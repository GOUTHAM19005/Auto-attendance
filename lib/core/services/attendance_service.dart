import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../data/database_helper.dart';
import 'dropbox_backup_service.dart';

class AttendanceService extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final DropboxBackupService _dropbox = DropboxBackupService();

  // ── Shift times (loaded from Firestore, fallback to defaults) ────────────
  int _shiftStartH = 9;
  int _shiftStartM = 0;
  int _shiftEndH = 16;
  int _shiftEndM = 0;

  // ── Auto punch-out = shift end + 30 min buffer ───────────────────────────
  static const int _autoPunchOutBufferMins = 30;

  // ── Fixed constants ──────────────────────────────────────────────────────
  static const int _afternoonStartH = 13;
  static const int _afternoonStartM = 0;

  static const int _fullDayMins = 420;
  static const int _halfDayMins = 180;
  static const int _maxDailyGrace = 60;
  static const int _monthlyGraceLimit = 250;

  // ── State ────────────────────────────────────────────────────────────────
  DateTime? punchIn;
  DateTime? finalPunchOut;
  bool _isPunchedIn = false;
  bool isInside = false;
  String? _dayType;
  int _graceMinutes = 0;
  int _dynamicFullDayMins = _fullDayMins;

  List<Map<String, dynamic>> _history = [];
  int _monthlyGraceTotal = 0;

  // ── Getters ──────────────────────────────────────────────────────────────
  bool get isPunchedIn => _isPunchedIn;
  String? get dayType => _dayType;
  int get graceMinutes => _graceMinutes;
  List<Map<String, dynamic>> get history => _history;
  int get monthlyGraceTotal => _monthlyGraceTotal;
  int get monthlyGraceRemaining =>
      (_monthlyGraceLimit - _monthlyGraceTotal).clamp(0, _monthlyGraceLimit);

  TimeOfDay get shiftStart =>
      TimeOfDay(hour: _shiftStartH, minute: _shiftStartM);
  TimeOfDay get shiftEnd => TimeOfDay(hour: _shiftEndH, minute: _shiftEndM);

  TimeOfDay get autoPunchOutTime {
    final totalMins = _shiftEndH * 60 + _shiftEndM + _autoPunchOutBufferMins;
    return TimeOfDay(hour: (totalMins ~/ 60) % 24, minute: totalMins % 60);
  }

  // ─────────────────────────────────────────────
  //  INIT
  // ─────────────────────────────────────────────

  Future<void> initializeUser() async {
    try {
      await _loadShiftTimesFromFirestore();
      await _refreshMonthlyGraceTotal();
      await loadTodayAttendance();
      await fetchHistory();
      debugPrint('AttendanceService: initialized.');
      notifyListeners();
    } catch (e) {
      debugPrint('AttendanceService Init Error: $e');
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  //  LOAD SHIFT TIMES FROM FIRESTORE
  // ─────────────────────────────────────────────

  Future<void> _loadShiftTimesFromFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!doc.exists || doc.data() == null) return;
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

      final shiftMins = (_shiftEndH * 60 + _shiftEndM) -
          (_shiftStartH * 60 + _shiftStartM);
      _dynamicFullDayMins = shiftMins > 0 ? shiftMins : _fullDayMins;
    } catch (e) {
      debugPrint('AttendanceService: Could not load shift times. Using defaults.');
    }
  }

  // ─────────────────────────────────────────────
  //  GRACE TOTAL
  // ─────────────────────────────────────────────

  Future<void> _refreshMonthlyGraceTotal() async {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _monthlyGraceTotal = await _db.getMonthlyGraceTotal(monthKey);
  }

  // ─────────────────────────────────────────────
  //  LOAD TODAY & HISTORY
  // ─────────────────────────────────────────────

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
    await _refreshMonthlyGraceTotal();
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  //  PUBLIC PUNCH HANDLER
  // ─────────────────────────────────────────────

  Future<void> handlePunch(
      {required String punchType, DateTime? customDateTime}) async {
    final time = customDateTime ?? DateTime.now();
    await _loadShiftTimesFromFirestore();
    await _refreshMonthlyGraceTotal();
    await _handlePunch(time, punchType);
    await fetchHistory();

    // ── Auto Dropbox upload after punch if enabled ──
    await _autoUploadToDropbox(time);
  }

  // ─────────────────────────────────────────────
  //  DROPBOX AUTO UPLOAD
  // ─────────────────────────────────────────────

  Future<void> _autoUploadToDropbox(DateTime time) async {
    try {
      await _dropbox.autoUpload();
    } catch (e) {
      debugPrint('AttendanceService: Dropbox auto-upload error → $e');
    }
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

      if (!time.isBefore(shiftEnd)) {
        debugPrint('AttendanceService: Punch-in at/after shift end → LEAVE');
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

      if (row == null) {
        await _db.insertPunchIn(
          date: date,
          punchInTime: dateTimeStr,
          punchType: punchType,
        );
        punchIn = time;
      } else {
        // Re-punch in — reactivate existing row, keep original punch_in
        await _db.reactivatePunchIn(row['id']);
        punchIn = DateTime.parse(row['punch_in']);
        debugPrint('AttendanceService: Re-punch in, original time kept.');
      }

      _isPunchedIn = true;
      _scheduleAutoPunchOut(time);
    } else {
      // ── PUNCH OUT ────────────────────────────
      final firstIn = DateTime.parse(row!['punch_in']);
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

      debugPrint('AttendanceService: Punch out → ${result.type}, grace=${result.graceUsed}');
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

    await _loadShiftTimesFromFirestore();
    await _refreshMonthlyGraceTotal();

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

    // Auto upload after manual override too
    await _autoUploadToDropbox(selectedDate);
  }

  // ─────────────────────────────────────────────
  //  AUTO PUNCH-OUT (shift end + 30 min buffer)
  // ─────────────────────────────────────────────

  void _scheduleAutoPunchOut(DateTime fromTime) {
    final totalMins =
        _shiftEndH * 60 + _shiftEndM + _autoPunchOutBufferMins;
    final autoH = (totalMins ~/ 60) % 24;
    final autoM = totalMins % 60;

    final autoPunchOut = DateTime(
      fromTime.year,
      fromTime.month,
      fromTime.day,
      autoH,
      autoM,
    );

    final now = DateTime.now();
    final delay = autoPunchOut.difference(now);

    if (delay.isNegative) {
      if (_isPunchedIn) {
        handlePunch(punchType: 'auto', customDateTime: autoPunchOut);
      }
      return;
    }

    Future.delayed(delay, () {
      if (_isPunchedIn) {
        handlePunch(punchType: 'auto', customDateTime: autoPunchOut);
      }
    });
  }

  // ─────────────────────────────────────────────
  //  ATTENDANCE CALCULATION ENGINE
  // ─────────────────────────────────────────────

  _AttendanceResult _calculateAttendance(DateTime inT, DateTime outT) {
    final shiftStart =
        DateTime(inT.year, inT.month, inT.day, _shiftStartH, _shiftStartM);
    final shiftEnd =
        DateTime(inT.year, inT.month, inT.day, _shiftEndH, _shiftEndM);
    final afternoonSt = DateTime(
        inT.year, inT.month, inT.day, _afternoonStartH, _afternoonStartM);

    final durationMins = outT.difference(inT).inMinutes;

    if (!inT.isBefore(shiftEnd)) {
      return const _AttendanceResult(type: 'LEAVE', graceUsed: 0);
    }

    if (durationMins < _halfDayMins) {
      return const _AttendanceResult(type: 'ABSENT', graceUsed: 0);
    }

    final lateMins =
        inT.isAfter(shiftStart) ? inT.difference(shiftStart).inMinutes : 0;
    if (lateMins > _maxDailyGrace) {
      final type = inT.isBefore(afternoonSt) ? 'HALF' : 'ABSENT';
      return _AttendanceResult(type: type, graceUsed: 0);
    }

    final shortfall = _dynamicFullDayMins - durationMins;

    if (shortfall <= 0) {
      return const _AttendanceResult(type: 'FULL', graceUsed: 0);
    }

    if (shortfall <= _maxDailyGrace) {
      final graceAvailable = _monthlyGraceLimit - _monthlyGraceTotal;
      if (graceAvailable >= shortfall) {
        _monthlyGraceTotal += shortfall;
        return _AttendanceResult(type: 'FULL', graceUsed: shortfall);
      }
      return const _AttendanceResult(type: 'HALF', graceUsed: 0);
    }

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

class _AttendanceResult {
  final String type;
  final int graceUsed;
  const _AttendanceResult({required this.type, required this.graceUsed});
}