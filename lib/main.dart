import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

// Internal Imports
import 'core/theme/theme_controller.dart';
import 'core/services/attendance_service.dart';
import 'data/database_helper.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/signup_screen.dart';
import 'features/dashboard/main_dashboard.dart';

// ── Notification channel constants ───────────────
const String _notifChannelId = 'my_foreground';
const String _notifChannelName = 'Auto Attendance Service';
const int _notifId = 888;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyCm57xgXyvRLHTwY5cfDwp_DrwhljUKCno",
      appId: "1:859293807314:android:346d3ab5415259645df30b",
      messagingSenderId: "859293807314",
      projectId: "auto-attendance-624d7",
      storageBucket: "auto-attendance-624d7.firebasestorage.app",
    ),
  );

  await DatabaseHelper.instance.database;

  // ── CRITICAL: Create notification channel BEFORE service starts ──
  // This fixes CannotPostForegroundServiceNotificationException on
  // Android 13+ and MIUI 14
  await _createNotificationChannel();

  await _checkPermissions();
  await initializeService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController()),
        ChangeNotifierProvider(create: (_) => AttendanceService()),
      ],
      child: const MyApp(),
    ),
  );
}

// ── Create notification channel before service starts ────
Future<void> _createNotificationChannel() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize the plugin first
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // Create the channel with HIGH importance so Android accepts it
  // for foreground services
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _notifChannelId,
    _notifChannelName,
    description: 'Used for auto attendance background tracking',
    importance: Importance.high, // Must be high or max for foreground service
    enableVibration: false,
    playSound: false,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  debugPrint('Notification channel created: $_notifChannelId');
}

Future<void> _checkPermissions() async {
  await Permission.location.request();
  await Permission.locationAlways.request();
  await Permission.notification.request();

  // MIUI FIX: Request battery optimization exemption
  final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
  if (!batteryStatus.isGranted) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _notifChannelId, // Must match channel above
      initialNotificationTitle: 'Auto Attendance Active',
      initialNotificationContent: 'Monitoring college geofence...',
      foregroundServiceNotificationId: _notifId,
      autoStartOnBoot: true,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: "Auto Attendance Active",
      content: "Monitoring college geofence...",
    );

    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 5), (timer) async {
    try {
      final now = DateTime.now();

      // ── Auto punch-out at 7:30pm ─────────────────
      if (now.hour == 19 && now.minute >= 30 && now.minute < 35) {
        final date =
            "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
        final existing =
            await DatabaseHelper.instance.getAttendanceByDate(date);

        if (existing != null && existing['is_active'] == 1) {
          final punchOutTime = DateTime(now.year, now.month, now.day, 19, 30);
          final punchInDt = DateTime.parse(existing['punch_in']);
          final duration = punchOutTime.difference(punchInDt).inMinutes;

          String attendanceType;
          int graceUsed = 0;

          if (duration < 180) {
            attendanceType = 'ABSENT';
          } else {
            final shortfall = 420 - duration;
            if (shortfall <= 0) {
              attendanceType = 'FULL';
            } else if (shortfall <= 60) {
              attendanceType = 'FULL';
              graceUsed = shortfall;
            } else {
              attendanceType = 'HALF';
            }
          }

          await DatabaseHelper.instance.updatePunchOut(
            attendanceId: existing['id'],
            punchOutTime: punchOutTime.toString().substring(0, 19),
            durationMinutes: duration,
            usedGraceMinutes: graceUsed,
            attendanceType: attendanceType,
          );

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Auto Punch-Out ✓",
              content: "Punched out at 7:30 PM — $attendanceType",
            );
          }
        }
      }

      // ── Geofence check (working hours only) ──────
      if (now.hour >= 7 && now.hour < 16 && now.weekday < 6) {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15));

        double distance = Geolocator.distanceBetween(
            position.latitude, position.longitude, 9.359433, 76.646917);

        if (distance <= 100) {
          final date =
              "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final existing =
              await DatabaseHelper.instance.getAttendanceByDate(date);

          // Only auto punch-in if no record yet AND before 4pm
          if (existing == null) {
            await DatabaseHelper.instance.insertPunchIn(
              date: date,
              punchInTime: now.toString().substring(0, 19),
              punchType: "AUTO",
            );

            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: "Attendance Marked ✓",
                content:
                    "Auto-punched in at ${now.hour}:${now.minute.toString().padLeft(2, '0')}",
              );
            }
          }
        } else {
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Auto Attendance Active",
              content: "Distance: ${distance.toStringAsFixed(0)}m from college",
            );
          }
        }

        service.invoke(
            'update', {"current_distance": distance.toStringAsFixed(1)});
      }
    } catch (e) {
      debugPrint("Service Error: $e");
    }
  });
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async => true;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeController>(
        builder: (context, themeController, child) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: themeController.themeMode,
        theme: ThemeData(
            useMaterial3: true, colorSchemeSeed: const Color(0xFF4F46E5)),
        darkTheme: ThemeData.dark(useMaterial3: true),
        routes: {
          '/signup': (context) => const SignupScreen(),
          '/login': (context) => const LoginScreen(),
          '/dashboard': (context) => const MainDashboard(),
        },
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.hasData) return const MainDashboard();
            return const LoginScreen();
          },
        ),
      );
    });
  }
}
