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

// ── Single source of truth for campus location ───
const double _campusLat = 9.413113;
const double _campusLng = 76.64189;
const double _campusRadius = 75.0; // metres

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

Future<void> _createNotificationChannel() async {
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    _notifChannelId,
    _notifChannelName,
    description: 'Used for auto attendance background tracking',
    importance: Importance.high,
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
      notificationChannelId: _notifChannelId,
      initialNotificationTitle: 'Auto Attendance Active',
      initialNotificationContent: 'Monitoring campus geofence...',
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
      content: "Monitoring campus geofence...",
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
      final date =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

      // ── Auto punch-out at 7:30 PM ─────────────
      if (now.hour == 19 && now.minute >= 30 && now.minute < 35) {
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

      // ── Geofence check — weekdays, smart hours only ──────
      // Punch-in window : 7:00am – 11:00am
      // Punch-out window: 1:00pm – 8:00pm
      final bool isWeekday = now.weekday >= 1 && now.weekday <= 5;
      
      
      final bool isActiveWindow = now.hour >= 7 && now.hour < 20;

      if (!isWeekday || !isActiveWindow) {
        debugPrint('BgService: Outside active window — skipping');
        return;
      }

      // ── GPS position ──────────────────────────
      final Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15));

      final double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        _campusLat,
        _campusLng,
      );

      final bool insideCampus = distance <= _campusRadius;
      debugPrint(
          'BgService: distance=${distance.toStringAsFixed(1)}m inside=$insideCampus');

      if (insideCampus) {
        // ── Inside campus → punch in if no record ──
        final existing =
            await DatabaseHelper.instance.getAttendanceByDate(date);

        if (existing == null) {
          await DatabaseHelper.instance.insertPunchIn(
            date: date,
            punchInTime: now.toString().substring(0, 19),
            punchType: 'auto',
          );
          debugPrint('BgService: Punch IN recorded');

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Attendance Marked ✓",
              content:
                  "Auto-punched in at ${now.hour}:${now.minute.toString().padLeft(2, '0')}",
            );
          }
        }
      } else {
        // ── Outside campus → punch out if still active ──
        final existing =
            await DatabaseHelper.instance.getAttendanceByDate(date);

        if (existing != null && existing['is_active'] == 1) {
          final punchInDt = DateTime.parse(existing['punch_in']);
          final duration = now.difference(punchInDt).inMinutes;

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
            punchOutTime: now.toString().substring(0, 19),
            durationMinutes: duration,
            usedGraceMinutes: graceUsed,
            attendanceType: attendanceType,
          );
          debugPrint('BgService: Punch OUT recorded — $attendanceType');

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Punched Out ✓",
              content: "Left campus — $attendanceType",
            );
          }
        } else {
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Auto Attendance Active",
              content:
                  "Outside campus — ${distance.toStringAsFixed(0)}m away",
            );
          }
        }
      }

      service.invoke(
          'update', {"current_distance": distance.toStringAsFixed(1)});

    } catch (e) {
      debugPrint('BgService error: $e');
    }
  }); // end Timer.periodic
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