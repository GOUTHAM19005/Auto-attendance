import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/attendance_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _graceController;

  late Animation<double> _fadeAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _graceAnim;

  // Track last grace value to re-animate on change
  double _lastGraceProgress = 0;

  @override
  void initState() {
    super.initState();

    // Staggered fade-in for cards
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward();

    // Pulse for the status orb
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Grace progress sweep animation
    _graceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _graceAnim = CurvedAnimation(
      parent: _graceController,
      curve: Curves.easeOutExpo,
    );
    _graceController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _graceController.dispose();
    super.dispose();
  }

  void _animateGraceIfChanged(double newProgress) {
    if ((newProgress - _lastGraceProgress).abs() > 0.001) {
      _lastGraceProgress = newProgress;
      _graceController
        ..reset()
        ..forward();
    }
  }

  // ── Color palette ────────────────────────────
  static const _indigo = Color(0xFF3949AB);
  static const _indigoDark = Color(0xFF1A237E);
  static const _teal = Color(0xFF00897B);
  static const _amber = Color(0xFFFFA000);
  static const _cardBg = Color(0xFFF8F9FF);

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AttendanceService>();
    final bool isInside = service.isPunchedIn;
    final bool hasPunchedIn = service.punchIn != null;

    const int totalGrace = 250;
    final int monthlyUsed = service.monthlyGraceTotal;
    final int graceLeft = (totalGrace - monthlyUsed).clamp(0, totalGrace);
    final double graceProgress = (graceLeft / totalGrace).clamp(0.0, 1.0);
    _animateGraceIfChanged(graceProgress);

    final Color graceColor = graceLeft < 50
        ? Colors.red.shade400
        : graceLeft < 150
            ? Colors.orange.shade600
            : _teal;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2FF),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // ── Hero header ───────────────────
              _buildHeroHeader(isInside, service, context),

              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    // ── Punch time row ────────────
                    _buildPunchRow(service, context),

                    const SizedBox(height: 14),

                    // ── Status + Grace row ────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day status card
                        Expanded(
                          flex: 5,
                          child: _buildDayStatusCard(service, hasPunchedIn),
                        ),
                        const SizedBox(width: 12),
                        // Compact grace card
                        Expanded(
                          flex: 5,
                          child: _buildCompactGraceCard(
                            graceLeft,
                            monthlyUsed,
                            totalGrace,
                            graceProgress,
                            graceColor,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // ── Quick stats row ───────────
                    _buildQuickStats(service),

                    const SizedBox(height: 20),

                    // ── Manual punch button ───────
                    _buildPunchButton(context, service, isInside),

                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Hero header with gradient + pulse orb ────
  Widget _buildHeroHeader(
      bool isInside, AttendanceService service, BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_indigoDark, _indigo],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: _indigo.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        children: [
          // Date & time
          Text(
            _todayLabel(),
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 20),

          // Pulse orb
          ScaleTransition(
            scale: isInside ? _pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isInside
                    ? Colors.green.withOpacity(0.18)
                    : Colors.red.withOpacity(0.18),
                border: Border.all(
                  color: isInside ? Colors.greenAccent : Colors.redAccent,
                  width: 2.5,
                ),
              ),
              child: Icon(
                isInside
                    ? Icons.location_on_rounded
                    : Icons.location_off_rounded,
                color: isInside ? Colors.greenAccent : Colors.redAccent,
                size: 46,
              ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            isInside ? 'Inside Campus' : 'Outside Campus',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isInside ? 'Auto attendance is active' : 'Auto attendance inactive',
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Punch In / Out time row ───────────────────
  Widget _buildPunchRow(AttendanceService service, BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _infoTile(
            icon: Icons.login_rounded,
            iconColor: _teal,
            label: 'Punch In',
            value: service.punchIn == null
                ? '--:--'
                : TimeOfDay.fromDateTime(service.punchIn!).format(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _infoTile(
            icon: Icons.logout_rounded,
            iconColor: Colors.deepOrange,
            label: 'Punch Out',
            value: service.finalPunchOut == null
                ? '--:--'
                : TimeOfDay.fromDateTime(service.finalPunchOut!)
                    .format(context),
          ),
        ),
      ],
    );
  }

  Widget _infoTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
              Text(value,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A2E))),
            ],
          ),
        ],
      ),
    );
  }

  // ── Day status card ───────────────────────────
  Widget _buildDayStatusCard(AttendanceService service, bool hasPunchedIn) {
    if (!hasPunchedIn) {
      return _glassCard(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.pending_outlined, color: Colors.grey.shade400, size: 32),
            const SizedBox(height: 8),
            const Text('Not Started',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey)),
            const SizedBox(height: 4),
            Text('No punch today',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    final isHalf = service.dayType == 'HALF';
    final isLeave = service.dayType == 'LEAVE';
    final isAbsent = service.dayType == 'ABSENT';
    final Color color = isLeave
        ? Colors.blueGrey
        : isAbsent
            ? Colors.red.shade400
            : isHalf
                ? Colors.orange
                : _teal;
    final IconData ic = isLeave
        ? Icons.event_busy_rounded
        : isAbsent
            ? Icons.cancel_rounded
            : isHalf
                ? Icons.hourglass_bottom_rounded
                : Icons.check_circle_rounded;

    return _glassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(ic, color: color, size: 34),
          const SizedBox(height: 8),
          Text(
            service.dayType ?? 'IN PROGRESS',
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14, color: color),
          ),
          const SizedBox(height: 4),
          Text(
            'Grace today: ${service.graceMinutes} min',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ── Compact grace card (no more giant circle) ─
  Widget _buildCompactGraceCard(
    int graceLeft,
    int monthlyUsed,
    int totalGrace,
    double graceProgress,
    Color color,
  ) {
    return _glassCard(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Mini arc indicator
          SizedBox(
            width: 72,
            height: 72,
            child: AnimatedBuilder(
              animation: _graceAnim,
              builder: (_, __) => Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: graceProgress * _graceAnim.value,
                    strokeWidth: 7,
                    color: color,
                    backgroundColor: Colors.grey.shade200,
                    strokeCap: StrokeCap.round,
                  ),
                  Center(
                    child: Text(
                      '$graceLeft',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Grace Left',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A2E))),
          const SizedBox(height: 2),
          Text('$monthlyUsed / $totalGrace min',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ── Quick stats strip ─────────────────────────
  Widget _buildQuickStats(AttendanceService service) {
    final int used = service.monthlyGraceTotal;
    final int left = (250 - used).clamp(0, 250);
    final pct = ((left / 250) * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _quickStat('Grace Used', '$used min', Colors.redAccent),
          _divider(),
          _quickStat('Grace Left', '$left min', _teal),
          _divider(),
          _quickStat('Balance', '$pct%', _indigo),
        ],
      ),
    );
  }

  Widget _quickStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _divider() =>
      Container(height: 36, width: 1, color: Colors.grey.shade200);

  // ── Animated punch button ─────────────────────
  Widget _buildPunchButton(
      BuildContext context, AttendanceService service, bool isPunchedIn) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.95, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: isPunchedIn ? Colors.redAccent : _indigo,
            foregroundColor: Colors.white,
            elevation: 6,
            shadowColor: (isPunchedIn ? Colors.red : _indigo).withOpacity(0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: Icon(
            isPunchedIn ? Icons.logout_rounded : Icons.fingerprint_rounded,
            size: 22,
          ),
          label: Text(
            isPunchedIn ? 'Manual Punch Out' : 'Manual Punch In',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
          onPressed: () async {
            await service.handlePunch(punchType: 'manual');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: isPunchedIn ? Colors.red.shade400 : _teal,
                  content: Text(
                    isPunchedIn
                        ? '✓ Punched Out Successfully'
                        : '✓ Punched In Successfully',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  // ── Reusable glass card ───────────────────────
  Widget _glassCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ── Helpers ───────────────────────────────────
  String _todayLabel() {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}
