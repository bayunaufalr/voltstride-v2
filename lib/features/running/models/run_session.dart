import 'dart:convert';
import 'dart:math' as math;

/// Status sesi lari dari sisi aplikasi.
enum RunStatus {
  idle,
  acquiringGps,
  running,
  paused,
  finished,
  error,
}

/// Titik rute yang sudah lolos penyaringan.
class RunPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double accuracyMeters;

  const RunPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracyMeters,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'accuracyMeters': accuracyMeters,
      };

  factory RunPoint.fromJson(Map<String, dynamic> json) {
    return RunPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
    );
  }
}

/// Split satu kilometer dari lari nyata.
class RunSplit {
  final int kilometer;
  final int durationSeconds;
  final int paceSecondsPerKm;
  final double distanceMeters;

  const RunSplit({
    required this.kilometer,
    required this.durationSeconds,
    required this.paceSecondsPerKm,
    required this.distanceMeters,
  });

  String get paceText {
    final int minutes = paceSecondsPerKm ~/ 60;
    final int seconds = paceSecondsPerKm % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}/km';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kilometer': kilometer,
        'durationSeconds': durationSeconds,
        'paceSecondsPerKm': paceSecondsPerKm,
        'distanceMeters': distanceMeters,
      };

  factory RunSplit.fromJson(Map<String, dynamic> json) {
    return RunSplit(
      kilometer: (json['kilometer'] as num).toInt(),
      durationSeconds: (json['durationSeconds'] as num).toInt(),
      paceSecondsPerKm: (json['paceSecondsPerKm'] as num).toInt(),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
    );
  }
}

/// Snapshot lengkap sesi lari.
///
/// Model tidak bergantung pada UI, GPS, atau database. Semua data dapat
/// diserialisasi untuk SQLite dan digunakan sebagai konteks AI Coach.
class RunSession {
  final DateTime startedAt;
  final DateTime? finishedAt;
  final double distanceMeters;
  final Duration elapsed;
  final Duration movingTime;
  final double? averagePaceSecondsPerKm;
  final double? currentPaceSecondsPerKm;
  final double? gpsAccuracyMeters;
  final int acceptedPoints;
  final int rejectedPoints;
  final List<RunPoint> route;
  final List<RunSplit> splits;

  const RunSession({
    required this.startedAt,
    required this.finishedAt,
    required this.distanceMeters,
    required this.elapsed,
    required this.movingTime,
    required this.averagePaceSecondsPerKm,
    required this.currentPaceSecondsPerKm,
    required this.gpsAccuracyMeters,
    required this.acceptedPoints,
    required this.rejectedPoints,
    required this.route,
    required this.splits,
  });

  double get distanceKm => distanceMeters / 1000.0;

  String get distanceText => distanceKm.toStringAsFixed(2);

  String get elapsedText => _formatDuration(elapsed);

  String get movingTimeText => _formatDuration(movingTime);

  String get averagePaceText => _formatPace(averagePaceSecondsPerKm);

  String get currentPaceText => _formatPace(currentPaceSecondsPerKm);

  String get gpsAccuracyText {
    final double? accuracy = gpsAccuracyMeters;
    if (accuracy == null || !accuracy.isFinite) return '--';
    return '${accuracy.toStringAsFixed(0)} m';
  }

  /// Mengubah sesi menjadi bentuk kolom SQLite.
  Map<String, Object?> toStorageMap() {
    return <String, Object?>{
      'startedAt': startedAt.toUtc().toIso8601String(),
      'finishedAt': finishedAt?.toUtc().toIso8601String(),
      'distanceMeters': distanceMeters,
      'elapsedMilliseconds': elapsed.inMilliseconds,
      'movingMilliseconds': movingTime.inMilliseconds,
      'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
      'currentPaceSecondsPerKm': currentPaceSecondsPerKm,
      'gpsAccuracyMeters': gpsAccuracyMeters,
      'acceptedPoints': acceptedPoints,
      'rejectedPoints': rejectedPoints,
      'routeJson': jsonEncode(
        route.map((RunPoint point) => point.toJson()).toList(),
      ),
      'splitsJson': jsonEncode(
        splits.map((RunSplit split) => split.toJson()).toList(),
      ),
    };
  }

  /// Membuat kembali sesi dari baris SQLite.
  factory RunSession.fromStorageMap(Map<String, Object?> row) {
    final List<dynamic> routeJson =
        jsonDecode(row['routeJson'] as String) as List<dynamic>;
    final List<dynamic> splitsJson =
        jsonDecode(row['splitsJson'] as String) as List<dynamic>;

    final Object? finishedAtValue = row['finishedAt'];
    final Object? averagePaceValue = row['averagePaceSecondsPerKm'];
    final Object? currentPaceValue = row['currentPaceSecondsPerKm'];
    final Object? accuracyValue = row['gpsAccuracyMeters'];

    return RunSession(
      startedAt: DateTime.parse(row['startedAt'] as String),
      finishedAt: finishedAtValue == null
          ? null
          : DateTime.parse(finishedAtValue as String),
      distanceMeters: (row['distanceMeters'] as num).toDouble(),
      elapsed: Duration(
        milliseconds: (row['elapsedMilliseconds'] as num).toInt(),
      ),
      movingTime: Duration(
        milliseconds: (row['movingMilliseconds'] as num).toInt(),
      ),
      averagePaceSecondsPerKm: averagePaceValue == null
          ? null
          : (averagePaceValue as num).toDouble(),
      currentPaceSecondsPerKm: currentPaceValue == null
          ? null
          : (currentPaceValue as num).toDouble(),
      gpsAccuracyMeters: accuracyValue == null
          ? null
          : (accuracyValue as num).toDouble(),
      acceptedPoints: (row['acceptedPoints'] as num).toInt(),
      rejectedPoints: (row['rejectedPoints'] as num).toInt(),
      route: routeJson
          .map(
            (dynamic item) => RunPoint.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      splits: splitsJson
          .map(
            (dynamic item) => RunSplit.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  static String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatPace(double? paceSecondsPerKm) {
    if (paceSecondsPerKm == null ||
        !paceSecondsPerKm.isFinite ||
        paceSecondsPerKm <= 0 ||
        paceSecondsPerKm > 3600) {
      return '--:--';
    }

    final int rounded = paceSecondsPerKm.round();
    final int minutes = rounded ~/ 60;
    final int seconds = rounded % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Haversine dalam meter.
double distanceBetweenMeters({
  required double latitude1,
  required double longitude1,
  required double latitude2,
  required double longitude2,
}) {
  const double earthRadiusMeters = 6371000.0;
  final double lat1 = latitude1 * math.pi / 180.0;
  final double lat2 = latitude2 * math.pi / 180.0;
  final double deltaLat = (latitude2 - latitude1) * math.pi / 180.0;
  final double deltaLon = (longitude2 - longitude1) * math.pi / 180.0;

  final double sinLat = math.sin(deltaLat / 2.0);
  final double sinLon = math.sin(deltaLon / 2.0);
  final double a = sinLat * sinLat +
      math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
  final double safeA = a.clamp(0.0, 1.0);
  final double c = 2.0 * math.atan2(
    math.sqrt(safeA),
    math.sqrt(1.0 - safeA),
  );

  return earthRadiusMeters * c;
}
