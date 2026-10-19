import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/run_segment_data.dart';

void main() {
  List<RunLap100m> makeLaps(int count) {
    return List<RunLap100m>.generate(count, (int index) {
      final int lapNumber = index + 1;
      return RunLap100m(
        distanceMeters: lapNumber * 100.0,
        durationMilliseconds: 40000,
        latitude: -7.8 + lapNumber * 0.0001,
        longitude: 110.3 + lapNumber * 0.0001,
        altitudeMeters: 50.0 + lapNumber.toDouble(),
      );
    }, growable: false);
  }

  test('default 100 m interval preserves every base segment', () {
    final List<RunDistanceSegment> segments =
        buildRunDistanceSegments(makeLaps(12), 100);

    expect(segments, hasLength(12));
    expect(segments.first.startMeters, 0);
    expect(segments.first.endMeters, 100);
    expect(segments.first.durationMilliseconds, 40000);
  });

  test('map/table share identical 300 m grouping and pace math', () {
    final List<RunDistanceSegment> segments =
        buildRunDistanceSegments(makeLaps(12), 300);

    expect(segments, hasLength(4));
    expect(segments[0].startMeters, 0);
    expect(segments[0].endMeters, 300);
    expect(segments[0].durationMilliseconds, 120000);
    expect(segments[0].paceSecondsPerKm, closeTo(400, 0.001));
    expect(segments[0].speedKmh, closeTo(9, 0.001));
    expect(segments[1].startMeters, 300);
    expect(segments[1].endMeters, 600);
  });

  test('large interval labels actual partial distance instead of pretending full', () {
    final List<RunDistanceSegment> segments =
        buildRunDistanceSegments(makeLaps(12), 5000);

    expect(segments, hasLength(1));
    expect(segments.single.startMeters, 0);
    expect(segments.single.endMeters, 1200);
    expect(segments.single.distanceMeters, 1200);
  });

  test('invalid interval falls back to 100 m', () {
    final List<RunDistanceSegment> segments =
        buildRunDistanceSegments(makeLaps(3), 250);

    expect(segments, hasLength(3));
  });
}
