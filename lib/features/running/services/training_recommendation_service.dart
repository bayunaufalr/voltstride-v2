import '../models/run_session.dart';

enum TrainingGoal {
  endurance,
  pace,
  consistency,
  generalFitness,
}

enum TrainingPlanKind {
  easyRunWalk,
  controlledIntervals,
  steadyRun,
  comfortableWalk,
  easyCycling,
  lowImpactHiit,
}

enum TrainingLoadLevel {
  starter,
  building,
  recovery,
}

class TrainingRecommendation {
  const TrainingRecommendation({
    required this.kind,
    required this.activityType,
    required this.durationMinutes,
    required this.intensity,
    required this.intervalPlan,
    required this.activityDetails,
  });

  final TrainingPlanKind kind;
  final RunActivityType activityType;
  final int durationMinutes;
  final String intensity;
  final IntervalRunPlan? intervalPlan;
  final String activityDetails;
}

class TrainingRecommendationOverview {
  const TrainingRecommendationOverview({
    required this.options,
    required this.loadLevel,
    required this.recentSessionCount,
    required this.minutesLastSevenDays,
    required this.hoursSinceLastSession,
    required this.hasRecentData,
  });

  final List<TrainingRecommendation> options;
  final TrainingLoadLevel loadLevel;
  final int recentSessionCount;
  final int minutesLastSevenDays;
  final int? hoursSinceLastSession;
  final bool hasRecentData;
}

/// Menyusun pilihan latihan dari riwayat 30 hari terakhir.
/// Rekomendasi ini memakai durasi/frekuensi, bukan diagnosis atau zona HR.
class TrainingRecommendationService {
  TrainingRecommendationService._();

  static TrainingRecommendationOverview generate({
    required List<RunSession> history,
    required TrainingGoal goal,
    required int durationMinutes,
    DateTime? now,
  }) {
    if (durationMinutes < 10 || durationMinutes > 60) {
      throw RangeError.range(durationMinutes, 10, 60, 'durationMinutes');
    }

    final DateTime referenceTime = now ?? DateTime.now();
    final DateTime thirtyDaysAgo = referenceTime.subtract(
      const Duration(days: 30),
    );
    final DateTime sevenDaysAgo = referenceTime.subtract(
      const Duration(days: 7),
    );

    final List<RunSession> recentSessions = history.where((RunSession session) {
      final DateTime? finishedAt = session.finishedAt;
      return finishedAt != null &&
          !finishedAt.isAfter(referenceTime) &&
          session.elapsed >= const Duration(minutes: 5) &&
          !session.startedAt.isAfter(referenceTime) &&
          !session.startedAt.isBefore(thirtyDaysAgo);
    }).toList()
      ..sort(
        (RunSession first, RunSession second) =>
            second.startedAt.compareTo(first.startedAt),
      );

    final int minutesLastSevenDays = recentSessions
        .where((RunSession session) =>
            !session.startedAt.isBefore(sevenDaysAgo))
        .fold<int>(
          0,
          (int total, RunSession session) => total + session.elapsed.inMinutes,
        );

    final RunSession? latest =
        recentSessions.isEmpty ? null : recentSessions.first;
    final int? hoursSinceLastSession = latest == null
        ? null
        : referenceTime
            .difference(latest.finishedAt ?? latest.startedAt)
            .inHours;

    // Beban diturunkan bila sesi terlalu dekat atau durasi mingguan tinggi.
    // Level membangun dipakai setelah pola dan volume latihan terlihat.
    final TrainingLoadLevel level;
    if ((hoursSinceLastSession != null && hoursSinceLastSession < 18) ||
        minutesLastSevenDays >= 180) {
      level = TrainingLoadLevel.recovery;
    } else if (recentSessions.length >= 5 &&
        (hoursSinceLastSession == null || hoursSinceLastSession >= 36) &&
        minutesLastSevenDays >= 60 &&
        minutesLastSevenDays < 180) {
      level = TrainingLoadLevel.building;
    } else {
      level = TrainingLoadLevel.starter;
    }

    final int workSeconds = switch (level) {
      TrainingLoadLevel.recovery => 10,
      TrainingLoadLevel.starter => 15,
      TrainingLoadLevel.building => 20,
    };
    final int recoverySeconds = 60 - workSeconds;
    final int repetitions = durationMinutes;
    final IntervalRunPlan easyIntervalPlan = IntervalRunPlan(
      workSeconds: workSeconds,
      recoverySeconds: recoverySeconds,
      repetitions: repetitions,
    );

    final String intensity = switch (level) {
      TrainingLoadLevel.recovery => 'Pemulihan',
      TrainingLoadLevel.starter => 'Ringan',
      TrainingLoadLevel.building => 'Ringan–sedang',
    };

    final List<TrainingPlanKind> kinds = switch (goal) {
      TrainingGoal.endurance => level == TrainingLoadLevel.recovery
          ? <TrainingPlanKind>[
              TrainingPlanKind.comfortableWalk,
              TrainingPlanKind.easyCycling,
              TrainingPlanKind.easyRunWalk,
            ]
          : <TrainingPlanKind>[
              TrainingPlanKind.easyRunWalk,
              TrainingPlanKind.easyCycling,
              TrainingPlanKind.comfortableWalk,
            ],
      TrainingGoal.pace => level == TrainingLoadLevel.recovery
          ? <TrainingPlanKind>[
              TrainingPlanKind.comfortableWalk,
              TrainingPlanKind.easyCycling,
              TrainingPlanKind.easyRunWalk,
            ]
          : <TrainingPlanKind>[
              TrainingPlanKind.controlledIntervals,
              TrainingPlanKind.steadyRun,
              TrainingPlanKind.comfortableWalk,
            ],
      TrainingGoal.consistency => <TrainingPlanKind>[
          TrainingPlanKind.comfortableWalk,
          TrainingPlanKind.easyRunWalk,
          TrainingPlanKind.easyCycling,
        ],
      TrainingGoal.generalFitness => level == TrainingLoadLevel.recovery
          ? <TrainingPlanKind>[
              TrainingPlanKind.comfortableWalk,
              TrainingPlanKind.easyCycling,
              TrainingPlanKind.easyRunWalk,
            ]
          : <TrainingPlanKind>[
              TrainingPlanKind.lowImpactHiit,
              TrainingPlanKind.easyCycling,
              TrainingPlanKind.comfortableWalk,
            ],
    };

    final List<TrainingRecommendation> options = kinds
        .map((TrainingPlanKind kind) => _makeRecommendation(
              kind: kind,
              durationMinutes: durationMinutes,
              intensity: intensity,
              intervalPlan: easyIntervalPlan,
              recovery: level == TrainingLoadLevel.recovery,
            ))
        .toList(growable: false);

    return TrainingRecommendationOverview(
      options: options,
      loadLevel: level,
      recentSessionCount: recentSessions.length,
      minutesLastSevenDays: minutesLastSevenDays,
      hoursSinceLastSession: hoursSinceLastSession,
      hasRecentData: recentSessions.isNotEmpty,
    );
  }

  static TrainingRecommendation _makeRecommendation({
    required TrainingPlanKind kind,
    required int durationMinutes,
    required String intensity,
    required IntervalRunPlan intervalPlan,
    required bool recovery,
  }) {
    switch (kind) {
      case TrainingPlanKind.easyRunWalk:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.run,
          durationMinutes: durationMinutes,
          intensity: intensity,
          intervalPlan: intervalPlan,
          activityDetails: recovery
              ? 'Jogging sangat ringan saat fase kerja, '
                  'lalu berjalan santai saat pemulihan.'
              : 'Jogging ringan saat fase kerja, '
                  'lalu berjalan santai saat pemulihan.',
        );
      case TrainingPlanKind.controlledIntervals:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.run,
          durationMinutes: durationMinutes,
          intensity: intensity,
          intervalPlan: intervalPlan,
          activityDetails:
              'Lari terkontrol saat fase kerja. Gunakan fase pemulihan '
              'untuk berjalan; jangan mengejar kecepatan maksimal.',
        );
      case TrainingPlanKind.steadyRun:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.run,
          durationMinutes: durationMinutes,
          intensity: intensity,
          intervalPlan: null,
          activityDetails:
              'Pertahankan usaha ringan dan ritme yang masih '
              'memungkinkan berbicara.',
        );
      case TrainingPlanKind.comfortableWalk:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.walk,
          durationMinutes: durationMinutes,
          intensity: recovery ? 'Pemulihan ringan' : 'Ringan',
          intervalPlan: null,
          activityDetails: 'Berjalan dengan langkah nyaman dan ritme stabil.',
        );
      case TrainingPlanKind.easyCycling:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.cycle,
          durationMinutes: durationMinutes,
          intensity: recovery ? 'Pemulihan ringan' : 'Ringan',
          intervalPlan: null,
          activityDetails:
              'Bersepeda santai dengan kayuhan stabil; pilih rute '
              'dan kondisi yang aman.',
        );
      case TrainingPlanKind.lowImpactHiit:
        return TrainingRecommendation(
          kind: kind,
          activityType: RunActivityType.hiit,
          durationMinutes: durationMinutes,
          intensity: recovery ? 'Pemulihan ringan' : intensity,
          intervalPlan: intervalPlan,
          activityDetails:
              'Pilih gerakan berdampak rendah yang sudah dikuasai. '
              'Jaga gerakan tetap terkontrol dan gunakan waktu pemulihan '
              'sepenuhnya.',
        );
    }
  }
}
