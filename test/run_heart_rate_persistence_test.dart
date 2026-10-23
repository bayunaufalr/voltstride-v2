import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';

void main() {
  test('heart-rate samples survive local session serialization', () {
    final DateTime startedAt = DateTime.utc(2026, 10, 23, 1);
    final RunSession original = RunSession(
      startedAt: startedAt,
      finishedAt: startedAt.add(const Duration(minutes: 2)),
      distanceMeters: 1000,
      elapsed: const Duration(minutes: 2),
      movingTime: const Duration(minutes: 2),
      averagePaceSecondsPerKm: 120,
      currentPaceSecondsPerKm: 120,
      gpsAccuracyMeters: 5,
      acceptedPoints: 2,
      rejectedPoints: 0,
      route: const <RunPoint>[],
      splits: const <RunSplit>[],
      heartRateSamples: const <RunHeartRateSample>[
        RunHeartRateSample(elapsedSeconds: 0, bpm: 110),
        RunHeartRateSample(elapsedSeconds: 30, bpm: 142),
        RunHeartRateSample(elapsedSeconds: 60, bpm: 153),
      ],
      averageHeartRateBpm: 135,
    );

    final RunSession restored =
        RunSession.fromStorageMap(original.toStorageMap());

    expect(restored.averageHeartRateBpm, 135);
    expect(restored.heartRateSamples, hasLength(3));
    expect(restored.heartRateSamples[1].elapsedSeconds, 30);
    expect(restored.heartRateSamples[1].bpm, 142);
  });
}
