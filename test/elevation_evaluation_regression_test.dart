import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/run_evaluation.dart';

void main() {
  RunPoint point(int index, double altitude) {
    return RunPoint(
      latitude: -7.8 + index * 0.00001,
      longitude: 110.3 + index * 0.00001,
      timestamp: DateTime.utc(2026, 10, 18).add(Duration(seconds: index)),
      accuracyMeters: 5,
      altitudeMeters: altitude,
    );
  }

  test('short elevation track preserves meaningful ascent and descent', () {
    final RunElevationStats stats = calculateRunElevation(<RunPoint>[
      point(0, 100),
      point(1, 110),
      point(2, 106),
    ]);

    expect(stats.totalAscentMeters, 10);
    expect(stats.totalDescentMeters, 4);
    expect(stats.netChangeMeters, 6);
  });

  test('very short activity does not show a numerical pace evaluation', () {
    final DateTime start = DateTime.utc(2026, 10, 18, 4);
    final RunSession session = RunSession(
      startedAt: start,
      finishedAt: start.add(const Duration(seconds: 90)),
      distanceMeters: 250,
      elapsed: const Duration(seconds: 90),
      movingTime: const Duration(seconds: 90),
      averagePaceSecondsPerKm: 360,
      currentPaceSecondsPerKm: 360,
      gpsAccuracyMeters: 8,
      acceptedPoints: 3,
      rejectedPoints: 0,
      route: <RunPoint>[point(0, 100), point(1, 101), point(2, 100)],
      splits: const <RunSplit>[],
    );

    final RunEvaluation evaluation = evaluateRun(session);
    final String visibleText = <String>[
      evaluation.title,
      evaluation.overview,
      ...evaluation.observations,
      ...evaluation.recommendations,
    ].join(' ');

    expect(visibleText, contains('terlalu singkat'));
    expect(visibleText, isNot(contains('Pace rata-rata sesi ini')));
    expect(visibleText, isNot(contains('6:00/km')));
  });
}
