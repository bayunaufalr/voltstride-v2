import 'dart:convert';
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import '../running/models/run_session.dart';
import '../running/services/run_history_repository.dart';

/// Mengemas riwayat latihan menjadi satu JSON yang mudah dianalisis AI.
/// Koordinat GPS dan rute mentah sengaja tidak diekspor demi privasi.
class TrainingDataExportService {
  TrainingDataExportService._();

  static Future<int> shareAllSessions() async {
    final List<RunSession> sessions =
        await RunHistoryRepository.instance.getAll();
    final DateTime exportedAt = DateTime.now();
    final Map<String, Object?> payload = <String, Object?>{
      'format': 'voltstride-training-data',
      'version': 1,
      'exportedAt': exportedAt.toUtc().toIso8601String(),
      'sessionCount': sessions.length,
      'privacy': <String, Object?>{
        'gpsCoordinatesIncluded': false,
        'note': 'Aggregate training metrics only. Raw GPS route coordinates are excluded.',
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
        text: 'Training history export for AI analysis. GPS coordinates are excluded.',
      ),
    );
    return sessions.length;
  }

  static Map<String, Object?> _sessionToJson(RunSession session) {
    final elevation = session.elevationStats;
    return <String, Object?>{
      'startedAt': session.startedAt.toUtc().toIso8601String(),
      'finishedAt': session.finishedAt?.toUtc().toIso8601String(),
      'activityType': session.activityType.name,
      'environment': session.environment.name,
      'distanceMeters': _finite(session.distanceMeters),
      'distanceKilometers': _finite(session.distanceKm),
      'elapsedSeconds': session.elapsed.inSeconds,
      'movingSeconds': session.movingTime.inSeconds,
      'averagePaceSecondsPerKm': _finiteOrNull(session.averagePaceSecondsPerKm),
      'averageHeartRateBpm': session.averageHeartRateBpm,
      'totalSteps': session.totalSteps,
      'averageCadenceSpm': _finiteOrNull(session.averageCadenceSpm),
      'maxCadenceSpm': _finiteOrNull(session.maxCadenceSpm),
      'gpsAccuracyMeters': _finiteOrNull(session.gpsAccuracyMeters),
      'gpsAcceptedPoints': session.acceptedPoints,
      'gpsRejectedPoints': session.rejectedPoints,
      'elevation': <String, Object?>{
        'hasData': elevation.hasAltitudeData,
        'ascentMeters': _finite(elevation.totalAscentMeters),
        'descentMeters': _finite(elevation.totalDescentMeters),
        'netChangeMeters': _finite(elevation.netChangeMeters),
      },
      'splits': session.splits.map((split) => split.toJson()).toList(growable: false),
      'hundredMeterLaps': session.hundredMeterLaps.map((lap) {
        return <String, Object?>{
          'distanceMeters': _finite(lap.distanceMeters),
          'durationMilliseconds': lap.durationMilliseconds,
          'paceSecondsPerKm': _finiteOrNull(lap.paceSecondsPerKm),
          'speedKmh': _finiteOrNull(lap.speedKmh),
        };
      }).toList(growable: false),
      'intervalPlan': session.intervalPlan?.toJson(),
      'cadenceSamples': session.cadenceSamples
          .map((sample) => sample.toJson())
          .toList(growable: false),
    };
  }

  static double _finite(double value) => value.isFinite ? value : 0;

  static double? _finiteOrNull(double? value) {
    if (value == null || !value.isFinite) return null;
    return value;
  }
}
