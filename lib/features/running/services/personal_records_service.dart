import 'dart:math' as math;

import '../models/run_session.dart';

class DistanceRecordDefinition {
  final String key;
  final String label;
  final double distanceMeters;

  const DistanceRecordDefinition({
    required this.key,
    required this.label,
    required this.distanceMeters,
  });
}

class PersonalRecord {
  final DistanceRecordDefinition definition;
  final Duration duration;
  final RunSession session;
  final bool estimated;

  const PersonalRecord({
    required this.definition,
    required this.duration,
    required this.session,
    required this.estimated,
  });

  double get paceSecondsPerKm =>
      duration.inMilliseconds / 1000.0 / (definition.distanceMeters / 1000.0);
}

class PersonalRecordsService {
  PersonalRecordsService._();

  static const List<DistanceRecordDefinition> distances =
      <DistanceRecordDefinition>[
    DistanceRecordDefinition(
      key: 'mile',
      label: '1 mil',
      distanceMeters: 1609.344,
    ),
    DistanceRecordDefinition(
      key: '1k',
      label: '1 km',
      distanceMeters: 1000,
    ),
    DistanceRecordDefinition(
      key: '5k',
      label: '5 km',
      distanceMeters: 5000,
    ),
    DistanceRecordDefinition(
      key: '10k',
      label: '10 km',
      distanceMeters: 10000,
    ),
    DistanceRecordDefinition(
      key: 'half',
      label: 'Half marathon',
      distanceMeters: 21097.5,
    ),
    DistanceRecordDefinition(
      key: 'full',
      label: 'Full marathon',
      distanceMeters: 42195,
    ),
  ];

  static Map<String, PersonalRecord> calculate(List<RunSession> sessions) {
    final Map<String, PersonalRecord> records = <String, PersonalRecord>{};
    for (final DistanceRecordDefinition definition in distances) {
      PersonalRecord? best;
      for (final RunSession session in sessions) {
        if (session.activityType != RunActivityType.run) continue;
        if (session.distanceMeters < definition.distanceMeters) continue;
        final _DistanceTime? result = _timeAtDistance(
          session,
          definition.distanceMeters,
        );
        if (result == null || result.duration.inMilliseconds <= 0) continue;
        final PersonalRecord candidate = PersonalRecord(
          definition: definition,
          duration: result.duration,
          session: session,
          estimated: result.estimated,
        );
        if (best == null ||
            candidate.duration < best.duration ||
            (candidate.duration == best.duration &&
                !candidate.estimated && best.estimated)) {
          best = candidate;
        }
      }
      if (best != null) records[definition.key] = best;
    }
    return records;
  }

  static List<String> achievementsFor(
    RunSession current,
    List<RunSession> previousSessions,
  ) {
    final List<String> achievements = <String>[];
    final Map<String, PersonalRecord> previous = calculate(previousSessions);

    if (current.activityType == RunActivityType.run) {
      for (final DistanceRecordDefinition definition in distances) {
        if (current.distanceMeters < definition.distanceMeters) continue;
        final _DistanceTime? currentTime = _timeAtDistance(
          current,
          definition.distanceMeters,
        );
        if (currentTime == null || currentTime.estimated) continue;
        final PersonalRecord? old = previous[definition.key];
        if (old == null || currentTime.duration < old.duration) {
          achievements.add('${definition.label} tercepat kamu!');
        }
      }
    }

    final double oldLongest = previousSessions.where((RunSession s) => s.activityType == RunActivityType.run).fold<double>(
      0,
      (double value, RunSession session) =>
          math.max(value, session.distanceMeters),
    );
    if (current.activityType == RunActivityType.run && current.distanceMeters > oldLongest + 1) {
      achievements.add('Rekor lari terjauh: ${current.distanceKm.toStringAsFixed(2)} km!');
    }

    final RunElevationStats currentElevation = current.elevationStats;
    if (currentElevation.hasAltitudeData) {
      final double previousAscent = previousSessions.fold<double>(
        0,
        (double value, RunSession session) => session.elevationStats.hasAltitudeData
            ? math.max(value, session.elevationStats.totalAscentMeters)
            : value,
      );
      if (currentElevation.totalAscentMeters > previousAscent + 1) {
        achievements.add(
          'Rekor tanjakan: naik total ${currentElevation.totalAscentMeters.round()} m!',
        );
      }
      final double previousPeak = previousSessions.fold<double>(
        0,
        (double value, RunSession session) => session.elevationStats.hasAltitudeData
            ? math.max(value, session.elevationStats.maxAboveStartMeters)
            : value,
      );
      if (currentElevation.maxAboveStartMeters > previousPeak + 1) {
        achievements.add(
          'Puncak tertinggi dari titik start: +${currentElevation.maxAboveStartMeters.round()} m!',
        );
      }
    }
    return achievements;
  }

  static _DistanceTime? _timeAtDistance(
    RunSession session,
    double targetMeters,
  ) {
    if (session.distanceMeters < targetMeters || targetMeters <= 0) {
      return null;
    }

    final List<RunLap100m> laps = session.hundredMeterLaps;
    if (laps.isNotEmpty) {
      double previousMark = 0;
      double elapsedMilliseconds = 0;
      for (final RunLap100m lap in laps) {
        final double endMark = lap.distanceMeters;
        final double segmentMeters = endMark - previousMark;
        if (segmentMeters <= 0 || lap.durationMilliseconds <= 0) continue;

        if (targetMeters <= endMark) {
          final double metersInSegment =
              (targetMeters - previousMark)
                  .clamp(0.0, segmentMeters)
                  .toDouble();
          elapsedMilliseconds +=
              lap.durationMilliseconds * metersInSegment / segmentMeters;
          return _DistanceTime(
            Duration(milliseconds: elapsedMilliseconds.round()),
            false,
          );
        }

        elapsedMilliseconds += lap.durationMilliseconds;
        previousMark = endMark;
      }
    }

    final Duration moving = session.movingTime > Duration.zero
        ? session.movingTime
        : session.elapsed;
    if (session.distanceMeters <= 0 || moving.inMilliseconds <= 0) return null;
    final double estimate =
        moving.inMilliseconds * targetMeters / session.distanceMeters;
    return _DistanceTime(
      Duration(milliseconds: estimate.round()),
      true,
    );
  }

  static String formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String formatPace(double secondsPerKm) {
    if (!secondsPerKm.isFinite || secondsPerKm <= 0) return '--:--';
    final int rounded = secondsPerKm.round();
    return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')}';
  }
}

class _DistanceTime {
  final Duration duration;
  final bool estimated;

  const _DistanceTime(this.duration, this.estimated);
}
