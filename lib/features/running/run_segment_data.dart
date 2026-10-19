import 'models/run_session.dart';

/// Jarak segmen yang dapat dipakai bersama oleh peta dan tabel detail.
/// Sumber data tetap split dasar 100 m yang disimpan oleh mesin lari.
const List<int> runSegmentIntervalOptions = <int>[
  100,
  200,
  300,
  400,
  500,
  600,
  700,
  800,
  900,
  1000,
  5000,
  10000,
];

class RunDistanceSegment {
  const RunDistanceSegment({
    required this.startMeters,
    required this.endMeters,
    required this.durationMilliseconds,
    required this.latitude,
    required this.longitude,
    required this.relativeElevationMeters,
  });

  final double startMeters;
  final double endMeters;
  final int durationMilliseconds;
  final double latitude;
  final double longitude;
  final double? relativeElevationMeters;

  double get distanceMeters =>
      (endMeters - startMeters).clamp(0.0, double.infinity).toDouble();

  double get durationSeconds => durationMilliseconds / 1000.0;

  double? get paceSecondsPerKm {
    if (durationMilliseconds <= 0 || distanceMeters <= 0) return null;
    final double value = durationSeconds * 1000 / distanceMeters;
    return value.isFinite && value > 0 ? value : null;
  }

  double? get speedKmh {
    final double? pace = paceSecondsPerKm;
    if (pace == null || pace <= 0) return null;
    final double value = 3600 / pace;
    return value.isFinite ? value : null;
  }
}

/// Menggabungkan split 100 m untuk peta dan tabel dengan algoritme yang sama.
/// Segmen terakhir boleh lebih pendek dari opsi yang dipilih; labelnya tetap
/// memakai jarak sebenarnya agar tidak memberi kesan segmen penuh.
List<RunDistanceSegment> buildRunDistanceSegments(
  List<RunLap100m> laps,
  int intervalMeters,
) {
  if (laps.isEmpty) return const <RunDistanceSegment>[];

  final int safeInterval = runSegmentIntervalOptions.contains(intervalMeters)
      ? intervalMeters
      : 100;
  final int groupSize = (safeInterval / 100).round().clamp(1, 100).toInt();
  final List<RunLap100m> valid = laps.where((RunLap100m lap) {
    return lap.distanceMeters.isFinite &&
        lap.distanceMeters > 0 &&
        lap.latitude.isFinite &&
        lap.longitude.isFinite &&
        lap.latitude >= -90 &&
        lap.latitude <= 90 &&
        lap.longitude >= -180 &&
        lap.longitude <= 180 &&
        lap.durationMilliseconds > 0;
  }).toList(growable: false);
  if (valid.isEmpty) return const <RunDistanceSegment>[];

  double? elevationAtStart;
  for (final RunLap100m lap in valid) {
    final double? elevation = lap.altitudeMeters;
    if (elevation != null && elevation.isFinite) {
      elevationAtStart = elevation;
      break;
    }
  }

  final List<RunDistanceSegment> result = <RunDistanceSegment>[];
  for (int start = 0; start < valid.length; start += groupSize) {
    final int end = (start + groupSize).clamp(0, valid.length).toInt();
    final List<RunLap100m> group = valid.sublist(start, end);
    if (group.isEmpty) continue;

    final double startDistance = start == 0 ? 0 : valid[start - 1].distanceMeters;
    final RunLap100m last = group.last;
    final double endDistance = last.distanceMeters;
    if (!endDistance.isFinite || endDistance <= startDistance) continue;

    final int duration = group.fold<int>(
      0,
      (int total, RunLap100m lap) => total + lap.durationMilliseconds,
    );
    if (duration <= 0) continue;

    result.add(RunDistanceSegment(
      startMeters: startDistance,
      endMeters: endDistance,
      durationMilliseconds: duration,
      latitude: last.latitude,
      longitude: last.longitude,
      relativeElevationMeters: _relativeElevationAt(
        valid,
        end - 1,
        elevationAtStart,
      ),
    ));
  }
  return result;
}

double? _relativeElevationAt(
  List<RunLap100m> laps,
  int index,
  double? elevationAtStart,
) {
  final int first = (index - 2).clamp(0, laps.length - 1).toInt();
  final int last = (index + 2).clamp(0, laps.length - 1).toInt();
  final List<double> values = <double>[];
  for (int i = first; i <= last; i++) {
    final double? value = laps[i].altitudeMeters;
    if (value != null && value.isFinite) values.add(value);
  }
  if (values.isEmpty || elevationAtStart == null) return null;
  values.sort();
  return values[values.length ~/ 2] - elevationAtStart;
}
