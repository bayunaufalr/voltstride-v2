import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../running/models/run_session.dart';
import '../running/services/run_history_repository.dart';

class TrainingDataExportService {
  TrainingDataExportService._();

  static Future<int> shareAllSessions() async {
    final List<RunSession> sessions =
        await RunHistoryRepository.instance.getAll();
    final DateTime exportedAt = DateTime.now();
    final Map<String, Object?> payload = <String, Object?>{
      'format': 'voltstride-training-data',
      'version': 2,
      'sessionCount': sessions.length,
      'privacy': <String, Object?>{
        'gpsCoordinatesIncluded': false,
        'routeIncluded': false,
        'profileIncluded': false,
        'exactSessionTimesIncluded': false,
        'bodyMeasurementsIncluded': false,
        'note': 'Only workout metrics and the calendar day are included. Names, contact details, birth date, body measurements, GPS, routes, exact times, notes and raw samples are excluded.',
      },
      'sessions': sessions.map(_sessionToJson).toList(growable: false),
    };

    final String stamp = '${exportedAt.year.toString().padLeft(4, '0')}'
        '${exportedAt.month.toString().padLeft(2, '0')}'
        '${exportedAt.day.toString().padLeft(2, '0')}-'
        '${exportedAt.hour.toString().padLeft(2, '0')}'
        '${exportedAt.minute.toString().padLeft(2, '0')}';
    final File file = File(
      '${Directory.systemTemp.path}/voltstride-training-$stamp.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'application/json'),
        ],
        title: 'VoltStride training data',
        text: 'Workout metrics only. Personal profile, body measurements, GPS route and exact session times are excluded.',
      ),
    );
    return sessions.length;
  }

  static Map<String, Object?> _sessionToJson(RunSession session) {
    final elevation = session.elevationStats;
    final DateTime localDate = session.startedAt.toLocal();
    final Map<String, Object?> result = <String, Object?>{
      'trainingDay': '${localDate.year.toString().padLeft(4, '0')}-'
          '${localDate.month.toString().padLeft(2, '0')}-'
          '${localDate.day.toString().padLeft(2, '0')}',
      'activityType': session.activityType.name,
      'distanceMeters': _finite(session.distanceMeters),
      'elapsedSeconds': session.elapsed.inSeconds,
      'movingSeconds': session.movingTime.inSeconds,
      'averagePaceSecondsPerKm': _finiteOrNull(session.averagePaceSecondsPerKm),
      'averageSpeedKmh': _finiteOrNull(session.averageSpeedKmh),
      'averageHeartRateBpm': session.averageHeartRateBpm,
      'totalSteps': session.totalSteps,
      'averageCadenceSpm': _finiteOrNull(session.averageCadenceSpm),
      'maxCadenceSpm': _finiteOrNull(session.maxCadenceSpm),
      'elevationAscentMeters': elevation.hasAltitudeData
          ? _finite(elevation.totalAscentMeters)
          : null,
      'elevationDescentMeters': elevation.hasAltitudeData
          ? _finite(elevation.totalDescentMeters)
          : null,
    };
    final interval = session.intervalPlan;
    if (interval != null) {
      result['interval'] = <String, Object?>{
        'workSeconds': interval.workSeconds,
        'recoverySeconds': interval.recoverySeconds,
        'repetitions': interval.repetitions,
      };
    }
    return result;
  }

  static double _finite(double value) => value.isFinite ? value : 0;

  static double? _finiteOrNull(double? value) {
    if (value == null || !value.isFinite) return null;
    return value;
  }
}
