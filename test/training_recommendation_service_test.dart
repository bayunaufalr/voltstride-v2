import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/training_recommendation_service.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 11, 10, 9);

  RunSession makeSession({
    required DateTime startedAt,
    int minutes = 30,
    RunActivityType activityType = RunActivityType.run,
  }) {
    return RunSession(
      startedAt: startedAt,
      finishedAt: startedAt.add(Duration(minutes: minutes)),
      distanceMeters: 3000,
      elapsed: Duration(minutes: minutes),
      movingTime: Duration(minutes: minutes),
      averagePaceSecondsPerKm: 600,
      currentPaceSecondsPerKm: 600,
      gpsAccuracyMeters: 5,
      acceptedPoints: 10,
      rejectedPoints: 0,
      route: const <RunPoint>[],
      splits: const <RunSplit>[],
      activityType: activityType,
    );
  }

  group('TrainingRecommendationService', () {
    test('starts gently when the user has no recent history', () {
      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: const <RunSession>[],
        goal: TrainingGoal.endurance,
        durationMinutes: 30,
        now: now,
      );

      expect(result.loadLevel, TrainingLoadLevel.starter);
      expect(result.hasRecentData, isFalse);
      expect(result.options, hasLength(3));
      expect(result.options.first.intervalPlan?.workSeconds, 15);
      expect(result.options.first.intervalPlan?.recoverySeconds, 45);
    });

    test('uses a recovery-oriented plan after a recent session', () {
      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: <RunSession>[
          makeSession(startedAt: now.subtract(const Duration(hours: 3))),
        ],
        goal: TrainingGoal.pace,
        durationMinutes: 25,
        now: now,
      );

      expect(result.loadLevel, TrainingLoadLevel.recovery);
      expect(result.options.first.kind, TrainingPlanKind.comfortableWalk);
      expect(result.options.first.intervalPlan, isNull);
    });

    test('recognizes a consistent pattern with moderate weekly load', () {
      final List<RunSession> history = List<RunSession>.generate(
        5,
        (int index) => makeSession(
          startedAt: now.subtract(Duration(days: index + 3)),
          minutes: 20,
        ),
      );

      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: history,
        goal: TrainingGoal.pace,
        durationMinutes: 30,
        now: now,
      );

      expect(result.loadLevel, TrainingLoadLevel.building);
      expect(result.minutesLastSevenDays, 100);
      expect(result.options.first.kind, TrainingPlanKind.controlledIntervals);
      expect(result.options.first.intervalPlan?.workSeconds, 20);
      expect(result.options.first.intervalPlan?.recoverySeconds, 40);
    });

    test('reduces intensity when the seven-day activity total is high', () {
      final List<RunSession> history = List<RunSession>.generate(
        6,
        (int index) => makeSession(
          startedAt: now.subtract(Duration(days: index + 1)),
          minutes: 30,
        ),
      );

      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: history,
        goal: TrainingGoal.generalFitness,
        durationMinutes: 30,
        now: now,
      );

      expect(result.minutesLastSevenDays, 180);
      expect(result.loadLevel, TrainingLoadLevel.recovery);
      expect(result.options.first.kind, TrainingPlanKind.comfortableWalk);
      expect(result.options.every((TrainingRecommendation option) =>
          option.kind != TrainingPlanKind.lowImpactHiit), isTrue);
    });

    test('offers low-impact options for general fitness at starter level', () {
      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: const <RunSession>[],
        goal: TrainingGoal.generalFitness,
        durationMinutes: 20,
        now: now,
      );

      expect(result.options.first.kind, TrainingPlanKind.lowImpactHiit);
      expect(result.options.first.activityType, RunActivityType.hiit);
      expect(result.options.first.intervalPlan, isNotNull);
    });

    test('rejects a duration outside the supported range', () {
      expect(
        () => TrainingRecommendationService.generate(
          history: const <RunSession>[],
          goal: TrainingGoal.endurance,
          durationMinutes: 9,
          now: now,
        ),
        throwsRangeError,
      );
    });
  });
}
