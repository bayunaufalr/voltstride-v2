import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/run_evaluation.dart';

void main() {
  group('IntervalRunPlan', () {
    const IntervalRunPlan plan = IntervalRunPlan(
      workSeconds: 60,
      recoverySeconds: 90,
      repetitions: 6,
    );

    test('phases advance from work to recovery and next repetition', () {
      expect(plan.phaseAt(Duration.zero).stage, IntervalStage.work);
      expect(plan.phaseAt(const Duration(seconds: 59)).secondsRemaining, 1);
      expect(plan.phaseAt(const Duration(seconds: 60)).stage, IntervalStage.recovery);
      expect(plan.phaseAt(const Duration(seconds: 150)).repetition, 2);
      expect(plan.phaseAt(const Duration(seconds: 900)).stage, IntervalStage.complete);
    });
  });

  group('RunLap100m', () {
    test('calculates speed and equivalent pace from 100 m duration', () {
      const RunLap100m lap = RunLap100m(
        distanceMeters: 100,
        durationMilliseconds: 20000,
        latitude: -7.8,
        longitude: 110.3,
      );
      expect(lap.speedKmh, closeTo(18, 0.001));
      expect(lap.paceSecondsPerKm, closeTo(200, 0.001));
    });
  });

  test('old-style route point JSON remains readable', () {
    final RunPoint point = RunPoint.fromJson(<String, dynamic>{
      'latitude': -7.8,
      'longitude': 110.3,
      'timestamp': '2026-10-13T00:00:00.000Z',
      'accuracyMeters': 5.0,
    });
    expect(point.startsNewSegment, isFalse);
  });


  test('run session storage map preserves 100m laps and interval plan', () {
    final RunSession original = RunSession(
      startedAt: DateTime.utc(2026, 10, 13),
      finishedAt: DateTime.utc(2026, 10, 13, 0, 10),
      distanceMeters: 100,
      elapsed: const Duration(seconds: 20),
      movingTime: const Duration(seconds: 20),
      averagePaceSecondsPerKm: 200,
      currentPaceSecondsPerKm: null,
      gpsAccuracyMeters: 5,
      acceptedPoints: 4,
      rejectedPoints: 0,
      route: const <RunPoint>[
        RunPoint(
          latitude: -7.8,
          longitude: 110.3,
          timestamp: DateTime.utc(2026, 10, 13),
          accuracyMeters: 5,
          startsNewSegment: true,
        ),
      ],
      splits: const <RunSplit>[],
      hundredMeterLaps: const <RunLap100m>[
        RunLap100m(
          distanceMeters: 100,
          durationMilliseconds: 20000,
          latitude: -7.799,
          longitude: 110.301,
        ),
      ],
      intervalPlan: const IntervalRunPlan(
        workSeconds: 60,
        recoverySeconds: 90,
        repetitions: 6,
      ),
    );

    final RunSession restored =
        RunSession.fromStorageMap(original.toStorageMap());
    expect(restored.hundredMeterLaps, hasLength(1));
    expect(restored.hundredMeterLaps.single.speedKmh, closeTo(18, 0.001));
    expect(restored.intervalPlan?.repetitions, 6);
    expect(restored.route.single.startsNewSegment, isTrue);
  });

  test('evaluation does not invent pace from very short sessions', () {
    final RunSession session = RunSession(
      startedAt: DateTime.utc(2026, 10, 13),
      finishedAt: DateTime.utc(2026, 10, 13, 0, 1),
      distanceMeters: 80,
      elapsed: const Duration(seconds: 60),
      movingTime: const Duration(seconds: 60),
      averagePaceSecondsPerKm: null,
      currentPaceSecondsPerKm: null,
      gpsAccuracyMeters: 10,
      acceptedPoints: 5,
      rejectedPoints: 0,
      route: const <RunPoint>[],
      splits: const <RunSplit>[],
    );
    expect(evaluateRun(session).title, 'Data masih terbatas');
  });
}
