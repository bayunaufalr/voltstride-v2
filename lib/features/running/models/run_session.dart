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
    return "$minutes:${seconds.toString().padLeft(2, '0')}/km";
  }
}

/// Snapshot lengkap sesi lari.
///
/// Objek ini sengaja tidak memegang controller atau subscription apa pun.
/// Ia hanya data, sehingga nanti bisa disimpan ke database lokal,
/// dikirim ke AI Coach, atau dikonversi ke payload Strava.
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
    if (accuracy == null || !accuracy.isFinite) {
      return '--';
    }
    return '${accuracy.toStringAsFixed(0)} m';
  }

  static String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}: '
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

/// Haversine dalam meter. Dipakai engine karena dependency aplikasi tidak
/// perlu ditambah hanya untuk satu perhitungan geodesi.
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
