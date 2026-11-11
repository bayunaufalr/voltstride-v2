import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/run_session.dart';
import 'training_plan_service.dart';
import '../../reminders/reminder_service.dart';

class SavedTrainingPlan {
  const SavedTrainingPlan({
    required this.id,
    required this.title,
    required this.strategy,
    required this.goal,
    required this.startDate,
    required this.endDate,
    required this.durationDays,
    required this.summary,
    required this.targetDescription,
    required this.targetDistanceKm,
    required this.targetPaceSecondsPerKm,
    required this.targetFinishMinutes,
    required this.targetVo2Max,
    required this.sessionMinutes,
    required this.sessionHour,
    required this.sessionMinute,
    required this.trainingWeekdays,
    required this.loadDescription,
    required this.advantages,
    required this.disadvantages,
    required this.reviewPrompted,
  });

  final String id;
  final String title;
  final TrainingStrategy strategy;
  final TrainingGoal goal;
  final DateTime startDate;
  final DateTime endDate;
  final int durationDays;
  final String summary;
  final String targetDescription;
  final double? targetDistanceKm;
  final int? targetPaceSecondsPerKm;
  final int? targetFinishMinutes;
  final double? targetVo2Max;
  final int sessionMinutes;
  final int sessionHour;
  final int sessionMinute;
  final List<int> trainingWeekdays;
  final String loadDescription;
  final List<String> advantages;
  final List<String> disadvantages;
  final bool reviewPrompted;
}

class PlannedTrainingSession {
  const PlannedTrainingSession({
    required this.planId,
    required this.planTitle,
    required this.day,
  });

  final String planId;
  final String planTitle;
  final TrainingPlanDay day;
}

TrainingEffort? _effortFromName(String? value) {
  for (final TrainingEffort effort in TrainingEffort.values) {
    if (effort.name == value) return effort;
  }
  if (value == 'tooEasy') return TrainingEffort.tooLight;
  return null;
}

class TrainingPlanRepository {
  TrainingPlanRepository._();

  static final TrainingPlanRepository instance = TrainingPlanRepository._();
  static const String _databaseName = 'voltstride_training_plans.db';
  static const int _databaseVersion = 4;
  Database? _database;
  final Map<String, Future<void>> _ownerPreparation = <String, Future<void>>{};

  String get _ownerId {
    if (Firebase.apps.isEmpty) return 'guest';
    return FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  }

  Future<Database> get _db async {
    final Database? current = _database;
    if (current != null && current.isOpen) {
      await _prepareOwnerData(current);
      return current;
    }
    final String basePath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(basePath, _databaseName),
      version: _databaseVersion,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE training_plans (
            id TEXT PRIMARY KEY,
            ownerId TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            startDate TEXT NOT NULL,
            endDate TEXT NOT NULL,
            goal TEXT NOT NULL,
            strategy TEXT NOT NULL,
            planJson TEXT NOT NULL,
            reviewPrompted INTEGER NOT NULL DEFAULT 0,
            active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE UNIQUE INDEX training_plans_one_active_per_owner
          ON training_plans(ownerId) WHERE active = 1
        ''');
        await db.execute('''
          CREATE TABLE training_plan_days (
            dayId TEXT PRIMARY KEY,
            planId TEXT NOT NULL,
            ownerId TEXT NOT NULL,
            dateKey TEXT NOT NULL,
            dayJson TEXT NOT NULL,
            completed INTEGER NOT NULL DEFAULT 0,
            missed INTEGER NOT NULL DEFAULT 0,
            effort TEXT,
            sessionStartedAt TEXT,
            FOREIGN KEY (planId) REFERENCES training_plans(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('''
          CREATE INDEX training_plan_days_by_date
          ON training_plan_days(ownerId, dateKey)
        ''');
        await db.execute('''
          CREATE TABLE training_session_feedback (
            id TEXT PRIMARY KEY,
            ownerId TEXT NOT NULL,
            startedAt TEXT NOT NULL,
            effort TEXT NOT NULL,
            planId TEXT,
            dayId TEXT
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE training_plans ADD COLUMN active INTEGER NOT NULL DEFAULT 1',
          );
          await db.execute(
            'ALTER TABLE training_plan_days ADD COLUMN missed INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute('UPDATE training_plans SET active = 0');
          await db.execute('''
            UPDATE training_plans SET active = 1
            WHERE id IN (
              SELECT latest.id
              FROM training_plans AS latest
              WHERE latest.rowid = (
                SELECT candidate.rowid
                FROM training_plans AS candidate
                WHERE candidate.ownerId = latest.ownerId
                ORDER BY candidate.createdAt DESC, candidate.rowid DESC
                LIMIT 1
              )
            )
          ''');
        }
        if (oldVersion < 4) {
          await db.execute('UPDATE training_plans SET active = 0');
          await db.execute('''
            UPDATE training_plans SET active = 1
            WHERE id IN (
              SELECT latest.id
              FROM training_plans AS latest
              WHERE latest.rowid = (
                SELECT candidate.rowid
                FROM training_plans AS candidate
                WHERE candidate.ownerId = latest.ownerId
                ORDER BY candidate.createdAt DESC, candidate.rowid DESC
                LIMIT 1
              )
            )
          ''');
          await db.execute('''
            CREATE UNIQUE INDEX training_plans_one_active_per_owner
            ON training_plans(ownerId) WHERE active = 1
          ''');
        }
      },
    );
    await _prepareOwnerData(_database!);
    return _database!;
  }

  Future<void> _prepareOwnerData(Database db) async {
    final String ownerId = _ownerId;
    if (ownerId == 'guest') {
      _ownerPreparation.clear();
      return;
    }
    final Future<void>? pending = _ownerPreparation[ownerId];
    if (pending != null) {
      await pending;
      return;
    }
    final Future<void> operation = _adoptGuestPlanData(db, ownerId);
    _ownerPreparation[ownerId] = operation;
    try {
      await operation;
    } catch (_) {
      _ownerPreparation.remove(ownerId);
      rethrow;
    }
  }

  Future<void> _adoptGuestPlanData(Database db, String ownerId) async {
    await db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> accountPlans = await txn.query(
        'training_plans',
        columns: <String>['id'],
        where: 'ownerId = ?',
        whereArgs: <Object?>[ownerId],
        limit: 1,
      );
      if (accountPlans.isNotEmpty) return;
      final List<Map<String, Object?>> guestPlans = await txn.query(
        'training_plans',
        columns: <String>['id'],
        where: 'ownerId = ?',
        whereArgs: const <Object?>['guest'],
        limit: 1,
      );
      if (guestPlans.isEmpty) return;
      await txn.update(
        'training_plans',
        <String, Object?>{'ownerId': ownerId},
        where: 'ownerId = ?',
        whereArgs: const <Object?>['guest'],
      );
      await txn.update(
        'training_plan_days',
        <String, Object?>{'ownerId': ownerId},
        where: 'ownerId = ?',
        whereArgs: const <Object?>['guest'],
      );
      await txn.update(
        'training_session_feedback',
        <String, Object?>{'ownerId': ownerId},
        where: 'ownerId = ?',
        whereArgs: const <Object?>['guest'],
      );
    });
  }

  Future<String> savePlan({
    required TrainingPlanRequest request,
    required TrainingPlanOption option,
  }) async {
    final Database db = await _db;
    final String id = 'plan_${DateTime.now().microsecondsSinceEpoch}';
    final DateTime start = DateTime(
      request.startDate.year,
      request.startDate.month,
      request.startDate.day,
    );
    final DateTime end = DateTime(
      start.year,
      start.month,
      start.day + request.durationDays - 1,
    );
    final List<Map<String, Object?>> previousPlans = await db.query(
      'training_plans',
      where: 'ownerId = ?',
      whereArgs: <Object?>[_ownerId],
      orderBy: 'createdAt DESC',
    );
    final List<String> replacedIds = previousPlans
        .map((Map<String, Object?> row) => row['id'] as String)
        .toList(growable: false);
    final Map<String, List<DateTime>> replacedDates = <String, List<DateTime>>{};
    final Map<int, TrainingEffort?> completedEffortBySession =
        <int, TrainingEffort?>{};

    for (final String previousId in replacedIds) {
      final List<Map<String, Object?>> oldRows = await db.query(
        'training_plan_days',
        where: 'planId = ? AND ownerId = ?',
        whereArgs: <Object?>[previousId, _ownerId],
        orderBy: 'dateKey ASC',
      );
      replacedDates[previousId] = oldRows
          .map((Map<String, Object?> row) =>
              DateTime.parse(row['dateKey'] as String))
          .toList(growable: false);

      int sessionOrdinal = 0;
      for (final Map<String, Object?> row in oldRows) {
        final Map<String, dynamic> dayJson =
            jsonDecode(row['dayJson'] as String) as Map<String, dynamic>;
        if (dayJson['isRestDay'] == true) continue;
        sessionOrdinal++;
        if ((row['completed'] as num?)?.toInt() != 1 ||
            (row['missed'] as num?)?.toInt() == 1 ||
            completedEffortBySession.containsKey(sessionOrdinal)) {
          continue;
        }
        completedEffortBySession[sessionOrdinal] =
            _effortFromName(row['effort'] as String?);
      }
    }

    final Map<String, Object?> target = <String, Object?>{
      'targetDistanceKm': request.targetDistanceKm,
      'targetPaceSecondsPerKm': request.targetPaceSecondsPerKm,
      'targetFinishMinutes': request.targetFinishMinutes,
      'targetVo2Max': request.targetVo2Max,
      'sessionMinutes': request.sessionMinutes,
      'trainingWeekdays': request.trainingWeekdays,
    };
    final Map<String, Object?> planJson = <String, Object?>{
      'title': option.title,
      'summary': option.summary,
      'target': target,
      'advantages': option.advantages,
      'disadvantages': option.disadvantages,
      'loadDescription': option.loadDescription,
      'durationDays': request.durationDays,
      'sessionHour': request.sessionHour,
      'sessionMinute': request.sessionMinute,
    };

    await db.transaction((Transaction txn) async {
      await txn.update(
        'training_plans',
        <String, Object?>{'active': 0},
        where: 'ownerId = ? AND active = 1',
        whereArgs: <Object?>[_ownerId],
      );
      await txn.insert('training_plans', <String, Object?>{
        'id': id,
        'ownerId': _ownerId,
        'createdAt': DateTime.now().toIso8601String(),
        'startDate': _dateKey(start),
        'endDate': _dateKey(end),
        'goal': request.goal.name,
        'strategy': option.strategy.name,
        'planJson': jsonEncode(planJson),
        'reviewPrompted': 0,
        'active': 1,
      });

      int sessionOrdinal = 0;
      for (final TrainingPlanDay day in option.days) {
        if (!day.isRestDay) sessionOrdinal++;
        final bool completed =
            !day.isRestDay && completedEffortBySession.containsKey(sessionOrdinal);
        final TrainingEffort? effort = completed
            ? completedEffortBySession[sessionOrdinal]
            : null;
        final String key = _dateKey(day.date);
        final TrainingPlanDay savedDay = TrainingPlanDay(
          id: '${id}_$key',
          date: day.date,
          title: day.title,
          description: day.description,
          activityType: day.activityType,
          durationMinutes: day.durationMinutes,
          intensity: day.intensity,
          isRestDay: day.isRestDay,
          intervalPlan: day.intervalPlan,
          completed: completed,
          effort: effort,
        );
        await txn.insert('training_plan_days', <String, Object?>{
          'dayId': savedDay.id,
          'planId': id,
          'ownerId': _ownerId,
          'dateKey': key,
          'dayJson': jsonEncode(savedDay.toJson()),
          'completed': completed ? 1 : 0,
          'missed': 0,
          'effort': effort?.name,
        });
      }

      if (replacedIds.isNotEmpty) {
        await txn.delete(
          'training_plan_days',
          where: 'ownerId = ? AND planId != ?',
          whereArgs: <Object?>[_ownerId, id],
        );
        await txn.delete(
          'training_plans',
          where: 'ownerId = ? AND id != ?',
          whereArgs: <Object?>[_ownerId, id],
        );
      }
    });

    for (final String previousId in replacedIds) {
      try {
        await ReminderService.cancelTrainingPlanNotifications(
          previousId,
          replacedDates[previousId] ?? const <DateTime>[],
        );
        await ReminderService.cancelTrainingPlanReview(previousId);
      } catch (_) {}
    }
    return id;
  }

  Future<SavedTrainingPlan?> getPlan(String id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plans',
      where: 'id = ? AND ownerId = ?',
      whereArgs: <Object?>[id, _ownerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _decodePlan(rows.first);
  }

  Future<List<SavedTrainingPlan>> getPlans({int limit = 12}) async {
    if (limit < 1) return <SavedTrainingPlan>[];
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plans',
      where: 'ownerId = ? AND active = 1',
      whereArgs: <Object?>[_ownerId],
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    return rows.map(_decodePlan).toList(growable: false);
  }

  Future<SavedTrainingPlan?> getCurrentPlan() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plans',
      where: 'ownerId = ? AND active = 1',
      whereArgs: <Object?>[_ownerId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _decodePlan(rows.first);
  }

  Future<List<TrainingPlanDay>> getDays(String planId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plan_days',
      where: 'planId = ? AND ownerId = ?',
      whereArgs: <Object?>[planId, _ownerId],
      orderBy: 'dateKey ASC',
    );
    return rows.map((Map<String, Object?> row) {
      final Map<String, dynamic> json = jsonDecode(row['dayJson'] as String)
          as Map<String, dynamic>;
      json['completed'] = (row['completed'] as num?)?.toInt() == 1;
      json['effort'] = row['effort'] as String?;
      json['notCompleted'] = (row['missed'] as num?)?.toInt() == 1;
      return TrainingPlanDay.fromJson(json);
    }).toList(growable: false);
  }

  Future<TrainingPlanDay?> getDay(String dayId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plan_days',
      where: 'dayId = ? AND ownerId = ?',
      whereArgs: <Object?>[dayId, _ownerId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, dynamic> json =
        jsonDecode(rows.first['dayJson'] as String) as Map<String, dynamic>;
    json['completed'] = (rows.first['completed'] as num?)?.toInt() == 1;
    json['effort'] = rows.first['effort'] as String?;
    json['notCompleted'] = (rows.first['missed'] as num?)?.toInt() == 1;
    return TrainingPlanDay.fromJson(json);
  }

  Future<void> deletePlan(String planId) async {
    final List<TrainingPlanDay> days = await getDays(planId);
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.delete(
        'training_plan_days',
        where: 'planId = ? AND ownerId = ?',
        whereArgs: <Object?>[planId, _ownerId],
      );
      await txn.delete(
        'training_plans',
        where: 'id = ? AND ownerId = ?',
        whereArgs: <Object?>[planId, _ownerId],
      );
    });
    try {
      await ReminderService.cancelTrainingPlanNotifications(
        planId,
        days.map((TrainingPlanDay day) => day.date),
      );
      await ReminderService.cancelTrainingPlanReview(planId);
    } catch (_) {}
  }

  Future<void> markDayNotCompleted(String dayId) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plan_days',
      where: 'dayId = ? AND ownerId = ?',
      whereArgs: <Object?>[dayId, _ownerId],
      limit: 1,
    );
    if (rows.isEmpty || (rows.first['completed'] as num?)?.toInt() == 1) return;
    final Map<String, dynamic> json =
        jsonDecode(rows.first['dayJson'] as String) as Map<String, dynamic>;
    json['notCompleted'] = true;
    await db.update(
      'training_plan_days',
      <String, Object?>{'missed': 1, 'dayJson': jsonEncode(json)},
      where: 'dayId = ? AND ownerId = ?',
      whereArgs: <Object?>[dayId, _ownerId],
    );
    try {
      await ReminderService.cancelTrainingPlanDayNotification(
        rows.first['planId'] as String,
        rows.first['dateKey'] as String,
      );
    } catch (_) {}
  }

  Future<void> restoreUpcomingNotifications() async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<SavedTrainingPlan> plans = await getPlans(limit: 12);
    for (final SavedTrainingPlan plan in plans) {
      final List<TrainingPlanDay> days = await getDays(plan.id);
      for (final TrainingPlanDay day in days) {
        if (day.isRestDay || day.completed || day.notCompleted ||
            day.date.isBefore(today)) {
          continue;
        }
        try {
          await ReminderService.scheduleTrainingPlanSessionReminder(
            planId: plan.id,
            dayId: day.id,
            date: day.date,
            title: day.title,
            sessionHour: plan.sessionHour,
            sessionMinute: plan.sessionMinute,
          );
        } catch (_) {}
      }
      final DateTime endDate = DateTime(
        plan.endDate.year,
        plan.endDate.month,
        plan.endDate.day,
      );
      if (!plan.reviewPrompted && !endDate.isBefore(today)) {
        try {
          await ReminderService.scheduleTrainingPlanReview(
            planId: plan.id,
            endDate: endDate,
          );
        } catch (_) {}
      }
    }
  }

  Future<PlannedTrainingSession?> getTodayPendingSession() async {
    final SavedTrainingPlan? plan = await getCurrentPlan();
    if (plan == null) return null;
    final String today = _dateKey(DateTime.now());
    final List<Map<String, Object?>> rows = await (await _db).query(
      'training_plan_days',
      where: 'planId = ? AND ownerId = ? AND dateKey = ? AND completed = 0 AND missed = 0',
      whereArgs: <Object?>[plan.id, _ownerId, today],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final Map<String, dynamic> json =
        jsonDecode(rows.first['dayJson'] as String) as Map<String, dynamic>;
    json['completed'] = false;
    json['notCompleted'] = false;
    final TrainingPlanDay day = TrainingPlanDay.fromJson(json);
    if (day.isRestDay) return null;
    return PlannedTrainingSession(planId: plan.id, planTitle: plan.title, day: day);
  }

  Future<List<TrainingPlanDay>> previewAdjustedDays({
    required String planId,
    required DateTime afterDate,
    required TrainingEffort effort,
  }) async {
    if (effort == TrainingEffort.normal) return <TrainingPlanDay>[];
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      'training_plan_days',
      where: 'planId = ? AND ownerId = ? AND dateKey > ? AND completed = 0 AND missed = 0',
      whereArgs: <Object?>[planId, _ownerId, _dateKey(afterDate.toLocal())],
      orderBy: 'dateKey ASC',
    );
    return rows.map((Map<String, Object?> row) {
      final Map<String, dynamic> json = jsonDecode(row['dayJson'] as String) as Map<String, dynamic>;
      return _adjustDay(TrainingPlanDay.fromJson(json), effort);
    }).toList(growable: false);
  }

  Future<SavedTrainingPlan?> getPlanNeedingReview() async {
    final Database db = await _db;
    final DateTime now = DateTime.now();
    final String today = _dateKey(now);
    final List<Map<String, Object?>> rows = await db.query(
      'training_plans',
      where: 'ownerId = ? AND active = 1 AND endDate <= ? AND reviewPrompted = 0',
      whereArgs: <Object?>[_ownerId, today],
      orderBy: 'endDate DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    if (rows.first['endDate'] == today && now.hour < 19) return null;
    return _decodePlan(rows.first);
  }

  Future<void> markReviewPrompted(String planId) async {
    final Database db = await _db;
    await db.update(
      'training_plans',
      <String, Object?>{'reviewPrompted': 1},
      where: 'id = ? AND ownerId = ?',
      whereArgs: <Object?>[planId, _ownerId],
    );
  }

  Future<void> recordFeedback({
    required DateTime startedAt,
    TrainingEffort? effort,
    String? planId,
    String? dayId,
  }) async {
    final Database db = await _db;
    final String id = '${_ownerId}_${startedAt.toUtc().microsecondsSinceEpoch}';
    await db.transaction((Transaction txn) async {
      if (effort != null) {
        await txn.insert(
          'training_session_feedback',
          <String, Object?>{
            'id': id,
            'ownerId': _ownerId,
            'startedAt': startedAt.toUtc().toIso8601String(),
            'effort': effort.name,
            'planId': planId,
            'dayId': dayId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      if (dayId != null) {
        await txn.update(
          'training_plan_days',
          <String, Object?>{
            'completed': 1,
            'missed': 0,
            'effort': effort?.name,
          },
          where: 'dayId = ? AND ownerId = ?',
          whereArgs: <Object?>[dayId, _ownerId],
        );
      }
    });
    if (dayId != null && planId != null) {
      final TrainingPlanDay? day = await getDay(dayId);
      if (day != null) {
        try {
          await ReminderService.cancelTrainingPlanDayNotification(
            planId,
            _dateKey(day.date),
          );
        } catch (_) {}
      }
    }
  }

  Future<List<TrainingEffort>> getRecentEfforts({int limit = 5}) async {
    final Database db = await _db;
    final String cutoff =
        DateTime.now().toUtc().subtract(const Duration(days: 30)).toIso8601String();
    final List<Map<String, Object?>> rows = await db.query(
      'training_session_feedback',
      columns: <String>['effort'],
      where: 'ownerId = ? AND startedAt >= ?',
      whereArgs: <Object?>[_ownerId, cutoff],
      orderBy: 'startedAt DESC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> row) =>
            _effortFromName(row['effort'] as String?) ?? TrainingEffort.normal)
        .toList(growable: false);
  }

  Future<void> adjustFutureDays({
    required String planId,
    required DateTime afterDate,
    required TrainingEffort effort,
  }) async {
    if (effort == TrainingEffort.normal) return;
    final List<TrainingPlanDay> preview = await previewAdjustedDays(
      planId: planId,
      afterDate: afterDate,
      effort: effort,
    );
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      for (final TrainingPlanDay day in preview) {
        await txn.update(
          'training_plan_days',
          <String, Object?>{'dayJson': jsonEncode(day.toJson())},
          where: 'dayId = ? AND ownerId = ? AND completed = 0 AND missed = 0',
          whereArgs: <Object?>[day.id, _ownerId],
        );
      }
    });
    final SavedTrainingPlan? plan = await getPlan(planId);
    if (plan != null) {
      for (final TrainingPlanDay day in preview) {
        await ReminderService.cancelTrainingPlanDayNotification(
          planId,
          _dateKey(day.date),
        );
        await ReminderService.scheduleTrainingPlanSessionReminder(
          planId: planId,
          dayId: day.id,
          date: day.date,
          title: day.title,
          sessionHour: plan.sessionHour,
          sessionMinute: plan.sessionMinute,
        );
      }
    }
  }

  TrainingPlanDay _adjustDay(TrainingPlanDay day, TrainingEffort effort) {
    if (day.isRestDay) return day;
    if (effort == TrainingEffort.tooHard || effort == TrainingEffort.hard) {
      final double factor = effort == TrainingEffort.tooHard ? 0.80 : 0.90;
      return day.copyWith(
        title: day.activityType == RunActivityType.run
            ? 'Disesuaikan: Lari mudah'
            : 'Disesuaikan: ${day.title}',
        description: _easyDescription(day.activityType),
        durationMinutes: mathMax(15, (day.durationMinutes * factor).round()),
        intensity: 'Ringan',
        clearInterval: true,
        intervalPlan: null,
      );
    }
    final int increment = effort == TrainingEffort.tooLight ? 5 : 2;
    return day.copyWith(
      title: day.title.startsWith('Disesuaikan')
          ? day.title
          : 'Disesuaikan: ${day.title}',
      description: '${day.description} Durasi ditambah sedikit, tetap pada intensitas terkendali.',
      durationMinutes: mathMin(90, day.durationMinutes + increment),
      intensity: day.intensity,
    );
  }

  SavedTrainingPlan _decodePlan(Map<String, Object?> row) {
    final Map<String, dynamic> json =
        jsonDecode(row['planJson'] as String) as Map<String, dynamic>;
    final Map<String, dynamic> target =
        Map<String, dynamic>.from(json['target'] as Map? ?? <String, dynamic>{});
    final TrainingGoal goal = TrainingGoal.values.firstWhere(
      (TrainingGoal value) => value.name == row['goal'],
      orElse: () => TrainingGoal.endurance,
    );
    final String targetDescription = switch (goal) {
      TrainingGoal.endurance =>
        'Jarak ${target['targetDistanceKm'] ?? '-'} km • batas sesi ${target['sessionMinutes'] ?? '-'} menit',
      TrainingGoal.pace =>
        'Pace ${_paceText(target['targetPaceSecondsPerKm'])}/km • ${target['targetDistanceKm'] ?? '-'} km • ${target['targetFinishMinutes'] ?? '-'} menit • batas sesi ${target['sessionMinutes'] ?? '-'} menit',
      TrainingGoal.vo2max =>
        'VO₂max ${target['targetVo2Max'] ?? '-'} ml/kg/menit',
    };
    return SavedTrainingPlan(
      id: row['id'] as String,
      title: json['title'] as String? ?? 'Rencana latihan',
      strategy: TrainingStrategy.values.firstWhere(
        (TrainingStrategy value) => value.name == row['strategy'],
        orElse: () => TrainingStrategy.progressive,
      ),
      goal: goal,
      startDate: DateTime.parse(row['startDate'] as String),
      endDate: DateTime.parse(row['endDate'] as String),
      durationDays: (json['durationDays'] as num? ?? 7).toInt(),
      summary: json['summary'] as String? ?? '',
      targetDescription: targetDescription,
      targetDistanceKm: (target['targetDistanceKm'] as num?)?.toDouble(),
      targetPaceSecondsPerKm: (target['targetPaceSecondsPerKm'] as num?)?.toInt(),
      targetFinishMinutes: (target['targetFinishMinutes'] as num?)?.toInt(),
      targetVo2Max: (target['targetVo2Max'] as num?)?.toDouble(),
      sessionMinutes: (target['sessionMinutes'] as num? ?? 30).toInt(),
      sessionHour: (json['sessionHour'] as num? ?? 7).toInt(),
      sessionMinute: (json['sessionMinute'] as num? ?? 0).toInt(),
      trainingWeekdays: (target['trainingWeekdays'] as List<dynamic>? ?? <dynamic>[2, 4, 6])
          .whereType<num>()
          .map((num value) => value.toInt())
          .where((int value) => value >= 1 && value <= 7)
          .toList(growable: false),
      loadDescription: json['loadDescription'] as String? ?? '',
      advantages: (json['advantages'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>().toList(growable: false),
      disadvantages: (json['disadvantages'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>().toList(growable: false),
      reviewPrompted: (row['reviewPrompted'] as num? ?? 0).toInt() == 1,
    );
  }

  static String _easyDescription(RunActivityType type) => switch (type) {
        RunActivityType.run =>
          'Pemanasan berjalan 5 menit, lanjutkan lari ringan dengan usaha yang masih memungkinkan berbicara, lalu pendinginan 5 menit.',
        RunActivityType.walk =>
          'Berjalan dengan ritme nyaman. Kurangi durasi dan jaga langkah tetap santai.',
        RunActivityType.cycle =>
          'Awali dengan kayuhan ringan, lanjutkan kayuhan santai, lalu akhiri dengan kayuhan perlahan.',
        RunActivityType.hiit =>
          'Sesi intensitas tinggi diganti dengan gerakan ringan dan pemulihan tanpa interval.',
      };

  static int mathMax(int a, int b) => a > b ? a : b;
  static int mathMin(int a, int b) => a < b ? a : b;

  static String _paceText(Object? value) {
    if (value is! num) return '-';
    final int seconds = value.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
