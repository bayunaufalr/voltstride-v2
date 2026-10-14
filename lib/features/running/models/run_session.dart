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

enum RunActivityType { run, walk }
enum RunEnvironment { outdoor, indoor }

extension RunActivityTypeLabel on RunActivityType {
  String get label => this == RunActivityType.walk ? 'Berjalan' : 'Berlari';
}

extension RunEnvironmentLabel on RunEnvironment {
  String get label => this == RunEnvironment.indoor
      ? 'Dalam ruangan'
      : 'Luar ruangan';
}

/// Titik rute yang sudah lolos penyaringan.
class RunPoint {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double accuracyMeters;
  /// Estimasi ketinggian dari GPS dalam meter di atas permukaan laut.
  /// Null untuk data lama atau ketika nilai GPS tidak valid.
  final double? altitudeMeters;

  /// True when this point starts a new uninterrupted GPS track segment, for
  /// example after resuming a paused run. Map renderers must not connect the
  /// previous point to this one with a straight line.
  final bool startsNewSegment;

  const RunPoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.accuracyMeters,
    this.altitudeMeters,
    this.startsNewSegment = false,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'accuracyMeters': accuracyMeters,
        'altitudeMeters': altitudeMeters,
        'startsNewSegment': startsNewSegment,
      };

  factory RunPoint.fromJson(Map<String, dynamic> json) {
    return RunPoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracyMeters: (json['accuracyMeters'] as num).toDouble(),
      altitudeMeters: json['altitudeMeters'] == null
          ? null
          : (json['altitudeMeters'] as num).toDouble(),
      startsNewSegment: json['startsNewSegment'] == true,
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


/// Satu segmen tepat 100 meter yang dihitung dari perpindahan GPS valid.
/// Koordinat menunjukkan titik interpolasi ketika jarak kumulatif melewati
/// kelipatan 100 m. Waktu segmen menggunakan waktu aktif stopwatch (pause
/// dikecualikan), bukan waktu dinding yang mencakup jeda.
class RunLap100m {
  final double distanceMeters;
  final int durationMilliseconds;
  final double latitude;
  final double longitude;
  /// Ketinggian GPS di lokasi penanda 100 m.
  final double? altitudeMeters;

  const RunLap100m({
    required this.distanceMeters,
    required this.durationMilliseconds,
    required this.latitude,
    required this.longitude,
    this.altitudeMeters,
  });

  double get durationSeconds => durationMilliseconds / 1000.0;

  double? get speedKmh {
    if (durationMilliseconds <= 0) return null;
    return 360000.0 / durationMilliseconds;
  }

  double? get paceSecondsPerKm {
    if (durationMilliseconds <= 0) return null;
    return durationMilliseconds / 100.0;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'distanceMeters': distanceMeters,
        'durationMilliseconds': durationMilliseconds,
        'latitude': latitude,
        'longitude': longitude,
        'altitudeMeters': altitudeMeters,
      };

  factory RunLap100m.fromJson(Map<String, dynamic> json) => RunLap100m(
        distanceMeters: (json['distanceMeters'] as num).toDouble(),
        durationMilliseconds: (json['durationMilliseconds'] as num).toInt(),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        altitudeMeters: json['altitudeMeters'] == null
            ? null
            : (json['altitudeMeters'] as num).toDouble(),
      );
}

enum IntervalStage { work, recovery, complete }

class IntervalPhase {
  final IntervalStage stage;
  final int repetition;
  final int secondsRemaining;

  const IntervalPhase({
    required this.stage,
    required this.repetition,
    required this.secondsRemaining,
  });
}

/// Konfigurasi latihan interval lari yang dipilih pengguna.
class IntervalRunPlan {
  final int workSeconds;
  final int recoverySeconds;
  final int repetitions;

  const IntervalRunPlan({
    required this.workSeconds,
    required this.recoverySeconds,
    required this.repetitions,
  });

  int get cycleSeconds => workSeconds + recoverySeconds;

  int get totalSeconds => cycleSeconds * repetitions;

  IntervalPhase phaseAt(Duration elapsed) {
    final int seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    if (seconds >= totalSeconds) {
      return IntervalPhase(
        stage: IntervalStage.complete,
        repetition: repetitions,
        secondsRemaining: 0,
      );
    }

    final int repetition = seconds ~/ cycleSeconds + 1;
    final int cyclePosition = seconds % cycleSeconds;
    if (cyclePosition < workSeconds) {
      return IntervalPhase(
        stage: IntervalStage.work,
        repetition: repetition,
        secondsRemaining: workSeconds - cyclePosition,
      );
    }

    return IntervalPhase(
      stage: IntervalStage.recovery,
      repetition: repetition,
      secondsRemaining: cycleSeconds - cyclePosition,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'workSeconds': workSeconds,
        'recoverySeconds': recoverySeconds,
        'repetitions': repetitions,
      };

  factory IntervalRunPlan.fromJson(Map<String, dynamic> json) =>
      IntervalRunPlan(
        workSeconds: (json['workSeconds'] as num).toInt(),
        recoverySeconds: (json['recoverySeconds'] as num).toInt(),
        repetitions: (json['repetitions'] as num).toInt(),
      );
}


/// Ringkasan elevasi berbasis perubahan altitude GPS yang cukup besar.
/// Perubahan di bawah ambang 3 m diabaikan untuk menekan noise GPS.
class RunElevationStats {
  final double totalAscentMeters;
  final double totalDescentMeters;
  final double netChangeMeters;
  final double maxAboveStartMeters;
  final bool hasAltitudeData;

  const RunElevationStats({
    required this.totalAscentMeters,
    required this.totalDescentMeters,
    required this.netChangeMeters,
    required this.maxAboveStartMeters,
    required this.hasAltitudeData,
  });
}

RunElevationStats calculateRunElevation(List<RunPoint> route) {
  const double noiseThresholdMeters = 3.0;
  final List<RunPoint> valid = route
      .where((RunPoint point) =>
          point.altitudeMeters != null && point.altitudeMeters!.isFinite)
      .toList(growable: false);
  if (valid.isEmpty) {
    return const RunElevationStats(
      totalAscentMeters: 0,
      totalDescentMeters: 0,
      netChangeMeters: 0,
      maxAboveStartMeters: 0,
      hasAltitudeData: false,
    );
  }

  final double startAltitude = valid.first.altitudeMeters!;
  double referenceAltitude = startAltitude;
  double ascent = 0;
  double descent = 0;
  double maximumAboveStart = 0;

  for (final RunPoint point in valid.skip(1)) {
    final double altitude = point.altitudeMeters!;
    final double relativeToStart = altitude - startAltitude;
    if (relativeToStart >= noiseThresholdMeters &&
        relativeToStart > maximumAboveStart) {
      maximumAboveStart = relativeToStart;
    }

    // Jangan menghubungkan elevasi antarsegmen GPS yang terpisah oleh jeda.
    if (point.startsNewSegment) {
      referenceAltitude = altitude;
      continue;
    }

    final double delta = altitude - referenceAltitude;
    if (delta >= noiseThresholdMeters) {
      ascent += delta;
      referenceAltitude = altitude;
    } else if (delta <= -noiseThresholdMeters) {
      descent += -delta;
      referenceAltitude = altitude;
    }
  }

  return RunElevationStats(
    totalAscentMeters: ascent,
    totalDescentMeters: descent,
    netChangeMeters: ascent - descent,
    maxAboveStartMeters: maximumAboveStart,
    hasAltitudeData: true,
  );
}

/// Snapshot lengkap sesi lari.
///
/// Model tidak bergantung pada UI, GPS, atau database. Semua data dapat
/// diserialisasi untuk SQLite dan digunakan oleh evaluasi lari lokal.
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
  final List<RunLap100m> hundredMeterLaps;
  final IntervalRunPlan? intervalPlan;
  final RunActivityType activityType;
  final RunEnvironment environment;

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
    this.hundredMeterLaps = const <RunLap100m>[],
    this.intervalPlan,
    this.activityType = RunActivityType.run,
    this.environment = RunEnvironment.outdoor,
  });

  String get displayLabel =>
      intervalPlan == null ? activityType.label : 'Lari interval';

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

  RunElevationStats get elevationStats => calculateRunElevation(route);

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
      'hundredMeterLapsJson': jsonEncode(
        hundredMeterLaps.map((RunLap100m lap) => lap.toJson()).toList(),
      ),
      'intervalPlanJson': intervalPlan == null
          ? null
          : jsonEncode(intervalPlan!.toJson()),
      'activityType': activityType.name,
      'environment': environment.name,
    };
  }

  /// Membuat kembali sesi dari baris SQLite.
  factory RunSession.fromStorageMap(Map<String, Object?> row) {
    final List<dynamic> routeJson =
        jsonDecode(row['routeJson'] as String) as List<dynamic>;
    final List<dynamic> splitsJson =
        jsonDecode(row['splitsJson'] as String) as List<dynamic>;
    final Object? lapsJsonValue = row['hundredMeterLapsJson'];
    final List<dynamic> lapsJson = lapsJsonValue is String
        ? jsonDecode(lapsJsonValue) as List<dynamic>
        : <dynamic>[];
    final Object? intervalJsonValue = row['intervalPlanJson'];
    final IntervalRunPlan? plan = intervalJsonValue is String &&
            intervalJsonValue.isNotEmpty
        ? IntervalRunPlan.fromJson(
            jsonDecode(intervalJsonValue) as Map<String, dynamic>,
          )
        : null;

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
      hundredMeterLaps: lapsJson
          .map(
            (dynamic item) => RunLap100m.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
      intervalPlan: plan,
      activityType: RunActivityType.values.firstWhere(
        (RunActivityType value) => value.name == row['activityType'],
        orElse: () => RunActivityType.run,
      ),
      environment: RunEnvironment.values.firstWhere(
        (RunEnvironment value) => value.name == row['environment'],
        orElse: () => RunEnvironment.outdoor,
      ),
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
