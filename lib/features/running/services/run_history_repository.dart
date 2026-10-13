import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/run_session.dart';

/// Penyimpanan riwayat lari lokal berbasis SQLite.
///
/// Database disimpan di app-private storage Android. Data tetap ada setelah
/// aplikasi ditutup atau perangkat direstart, kecuali data aplikasi dihapus,
/// aplikasi dihapus instalasinya, atau sistem/perangkat menghapus data aplikasi.
class RunHistoryRepository {
  RunHistoryRepository._();

  static final RunHistoryRepository instance = RunHistoryRepository._();

  static const String _databaseName = 'voltstride_runs.db';
  static const String _tableName = 'run_sessions';
  static const int _databaseVersion = 2;
  static const String _backupFormat = 'voltstride-run-history';
  static const int _backupVersion = 1;

  Database? _database;

  Future<String> get databasePath async {
    final String basePath = await getDatabasesPath();
    return path.join(basePath, _databaseName);
  }

  Future<Database> get _db async {
    final Database? current = _database;
    if (current != null && current.isOpen) return current;

    final String databasePath = await this.databasePath;
    final Database opened = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            startedAt TEXT PRIMARY KEY,
            finishedAt TEXT,
            distanceMeters REAL NOT NULL,
            elapsedMilliseconds INTEGER NOT NULL,
            movingMilliseconds INTEGER NOT NULL,
            averagePaceSecondsPerKm REAL,
            currentPaceSecondsPerKm REAL,
            gpsAccuracyMeters REAL,
            acceptedPoints INTEGER NOT NULL,
            rejectedPoints INTEGER NOT NULL,
            routeJson TEXT NOT NULL,
            splitsJson TEXT NOT NULL,
            hundredMeterLapsJson TEXT NOT NULL DEFAULT '[]',
            intervalPlanJson TEXT
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN hundredMeterLapsJson TEXT NOT NULL DEFAULT '[]'",
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN intervalPlanJson TEXT',
          );
        }
      },
    );
    _database = opened;
    return opened;
  }

  Future<void> save(RunSession session) async {
    final Database db = await _db;
    await db.insert(
      _tableName,
      session.toStorageMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RunSession>> getAll({int? limit}) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      _tableName,
      orderBy: 'startedAt DESC',
      limit: limit,
    );

    return rows.map(RunSession.fromStorageMap).toList(growable: false);
  }

  Future<void> delete(DateTime startedAt) async {
    final Database db = await _db;
    await db.delete(
      _tableName,
      where: 'startedAt = ?',
      whereArgs: <Object?>[startedAt.toUtc().toIso8601String()],
    );
  }

  /// Membuat file cadangan JSON yang bisa disimpan di luar data aplikasi.
  /// Cadangan tidak mengandung API key atau data akun.
  Future<String> exportBackupJson() async {
    final List<RunSession> sessions = await getAll();
    final Map<String, Object?> backup = <String, Object?>{
      'format': _backupFormat,
      'version': _backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sessionCount': sessions.length,
      'sessions': sessions
          .map((RunSession session) => session.toStorageMap())
          .toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Menggabungkan cadangan yang valid tanpa menghapus sesi yang sudah ada.
  /// Jika startedAt sama, sesi dari cadangan menggantikan baris dengan kunci itu.
  Future<int> importBackupJson(String contents) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException('File bukan JSON cadangan yang valid.');
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _backupFormat ||
        decoded['version'] != _backupVersion ||
        decoded['sessions'] is! List<dynamic>) {
      throw const FormatException(
        'Format cadangan tidak cocok dengan VoltStride.',
      );
    }

    final List<dynamic> rawSessions = decoded['sessions'] as List<dynamic>;
    final List<RunSession> sessions = <RunSession>[];

    try {
      for (final dynamic raw in rawSessions) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Ada sesi dengan format yang salah.');
        }
        sessions.add(
          RunSession.fromStorageMap(Map<String, Object?>.from(raw)),
        );
      }
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException(
        'Data sesi di dalam cadangan rusak atau tidak lengkap.',
      );
    }

    final Database db = await _db;
    await db.transaction((Transaction transaction) async {
      for (final RunSession session in sessions) {
        await transaction.insert(
          _tableName,
          session.toStorageMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    return sessions.length;
  }

  /// Informasi diagnostik untuk membedakan database kosong dari database error.
  Future<Map<String, Object?>> diagnostics() async {
    final Database db = await _db;
    final String filePath = await databasePath;
    final File file = File(filePath);
    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $_tableName',
    );
    final List<Map<String, Object?>> integrityRows =
        await db.rawQuery('PRAGMA quick_check');
    final List<Map<String, Object?>> versionRows =
        await db.rawQuery('SELECT sqlite_version() AS version');

    return <String, Object?>{
      'databasePath': filePath,
      'fileExists': await file.exists(),
      'fileSizeBytes': await file.exists() ? await file.length() : 0,
      'sessionCount': Sqflite.firstIntValue(countRows) ?? 0,
      'integrity': integrityRows.isEmpty
          ? 'unknown'
          : integrityRows.first.values.first.toString(),
      'sqliteVersion': versionRows.isEmpty
          ? 'unknown'
          : versionRows.first['version']?.toString() ?? 'unknown',
    };
  }

  Future<void> close() async {
    final Database? db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
