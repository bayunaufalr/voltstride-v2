import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';

void main() {
  RunPoint point(int index, double altitude, {bool newSegment = false}) {
    return RunPoint(
      latitude: -7.8 + index * 0.00001,
      longitude: 110.3 + index * 0.00001,
      timestamp: DateTime.utc(2026, 10, 18).add(Duration(seconds: index)),
      accuracyMeters: 5,
      altitudeMeters: altitude,
      startsNewSegment: newSegment,
    );
  }

  test('distance interval reports work and recovery distance remaining', () {
    const IntervalRunPlan plan = IntervalRunPlan(
      workSeconds: 60,
      recoverySeconds: 90,
      repetitions: 3,
      measure: IntervalMeasure.distance,
      workDistanceMeters: 400,
      recoveryDistanceMeters: 200,
    );

    final IntervalPhase work = plan.phaseAtProgress(
      elapsed: Duration.zero,
      distanceMeters: 250,
    );
    expect(work.stage, IntervalStage.work);
    expect(work.repetition, 1);
    expect(work.distanceRemainingMeters, 150);

    final IntervalPhase recovery = plan.phaseAtProgress(
      elapsed: Duration.zero,
      distanceMeters: 450,
    );
    expect(recovery.stage, IntervalStage.recovery);
    expect(recovery.repetition, 1);
    expect(recovery.distanceRemainingMeters, 150);

    final IntervalPhase nextRepetition = plan.phaseAtProgress(
      elapsed: Duration.zero,
      distanceMeters: 700,
    );
    expect(nextRepetition.stage, IntervalStage.work);
    expect(nextRepetition.repetition, 2);
    expect(nextRepetition.distanceRemainingMeters, 300);
  });

  test('small altitude jitter does not create large ascent and descent totals', () {
    const List<double> noisyAltitude = <double>[
      50, 54, 47, 53, 49, 52, 46, 55, 48, 51,
      53, 47, 52, 49, 54, 46, 50, 53, 48, 51,
      47, 54, 49, 52, 46, 50, 53, 48, 51, 47,
    ];
    final List<RunPoint> route = List<RunPoint>.generate(
      noisyAltitude.length,
      (int index) => point(index, noisyAltitude[index], newSegment: index == 0),
      growable: false,
    );

    final RunElevationStats stats = calculateRunElevation(route);
    expect(stats.hasAltitudeData, isTrue);
    expect(stats.totalAscentMeters, lessThan(12));
    expect(stats.totalDescentMeters, lessThan(12));
    expect(stats.maxAboveStartMeters, lessThan(12));
  });

  test('meaningful elevation change remains visible after noise filtering', () {
    const List<double> altitude = <double>[
      100, 100, 100, 100, 100, 106, 112, 118,
      124, 130, 124, 118, 112, 106, 100, 94,
    ];
    final List<RunPoint> route = List<RunPoint>.generate(
      altitude.length,
      (int index) => point(index, altitude[index], newSegment: index == 0),
      growable: false,
    );

    final RunElevationStats stats = calculateRunElevation(route);
    expect(stats.totalAscentMeters, greaterThan(0));
    expect(stats.totalDescentMeters, greaterThan(0));
    expect(stats.maxAboveStartMeters, greaterThanOrEqualTo(12));
  });

  test('session keeps steps and cadence samples through local-map serialization', () {
    final RunSession session = RunSession(
      startedAt: DateTime.utc(2026, 10, 18, 4),
      finishedAt: DateTime.utc(2026, 10, 18, 4, 30),
      distanceMeters: 5000,
      elapsed: Duration(minutes: 30),
      movingTime: Duration(minutes: 28),
      averagePaceSecondsPerKm: 336,
      currentPaceSecondsPerKm: 330,
      gpsAccuracyMeters: 6,
      acceptedPoints: 120,
      rejectedPoints: 5,
      route: <RunPoint>[],
      splits: <RunSplit>[],
      totalSteps: 6200,
      averageCadenceSpm: 154,
      maxCadenceSpm: 170,
      cadenceSamples: <RunCadenceSample>[
        RunCadenceSample(distanceMeters: 100, cadenceSpm: 150),
        RunCadenceSample(distanceMeters: 200, cadenceSpm: 158),
      ],
    );

    final RunSession restored = RunSession.fromStorageMap(
      Map<String, Object?>.from(session.toStorageMap()),
    );
    expect(restored.totalSteps, 6200);
    expect(restored.averageCadenceSpm, 154);
    expect(restored.maxCadenceSpm, 170);
    expect(restored.cadenceSamples, hasLength(2));
    expect(restored.estimatedCalories, closeTo(300, 0.01));
  });
}
