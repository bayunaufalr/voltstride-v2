import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/personal_records_service.dart';

void main() {
  RunSession createFiveKilometerSession() {
    final List<RunLap100m> laps = List<RunLap100m>.generate(
      50,
      (int index) => RunLap100m(
        distanceMeters: (index + 1) * 100.0,
        durationMilliseconds: 20000,
        latitude: -7.8,
        longitude: 110.3,
      ),
      growable: false,
    );

    return RunSession(
      startedAt: DateTime.utc(2026, 10, 15, 4),
      finishedAt: DateTime.utc(2026, 10, 15, 4, 16, 40),
      distanceMeters: 5000,
      elapsed: const Duration(seconds: 1000),
      movingTime: const Duration(seconds: 1000),
      averagePaceSecondsPerKm: 200,
      currentPaceSecondsPerKm: null,
      gpsAccuracyMeters: 5,
      acceptedPoints: 51,
      rejectedPoints: 0,
      route: const <RunPoint>[],
      splits: const <RunSplit>[],
      hundredMeterLaps: laps,
    );
  }

  test('personal records use measured 100 metre segments when available', () {
    final RunSession session = createFiveKilometerSession();
    final Map<String, PersonalRecord> records =
        PersonalRecordsService.calculate(<RunSession>[session]);

    expect(records['1k'], isNotNull);
    expect(records['5k'], isNotNull);
    expect(records['5k']!.duration, const Duration(seconds: 1000));
    expect(records['5k']!.estimated, isFalse);
    expect(
      PersonalRecordsService.formatPace(records['5k']!.paceSecondsPerKm),
      '3:20',
    );
  });

  test('a new measured session announces distance and longest-run records', () {
    final RunSession session = createFiveKilometerSession();
    final List<String> achievements = PersonalRecordsService.achievementsFor(
      session,
      const <RunSession>[],
    );

    expect(achievements, contains('1 km tercepat kamu!'));
    expect(achievements, contains('5 km tercepat kamu!'));
    expect(achievements, contains('Rekor lari terjauh: 5.00 km!'));
  });
}
