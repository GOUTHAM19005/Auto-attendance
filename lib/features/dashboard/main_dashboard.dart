import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../attendance/attendance_screen.dart';
import '../manual/manual_punch_screen.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';
import '../../core/services/location_service.dart';
import '../../core/services/geofence_service.dart';
import '../../core/services/attendance_service.dart';

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  final LocationService _locationService = LocationService();
  late final GeofenceService _geofenceService;
  bool _initialChecked = false;

  late List<AnimationController> _navControllers;
  late List<Animation<double>> _navScaleAnims;
  late AnimationController _appBarController;
  late Animation<double> _appBarFade;

  static const _indigo = Color(0xFF3949AB);
  static const _indigoDark = Color(0xFF1A237E);

  final List<_NavItem> _navItems = const [
    _NavItem(icon: Icons.dashboard_rounded, label: 'Home'),
    _NavItem(icon: Icons.touch_app_rounded, label: 'Manual'),
    _NavItem(icon: Icons.calendar_month_rounded, label: 'History'),
    _NavItem(icon: Icons.settings_rounded, label: 'Settings'),
  ];

  final List<Widget> _pages = const [
    AttendanceScreen(),
    ManualPunchScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();

    _navControllers = List.generate(
      4,
      (i) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 300),
      ),
    );
    _navScaleAnims = _navControllers
        .map((c) => Tween<double>(begin: 1.0, end: 1.25).animate(
              CurvedAnimation(parent: c, curve: Curves.elasticOut),
            ))
        .toList();

    _navControllers[0].forward();

    _appBarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _appBarFade = CurvedAnimation(
      parent: _appBarController,
      curve: Curves.easeOut,
    );
    _appBarController.forward();

    _geofenceService = GeofenceService(
      centerLat: 9.413113,
      centerLng: 76.64189,
      radiusInMeters: 75,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final attendanceService = context.read<AttendanceService>();
      try {
        await attendanceService.loadTodayAttendance();
        await attendanceService.loadShiftTimings();
        _startTracking(attendanceService);
      } catch (e) {
        debugPrint('Init Error: $e');
      }
    });
  }

  @override
  void dispose() {
    for (final c in _navControllers) {
      c.dispose();
    }
    _appBarController.dispose();
    super.dispose();
  }

  void _onNavTap(int index) {
    if (index == _currentIndex) return;
    HapticFeedback.lightImpact();
    _navControllers[_currentIndex].reverse();
    setState(() => _currentIndex = index);
    _navControllers[index]
      ..reset()
      ..forward();
  }

  void _startTracking(AttendanceService attendanceService) async {
    final allowed = await _locationService.ensurePermission();
    if (!allowed) {
      debugPrint('GeofenceTracking: Location permission denied');
      return;
    }

    debugPrint('GeofenceTracking: Stream started');

    _locationService.getPositionStream().listen(
      (position) {
        final now = DateTime.now();

        // Weekdays only, 7am–8pm single window
        final bool isWeekday = now.weekday >= 1 && now.weekday <= 5;
        final bool isActiveWindow = now.hour >= 7 && now.hour < 20;

        if (!isWeekday || !isActiveWindow) {
          attendanceService.updateIsInside(false);
          return;
        }

        final changed = _geofenceService.check(position);
        final inside = _geofenceService.isInside;

        debugPrint(
            'GeofenceTracking: lat=${position.latitude}, lng=${position.longitude}, inside=$inside, changed=$changed');

        // Always sync UI
        attendanceService.updateIsInside(inside);

        if (!_initialChecked) {
          _initialChecked = true;
          debugPrint('GeofenceTracking: Cold start — inside=$inside');
          if (inside && !attendanceService.isPunchedIn) {
            debugPrint('GeofenceTracking: Cold start punch IN');
            attendanceService.handlePunch(punchType: 'auto');
          }
          return;
        }

        if (!changed) return;

        if (inside) {
          debugPrint('GeofenceTracking: Entered campus → punch IN');
          if (!attendanceService.isPunchedIn) {
            attendanceService.handlePunch(punchType: 'auto');
          }
        } else {
          debugPrint('GeofenceTracking: Left campus → punch OUT');
          if (attendanceService.isPunchedIn) {
            attendanceService.handlePunch(punchType: 'auto');
          }
        }
      },
      onError: (e) => debugPrint('GeofenceTracking ERROR: $e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2FF),
      extendBody: true,

      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: FadeTransition(
          opacity: _appBarFade,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_indigoDark, _indigo],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0x443949AB),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),

                    Expanded(
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .doc(user?.uid)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.exists) {
                            final data =
                                snapshot.data!.data() as Map<String, dynamic>;
                            final name = data['name'] ?? 'Faculty Member';
                            final dept = data['department'] ?? 'General';
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.2,
                                    )),
                                Text(dept,
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 12,
                                    )),
                              ],
                            );
                          }
                          return Text(
                            user?.email ?? 'Loading...',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          );
                        },
                      ),
                    ),

                    Consumer<AttendanceService>(
                      builder: (_, service, __) {
                        final isIn = service.isPunchedIn;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isIn
                                ? Colors.green.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isIn
                                  ? Colors.greenAccent.withOpacity(0.5)
                                  : Colors.redAccent.withOpacity(0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isIn
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isIn ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  color: isIn
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: 8),

                    InkWell(
                      onTap: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.logout_rounded,
                            color: Colors.white70, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: child,
        ),
        child: KeyedSubtree(
          key: ValueKey(_currentIndex),
          child: _pages[_currentIndex],
        ),
      ),

      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_navItems.length, (i) {
              final selected = _currentIndex == i;
              return GestureDetector(
                onTap: () => _onNavTap(i),
                behavior: HitTestBehavior.opaque,
                child: ScaleTransition(
                  scale: _navScaleAnims[i],
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? _indigo.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            _navItems[i].icon,
                            key: ValueKey(selected),
                            color: selected ? _indigo : Colors.grey.shade400,
                            size: selected ? 26 : 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: selected ? 11 : 10,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w400,
                            color: selected ? _indigo : Colors.grey.shade400,
                          ),
                          child: Text(_navItems[i].label),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}