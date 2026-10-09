import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/run_session.dart';

/// Penyimpanan riwayat lari lokal berbasis SQLite.
///
/// Database disimpan di app-private storage Android, bukan di folder publik.
/// Data tetap ada setelah aplikasi ditutup atau perangkat di-restart.
class RunHistoryRepository {
  RunHistoryRepository._();

  static final RunHistoryRepository instance = RunHistoryRepository._();

  static const String _databaseName = 'voltstride_runs.db';
  static const String _tableName = 'run_sessions';
  static const int _databaseVersion = 1;

  Database? _database;

  Future<Database> get _db async {
    final Database? current = _database;
    if (current != null && current.isOpen) return current;

    final String basePath = await getDatabasesPath();
    final String databasePath = path.join(basePath, _databaseName);
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
            splitsJson TEXT NOT NULL
          )
        ''');
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

    return rows
        .map(RunSession.fromStorageMap)
        .toList(growable: false);
  }

  Future<void> delete(DateTime startedAt) async {
    final Database db = await _db;
    await db.delete(
      _tableName,
      where: 'startedAt = ?',
      whereArgs: <Object?>[startedAt.toUtc().toIso8601String()],
    );
  }

  Future<void> close() async {
    final Database? db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
