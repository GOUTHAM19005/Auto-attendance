import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/attendance_service.dart';
import '../../data/database_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Calendar state
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, Map<String, dynamic>> _monthRecords = {};
  bool _calendarLoading = true;

  // ── Colors ──────────────────────────────────
  static const _presentBg = Color(0xFFD4F0E0);
  static const _presentFg = Color(0xFF2D7A4F);
  static const _absentBg = Color(0xFFFDE8E6);
  static const _absentFg = Color(0xFFC0392B);
  static const _sundayBg = Color(0xFFF0F0F0);
  static const _sundayFg = Color(0xFF9B9B9B);
  static const _todayRing = Color(0xFFF4A228);

  @override
  void initState() {
    super.initState();
    _loadMonthData();
  }

  // ── Load attendance records for focused month from SQLite ──
  Future<void> _loadMonthData() async {
    setState(() => _calendarLoading = true);
    final all = await DatabaseHelper.instance.getAllAttendance();
    final yearMonth =
        '${_focusedMonth.year}-${_focusedMonth.month.toString().padLeft(2, '0')}';

    final Map<String, Map<String, dynamic>> filtered = {};
    for (final record in all) {
      final date = record['date'] as String? ?? '';
      if (date.startsWith(yearMonth)) {
        // key = "YYYY-MM-DD"
        filtered[date.substring(0, 10)] = record;
      }
    }
    setState(() {
      _monthRecords = filtered;
      _calendarLoading = false;
    });
  }

  void _prevMonth() {
    setState(() =>
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
    _loadMonthData();
  }

  void _nextMonth() {
    setState(() =>
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
    _loadMonthData();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Determine cell status from DB record ──
  String _statusFor(DateTime date) {
    final today = DateTime.now();
    if (date.isAfter(today) && date.day != today.day) return 'future';
    final record = _monthRecords[_dateKey(date)];
    if (record == null) return 'absent';
    final type = (record['attendance_type'] as String? ?? '').toUpperCase();
    if (type == 'LEAVE') return 'leave';
    if (type == 'HALF' || type == 'HALF DAY') return 'half';
    return 'present'; // Full Day or any punch_in record
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AttendanceService>().fetchHistory();
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Consumer<AttendanceService>(
        builder: (context, service, child) {
          return SingleChildScrollView(
            child: Column(
              children: [
                _buildMonthlyGraceCard(service),
                const SizedBox(height: 12),

                // ── CALENDAR ──────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildCalendarHeader(),
                          const SizedBox(height: 10),
                          _buildDayLabels(),
                          const SizedBox(height: 4),
                          _calendarLoading
                              ? const SizedBox(
                                  height: 180,
                                  child: Center(
                                      child: CircularProgressIndicator()))
                              : _buildGrid(),
                          const Divider(height: 24),
                          _buildLegend(),
                          const SizedBox(height: 4),
                          _buildStats(),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── HISTORY LIST ──────────────────────
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Recent Logs",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ),
                service.history.isEmpty
                    ? _buildEmptyState()
                    : _buildHistoryList(service),

                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Calendar Header (Month nav) ───────────────
  Widget _buildCalendarHeader() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _prevMonth,
          splashRadius: 20,
        ),
        Text(
          '${months[_focusedMonth.month - 1]} ${_focusedMonth.year}',
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _nextMonth,
          splashRadius: 20,
        ),
      ],
    );
  }

  // ── Sun Mon Tue … Sat labels ──────────────────
  Widget _buildDayLabels() {
    const labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return Row(
      children: labels
          .map((l) => Expanded(
                child: Center(
                  child: Text(l,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: l == 'Sun' ? _sundayFg : Colors.grey.shade500,
                      )),
                ),
              ))
          .toList(),
    );
  }

  // ── Calendar grid ─────────────────────────────
  Widget _buildGrid() {
    final today = DateTime.now();
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    // Flutter weekday: Mon=1…Sun=7 → convert to Sun=0 offset
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;

    final cells = <Widget>[];

    // Empty leading cells
    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      final isSunday = date.weekday == DateTime.sunday;
      final isToday = _dateKey(date) == _dateKey(today);
      final status = isSunday ? 'sunday' : _statusFor(date);

      Color bg, fg;
      IconData? icon;

      switch (status) {
        case 'present':
          bg = _presentBg;
          fg = _presentFg;
          break;
        case 'half':
          bg = const Color(0xFFFFF3CD);
          fg = const Color(0xFFB8860B);
          break;
        case 'absent':
          bg = _absentBg;
          fg = _absentFg;
          break;
        case 'sunday':
          bg = _sundayBg;
          fg = _sundayFg;
          break;
        case 'leave':
          bg = const Color(0xFFECEFF1);
          fg = Colors.blueGrey;
          break;
        default: // future
          bg = Colors.white;
          fg = Colors.grey.shade300;
      }

      cells.add(AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: _todayRing, width: 2.5)
              : status == 'future'
                  ? Border.all(color: Colors.grey.shade200, width: 1)
                  : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$d',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
            if (status == 'present' ||
                status == 'absent' ||
                status == 'half' ||
                status == 'leave')
              Container(
                width: 4,
                height: 4,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
              ),
          ],
        ),
      ));
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: cells,
    );
  }

  // ── Legend ────────────────────────────────────
  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        _legendDot(_presentBg, _presentFg, 'Present'),
        _legendDot(_absentBg, _absentFg, 'Absent'),
        _legendDot(
            const Color(0xFFFFF3CD), const Color(0xFFB8860B), 'Half Day'),
        _legendDot(_sundayBg, _sundayFg, 'Sunday'),
        _legendDot(const Color(0xFFECEFF1), Colors.blueGrey, 'Leave'),
      ],
    );
  }

  Widget _legendDot(Color bg, Color fg, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: fg.withOpacity(0.4))),
      ),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
    ]);
  }

  // ── Stats row ─────────────────────────────────
  Widget _buildStats() {
    final today = DateTime.now();
    final daysInMonth =
        DateUtils.getDaysInMonth(_focusedMonth.year, _focusedMonth.month);
    int present = 0, half = 0, absent = 0, sundays = 0;

    for (int d = 1; d <= daysInMonth; d++) {
      final date = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      if (date.isAfter(today)) continue;
      if (date.weekday == DateTime.sunday) {
        sundays++;
        continue;
      }
      final s = _statusFor(date);
      if (s == 'present')
        present++;
      else if (s == 'half')
        half++;
      else if (s == 'absent') absent++;
    }

    final total = present + half + absent;
    final pct =
        total > 0 ? ((present + half * 0.5) / total * 100).round() : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statChip('Present', present, _presentFg, _presentBg),
        _statChip('Absent', absent, _absentFg, _absentBg),
        _statChip(
            'Half', half, const Color(0xFFB8860B), const Color(0xFFFFF3CD)),
        if (pct != null)
          Column(children: [
            Text('$pct%',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _presentFg)),
            Text('attendance',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
      ],
    );
  }

  Widget _statChip(String label, int count, Color fg, Color bg) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text('$count',
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 15, color: fg)),
      ),
      const SizedBox(height: 4),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
    ]);
  }

  // ── Existing widgets (unchanged) ──────────────

  Widget _buildMonthlyGraceCard(AttendanceService service) {
    const int limit = 250;
    int used = service.monthlyGraceTotal;
    double progress = (used / limit).clamp(0.0, 1.0);
    Color progressColor = used > 200 ? Colors.red : Colors.orange;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Monthly Grace Usage",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("$used / $limit mins used",
                      style: TextStyle(
                          color: progressColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                  Text("${(progress * 100).toInt()}%"),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: progressColor,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryList(AttendanceService service) {
    return ListView.builder(
      itemCount: service.history.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemBuilder: (context, index) {
        final record = service.history[index];
        final isHalfDay = record['attendance_type'] == 'HALF';
        final grace = record['used_grace_minutes'] ?? 0;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: Icon(
              isHalfDay ? Icons.hourglass_bottom_rounded : Icons.check_circle,
              color: isHalfDay ? Colors.orange : Colors.green,
            ),
            title: Text(record['date'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              "In: ${record['punch_in']?.substring(11, 16) ?? '--:--'} | "
              "Out: ${record['punch_out']?.substring(11, 16) ?? '--:--'}",
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  record['attendance_type'] ?? 'FULL',
                  style: TextStyle(
                    color: isHalfDay ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (grace > 0)
                  Text("-$grace min",
                      style: const TextStyle(
                          color: Colors.red,
                          fontSize: 10,
                          fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.history_toggle_off, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text("No logs found yet.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
