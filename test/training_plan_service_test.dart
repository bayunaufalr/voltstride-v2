import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/training_plan_service.dart';

void main() {
  final DateTime start = DateTime(2026, 11, 16);

  TrainingPlanRequest request({
    TrainingGoal goal = TrainingGoal.endurance,
    int days = 14,
  }) =>
      TrainingPlanRequest(
        goal: goal,
        durationDays: days,
        startDate: start,
        trainingWeekdays: const <int>[2, 4, 6],
        sessionMinutes: 35,
        targetDistanceKm: goal == TrainingGoal.vo2max ? null : 5,
        targetPaceSecondsPerKm: goal == TrainingGoal.pace ? 420 : null,
        targetFinishMinutes: goal == TrainingGoal.pace ? 35 : null,
        targetVo2Max: goal == TrainingGoal.vo2max ? 45 : null,
      );

  RunSession makeSession(DateTime date, int minutes) => RunSession(
        startedAt: date,
        finishedAt: date.add(Duration(minutes: minutes)),
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
      );

  group('TrainingPlanService', () {
    test('creates three date-based options for a 14-day plan', () {
      final List<TrainingPlanOption> options = TrainingPlanService.buildOptions(
        request: request(),
        history: const <RunSession>[],
        now: DateTime(2026, 11, 10),
      );

      expect(options, hasLength(3));
      for (final TrainingPlanOption option in options) {
        expect(option.days, hasLength(14));
        expect(option.days.first.date, start);
        expect(option.days.last.date, DateTime(2026, 11, 29));
        expect(option.days.any((TrainingPlanDay day) => day.isRestDay), isTrue);
        expect(option.advantages, isNotEmpty);
        expect(option.disadvantages, isNotEmpty);
      }
    });

    test('limits workout days to the selected weekdays', () {
      final TrainingPlanOption option = TrainingPlanService.buildOptions(
        request: request(days: 7),
        history: const <RunSession>[],
        now: DateTime(2026, 11, 10),
      ).first;
      final List<TrainingPlanDay> workouts = option.days
          .where((TrainingPlanDay day) => !day.isRestDay)
          .toList();

      expect(workouts, hasLength(3));
      expect(workouts.map((TrainingPlanDay day) => day.date.weekday),
          everyElement(anyOf(2, 4, 6)));
    });

    test('limits an unfamiliar session duration using available history', () {
      final TrainingPlanRequest longSession = TrainingPlanRequest(
        goal: TrainingGoal.endurance,
        durationDays: 7,
        startDate: start,
        trainingWeekdays: const <int>[2, 4, 6],
        sessionMinutes: 90,
        targetDistanceKm: 10,
      );
      final TrainingPlanOption option = TrainingPlanService.buildOptions(
        request: longSession,
        history: const <RunSession>[],
        now: DateTime(2026, 11, 10),
      ).first;
      final List<TrainingPlanDay> workouts = option.days
          .where((TrainingPlanDay day) => !day.isRestDay)
          .toList();

      expect(workouts.every((TrainingPlanDay day) => day.durationMinutes <= 25), isTrue);
      expect(option.loadDescription, contains('maksimal 30 menit'));
    });

    test('builds a complete 28-day schedule', () {
      final TrainingPlanOption option = TrainingPlanService.buildOptions(
        request: request(days: 28),
        history: const <RunSession>[],
        now: DateTime(2026, 11, 10),
      ).first;

      expect(option.days, hasLength(28));
      expect(option.days.last.date, DateTime(2026, 12, 13));
    });

    test('resets the weekly workout sequence on Monday', () {
      final TrainingPlanRequest thursdayStart = TrainingPlanRequest(
        goal: TrainingGoal.endurance,
        durationDays: 14,
        startDate: DateTime(2026, 11, 12),
        trainingWeekdays: const <int>[2, 4, 6],
        sessionMinutes: 30,
        targetDistanceKm: 5,
      );
      final TrainingPlanOption option = TrainingPlanService.buildOptions(
        request: thursdayStart,
        history: const <RunSession>[],
        now: DateTime(2026, 11, 10),
      ).first;
      final Map<int, TrainingPlanDay> byDay = <int, TrainingPlanDay>{
        for (final TrainingPlanDay day in option.days)
          day.date.day: day,
      };

      expect(byDay[12]!.activityType, RunActivityType.run);
      expect(byDay[14]!.activityType, RunActivityType.walk);
      expect(byDay[17]!.activityType, RunActivityType.run);
      expect(byDay[19]!.activityType, RunActivityType.walk);
      expect(byDay[21]!.activityType, RunActivityType.run);
    });

    test('uses current pace and distance history in the plan comparison', () {
      final TrainingPlanOption option = TrainingPlanService.buildOptions(
        request: request(goal: TrainingGoal.pace),
        history: <RunSession>[
          makeSession(DateTime(2026, 11, 2), 25),
          makeSession(DateTime(2026, 11, 4), 25),
          makeSession(DateTime(2026, 11, 6), 25),
        ],
        now: DateTime(2026, 11, 10),
      ).first;

      expect(option.loadDescription, contains('pace lari rata-rata'));
      expect(option.loadDescription, contains('jarak terjauh'));
      expect(option.days.any((TrainingPlanDay day) =>
          day.description.contains('target waktu 35 menit')), isTrue);
    });

    test('uses hard session feedback to choose a recovery load', () {
      final List<TrainingPlanOption> options = TrainingPlanService.buildOptions(
        request: request(goal: TrainingGoal.vo2max),
        history: <RunSession>[
          makeSession(DateTime(2026, 11, 6), 25),
          makeSession(DateTime(2026, 11, 8), 25),
        ],
        recentEfforts: const <TrainingEffort>[
          TrainingEffort.tooHard,
          TrainingEffort.tooHard,
        ],
        now: DateTime(2026, 11, 10),
      );

      expect(options.first.loadDescription, contains('pemulihan'));
      expect(options, hasLength(3));
    });

    test('creates pace targets with a controlled interval option', () {
      final List<TrainingPlanOption> options = TrainingPlanService.buildOptions(
        request: request(goal: TrainingGoal.pace),
        history: <RunSession>[
          makeSession(DateTime(2026, 11, 2), 25),
          makeSession(DateTime(2026, 11, 4), 25),
          makeSession(DateTime(2026, 11, 6), 25),
          makeSession(DateTime(2026, 11, 8), 25),
        ],
        now: DateTime(2026, 11, 10),
      );

      expect(options, hasLength(3));
      expect(options[1].days.any((TrainingPlanDay day) =>
          day.intervalPlan != null), isTrue);
    });

    test('keeps interval work inside the requested session time', () {
      final TrainingPlanRequest shortSession = TrainingPlanRequest(
        goal: TrainingGoal.pace,
        durationDays: 7,
        startDate: start,
        trainingWeekdays: const <int>[2, 4, 6],
        sessionMinutes: 15,
        targetDistanceKm: 5,
        targetPaceSecondsPerKm: 480,
        targetFinishMinutes: 40,
      );
      final List<TrainingPlanOption> options = TrainingPlanService.buildOptions(
        request: shortSession,
        history: <RunSession>[
          makeSession(DateTime(2026, 11, 2), 25),
          makeSession(DateTime(2026, 11, 4), 25),
          makeSession(DateTime(2026, 11, 6), 25),
          makeSession(DateTime(2026, 11, 8), 25),
        ],
        now: DateTime(2026, 11, 10),
      );

      expect(options[1].days.any((TrainingPlanDay day) =>
          day.intervalPlan != null), isFalse);
    });

    test('rejects plan periods that are not weekly increments', () {
      expect(
        () => TrainingPlanService.buildOptions(
          request: request(days: 10),
          history: const <RunSession>[],
        ),
        throwsArgumentError,
      );
    });
  });
}
