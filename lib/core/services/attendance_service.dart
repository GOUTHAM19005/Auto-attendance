import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/database_helper.dart';

class AttendanceService extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;

  // ── Shift constants ──────────────────────────
  //  Full Day  : punch in ≤ 9:00am, punch out ≥ 4:00pm (7hrs / 420 mins)
  //  Half Day  : covers 9am–12pm (morning) OR 1pm–4pm (afternoon)
  //  Absent    : worked < 3 hours (180 mins)
  //  Leave     : punch in AT or AFTER 4:00pm
  //  Grace     : shortfall from 420 mins, MAX 60 mins/day
  //              deducted from monthly pool (limit read from DB)
  //  Auto-out  : 7:30pm if still punched in

  int _shiftStartH = 9;
  int _shiftStartM = 0;
  int _shiftEndH = 16;
  int _shiftEndM = 0;
  static const int _afternoonStartH = 13;
  static const int _afternoonStartM = 0;
  static const int _autoPunchOutH = 19;
  static const int _autoPunchOutM = 30;

  static const int _fullDayMins = 420;
  static const int _halfDayMins = 180;
  static const int _maxDailyGrace = 60;

  // ── State ────────────────────────────────────
  DateTime? punchIn;
  DateTime? finalPunchOut;
  bool _isPunchedIn = false;
  bool _isInside = false;
  String? _dayType;
  int _graceMinutes = 0;

  List<Map<String, dynamic>> _history = [];
  int _monthlyGraceTotal = 0;
  int _monthlyGraceLimit = 250; // loaded from DB on init

  // ── Getters ──────────────────────────────────
  bool get isPunchedIn => _isPunchedIn;
  bool get isInside => _isInside;
  String? get dayType => _dayType;
  int get graceMinutes => _graceMinutes;
  List<Map<String, dynamic>> get history => _history;
  int get monthlyGraceTotal => _monthlyGraceTotal;
  int get monthlyGraceLimit => _monthlyGraceLimit;

  // How many grace minutes are still available this month
  int get monthlyGraceRemaining => (_monthlyGraceLimit - _monthlyGraceTotal).clamp(0, _monthlyGraceLimit);

  // Called by dashboard whenever geofence state changes
  void updateIsInside(bool value) {
    if (_isInside == value) return;
    _isInside = value;
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  //  INIT
  // ─────────────────────────────────────────────

  Future<void> initializeUser() async {
    try {
      _monthlyGraceLimit = await _db.getMonthlyGraceLimit();
      await loadShiftTimings(); // load shift times from Firestore
      await loadTodayAttendance();
      await fetchHistory();
      debugPrint('AttendanceService: initialized. Grace limit: \$_monthlyGraceLimit mins/month');
      notifyListeners();
    } catch (e) {
      debugPrint('AttendanceService Init Error: \$e');
      rethrow;
    }
  }

  // ── Load shift timings from Firestore ────────
  Future<void> loadShiftTimings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists) return;
      final data = doc.data()!;

      if (data['shift_in'] != null) {
        final parts = (data['shift_in'] as String).split(':');
        _shiftStartH = int.parse(parts[0]);
        _shiftStartM = int.parse(parts[1]);
      }
      if (data['shift_out'] != null) {
        final parts = (data['shift_out'] as String).split(':');
        _shiftEndH = int.parse(parts[0]);
        _shiftEndM = int.parse(parts[1]);
      }

      debugPrint('AttendanceService: Shift timings loaded — $_shiftStartH:$_shiftStartM → $_shiftEndH:$_shiftEndM');
    } catch (e) {
      debugPrint('AttendanceService: Could not load shift timings — using defaults. \$e');
    }
  }

  Future<void> loadTodayAttendance() async {
    final now = DateTime.now();
    final date = _dateStr(now);
    final row = await _db.getAttendanceByDate(date);

    if (row == null) {
      _resetLocalState();
    } else {
      punchIn =
          row['punch_in'] != null ? DateTime.parse(row['punch_in']) : null;
      finalPunchOut =
          row['punch_out'] != null ? DateTime.parse(row['punch_out']) : null;
      _dayType = row['attendance_type'];
      _graceMinutes = row['used_grace_minutes'] ?? 0;
      _isPunchedIn = (row['is_active'] == 1);

      if (_isPunchedIn) _scheduleAutoPunchOut(now);
    }
    notifyListeners();
  }

  Future<void> fetchHistory() async {
    _history = await _db.getAllAttendance();
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    // Always reload from DB — never rely on local optimistic updates
    _monthlyGraceTotal = await _db.getMonthlyGraceTotal(monthKey);
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  //  PUBLIC PUNCH HANDLER
  // ─────────────────────────────────────────────

  Future<void> handlePunch(
      {required String punchType, DateTime? customDateTime}) async {
    final time = customDateTime ?? DateTime.now();
    await _handlePunch(time, punchType);
    // Reload grace total from DB after every punch — no local optimism
    await fetchHistory();
  }

  // ─────────────────────────────────────────────
  //  CORE PUNCH LOGIC
  // ─────────────────────────────────────────────

  Future<void> _handlePunch(DateTime time, String punchType) async {
    final date = _dateStr(time);
    final dateTimeStr = time.toString().substring(0, 19);
    final row = await _db.getAttendanceByDate(date);

    if (!_isPunchedIn) {
      // ── PUNCH IN ─────────────────────────────
      final shiftEnd =
          DateTime(time.year, time.month, time.day, _shiftEndH, _shiftEndM);

      // Punch-in at or after 4:00pm → mark as LEAVE immediately
      if (!time.isBefore(shiftEnd)) {
        debugPrint('AttendanceService: Punch-in at/after 4pm → LEAVE');
        int id;
        if (row == null) {
          id = await _db.insertPunchIn(
            date: date,
            punchInTime: dateTimeStr,
            punchType: punchType,
          );
        } else {
          id = row['id'];
        }
        await _db.updatePunchOut(
          attendanceId: id,
          punchOutTime: dateTimeStr,
          durationMinutes: 0,
          usedGraceMinutes: 0,
          attendanceType: 'LEAVE',
        );
        punchIn = time;
        finalPunchOut = time;
        _dayType = 'LEAVE';
        _graceMinutes = 0;
        _isPunchedIn = false;
        notifyListeners();
        return;
      }

      // Normal punch in
      if (row == null) {
        await _db.insertPunchIn(
          date: date,
          punchInTime: dateTimeStr,
          punchType: punchType,
        );
        punchIn = time;
      } else {
        await _db.updateAttendanceStatus(row['id'], 1);
        punchIn = DateTime.parse(row['punch_in']);
      }
      _isPunchedIn = true;
      _scheduleAutoPunchOut(time);
    } else {
      // ── PUNCH OUT ────────────────────────────
      final firstIn = DateTime.parse(row!['punch_in']);

      // Reload grace total fresh from DB before calculating
      // so we have the true pool size (not a stale local value)
      final monthKey =
          '${time.year}-${time.month.toString().padLeft(2, '0')}';
      _monthlyGraceTotal = await _db.getMonthlyGraceTotal(monthKey);

      final result = _calculateAttendance(firstIn, time);

      await _db.updatePunchOut(
        attendanceId: row['id'],
        punchOutTime: dateTimeStr,
        durationMinutes: time.difference(firstIn).inMinutes,
        usedGraceMinutes: result.graceUsed,
        attendanceType: result.type,
      );

      _isPunchedIn = false;
      punchIn = firstIn;
      finalPunchOut = time;
      _dayType = result.type;
      _graceMinutes = result.graceUsed;
      // Do NOT update _monthlyGraceTotal here — fetchHistory() will reload it from DB
    }
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  //  MANUAL OVERRIDE
  // ─────────────────────────────────────────────

  Future<void> manualOverridePunch({
    required DateTime selectedDate,
    required TimeOfDay inTime,
    required TimeOfDay outTime,
  }) async {
    final dateStr = _dateStr(selectedDate);
    final fullIn = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, inTime.hour, inTime.minute);
    final fullOut = DateTime(selectedDate.year, selectedDate.month,
        selectedDate.day, outTime.hour, outTime.minute);

    // Reload grace total for the selected date's month before calculating
    final monthKey =
        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}';
    _monthlyGraceTotal = await _db.getMonthlyGraceTotal(monthKey);

    final result = _calculateAttendance(fullIn, fullOut);

    await _db.insertManualOverride(
      date: dateStr,
      punchIn: fullIn.toString().substring(0, 19),
      punchOut: fullOut.toString().substring(0, 19),
      grace: result.graceUsed,
      type: result.type,
    );

    await fetchHistory();
    final today = DateTime.now();
    if (selectedDate.day == today.day &&
        selectedDate.month == today.month &&
        selectedDate.year == today.year) {
      await loadTodayAttendance();
    }
  }

  // ─────────────────────────────────────────────
  //  AUTO PUNCH-OUT AT 7:30 PM
  // ─────────────────────────────────────────────

  void _scheduleAutoPunchOut(DateTime fromTime) {
    final autoPunchOut = DateTime(
      fromTime.year,
      fromTime.month,
      fromTime.day,
      _autoPunchOutH,
      _autoPunchOutM,
    );
    final now = DateTime.now();
    final delay = autoPunchOut.difference(now);

    if (delay.isNegative) {
      if (_isPunchedIn) {
        debugPrint('AttendanceService: Past 7:30pm on load → auto punch-out.');
        handlePunch(punchType: 'auto', customDateTime: autoPunchOut);
      }
      return;
    }

    Future.delayed(delay, () {
      if (_isPunchedIn) {
        debugPrint('AttendanceService: 7:30pm hit → auto punch-out.');
        handlePunch(punchType: 'auto', customDateTime: autoPunchOut);
      }
    });
  }

  // ─────────────────────────────────────────────
  //  ATTENDANCE CALCULATION ENGINE
  // ─────────────────────────────────────────────
  //
  //  Step 0: punch-in ≥ 4:00pm              → LEAVE  (no grace)
  //  Step 1: duration < 3hrs (180 min)      → ABSENT (no grace)
  //  Step 2: late > 60 mins (after 10:00am) → HALF   (no grace)
  //  Step 3: shortfall = 420 - duration
  //    • shortfall ≤ 0                              → FULL  (no grace)
  //    • shortfall ≤ 60 AND monthly pool ≥ shortfall → FULL (grace deducted)
  //    • otherwise                                  → HALF  (no grace)

  _AttendanceResult _calculateAttendance(DateTime inT, DateTime outT) {
    final shiftStart =
        DateTime(inT.year, inT.month, inT.day, _shiftStartH, _shiftStartM);
    final shiftEnd =
        DateTime(inT.year, inT.month, inT.day, _shiftEndH, _shiftEndM);
    final afternoonSt = DateTime(
        inT.year, inT.month, inT.day, _afternoonStartH, _afternoonStartM);

    final durationMins = outT.difference(inT).inMinutes;

    // ── Step 0: Punch-in at or after 4:00pm → LEAVE ──
    if (!inT.isBefore(shiftEnd)) {
      return const _AttendanceResult(type: 'LEAVE', graceUsed: 0);
    }

    // ── Step 1: Punched but worked less than 3 hours → HALF ──
    if (durationMins < _halfDayMins) {
      return const _AttendanceResult(type: 'HALF', graceUsed: 0);
    }

    // ── Step 2: Calculate total shortfall ───────────
    // Shortfall = how many minutes short of a perfect full day
    // This includes BOTH late arrival AND early departure
    //
    // Perfect day = punch in at 9:00am, punch out at 4:00pm (420 mins)
    // If you arrived at 9:16 and left at 3:50:
    //   late = 16 mins, early = 10 mins, total shortfall = 26 mins grace used
    //
    final lateMins =
        inT.isAfter(shiftStart) ? inT.difference(shiftStart).inMinutes : 0;
    final earlyMins =
        outT.isBefore(shiftEnd) ? outT.difference(shiftEnd).inMinutes.abs() : 0;
    final totalShortfall = lateMins + earlyMins;

    // More than 60 mins late → HALF day, no grace
    if (lateMins > _maxDailyGrace) {
      return const _AttendanceResult(type: 'HALF', graceUsed: 0);
    }

    // ── Step 3: Grace shortfall check ───────────────
    // No shortfall at all — perfect attendance
    if (totalShortfall <= 0) {
      return const _AttendanceResult(type: 'FULL', graceUsed: 0);
    }

    // Shortfall within 60-min daily grace cap
    if (totalShortfall <= _maxDailyGrace) {
      final graceAvailable = _monthlyGraceLimit - _monthlyGraceTotal;
      if (graceAvailable >= totalShortfall) {
        // Monthly pool has enough — mark FULL, deduct grace
        return _AttendanceResult(type: 'FULL', graceUsed: totalShortfall);
      }
      // Pool exhausted — mark HALF
      return const _AttendanceResult(type: 'HALF', graceUsed: 0);
    }

    // Shortfall > 60 mins — too big for grace cap → HALF
    return const _AttendanceResult(type: 'HALF', graceUsed: 0);
  }

  // ─────────────────────────────────────────────
  //  HELPERS
  // ─────────────────────────────────────────────

  void _resetLocalState() {
    punchIn = null;
    finalPunchOut = null;
    _dayType = null;
    _graceMinutes = 0;
    _isPunchedIn = false;
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ── Result model ─────────────────────────────────

class _AttendanceResult {
  final String type; // 'FULL' | 'HALF' | 'ABSENT' | 'LEAVE'
  final int graceUsed; // actual minutes deducted from monthly pool

  const _AttendanceResult({required this.type, required this.graceUsed});
}