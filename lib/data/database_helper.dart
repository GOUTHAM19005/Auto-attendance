import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();
  factory DatabaseHelper() => instance;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'attendance.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute(_createUserTable);
    await db.execute(_createAttendanceTable);
    await db.execute(_createGraceSummaryTable);
    await _insertDefaultUser(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE attendance ADD COLUMN attendance_type TEXT");
    }
    if (oldVersion < 3) {
      await db.execute(
          "ALTER TABLE attendance ADD COLUMN is_active INTEGER DEFAULT 0");
    }
  }

  static const String _createUserTable = '''
    CREATE TABLE user (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      monthly_grace_limit INTEGER NOT NULL
    )
  ''';

  static const String _createAttendanceTable = '''
    CREATE TABLE attendance (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      date TEXT NOT NULL UNIQUE,
      punch_in TEXT,
      punch_out TEXT,
      duration_minutes INTEGER,
      used_grace_minutes INTEGER DEFAULT 0,
      attendance_type TEXT,
      punch_type TEXT,
      edited INTEGER DEFAULT 0,
      is_active INTEGER DEFAULT 0
    )
  ''';

  static const String _createGraceSummaryTable = '''
    CREATE TABLE grace_summary (
      month TEXT PRIMARY KEY,
      total_used_minutes INTEGER,
      remaining_minutes INTEGER
    )
  ''';

  Future<void> _insertDefaultUser(Database db) async {
    await db.insert('user', {
      'id': 1,
      'name': 'User',
      'monthly_grace_limit': 250,
    });
  }

  // ── Read user's monthly grace limit from DB ──
  Future<int> getMonthlyGraceLimit() async {
    final db = await database;
    final result = await db.query('user', where: 'id = ?', whereArgs: [1]);
    if (result.isEmpty) return 250; // fallback
    return result.first['monthly_grace_limit'] as int;
  }

  Future<int> insertPunchIn({
    required String date,
    required String punchInTime,
    required String punchType,
  }) async {
    final db = await database;
    return await db.insert(
      'attendance',
      {
        'date': date,
        'punch_in': punchInTime,
        'punch_type': punchType,
        'is_active': 1,
        'edited': punchType == 'manual' ? 1 : 0,
      },
      // If a record already exists for this date, replace it
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updatePunchOut({
    required int attendanceId,
    required String punchOutTime,
    required int durationMinutes,
    required int usedGraceMinutes,
    required String attendanceType,
  }) async {
    final db = await database;
    return await db.update(
      'attendance',
      {
        'punch_out': punchOutTime,
        'duration_minutes': durationMinutes,
        'used_grace_minutes': usedGraceMinutes,
        'attendance_type': attendanceType,
        'is_active': 0,
      },
      where: 'id = ?',
      whereArgs: [attendanceId],
    );
  }

  Future<int> updateAttendanceStatus(int id, int isActive) async {
    final db = await database;
    return await db.update(
      'attendance',
      {'is_active': isActive},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Manual override: upsert so re-overriding the same date replaces correctly
  Future<int> insertManualOverride({
    required String date,
    required String punchIn,
    required String punchOut,
    required int grace,
    required String type,
  }) async {
    final db = await database;
    return await db.insert(
      'attendance',
      {
        'date': date,
        'punch_in': punchIn,
        'punch_out': punchOut,
        'duration_minutes': DateTime.parse(punchOut)
            .difference(DateTime.parse(punchIn))
            .inMinutes,
        'used_grace_minutes': grace,
        'attendance_type': type,
        'is_active': 0,
        'punch_type': 'manual_override',
        'edited': 1,
      },
      // Replace the existing row for that date if one exists
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getAttendanceByDate(String date) async {
    final db = await database;
    final result = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [date],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllAttendance() async {
    final db = await database;
    return await db.query('attendance', orderBy: 'date DESC');
  }

  // Sum grace used this month — monthKey format: 'YYYY-MM'
  Future<int> getMonthlyGraceTotal(String yearMonth) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT SUM(used_grace_minutes) as total FROM attendance WHERE date LIKE ?",
      ['$yearMonth%'],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('attendance');
    await db.delete('grace_summary');
  }
}