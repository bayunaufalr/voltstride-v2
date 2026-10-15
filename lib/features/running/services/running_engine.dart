import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/lokasi_service.dart';
import '../models/run_session.dart';
import 'pace_sample.dart';
import 'running_notification_service.dart';

/// Abstraksi sumber lokasi supaya RunningEngine dapat diuji tanpa perangkat.
abstract class RunningLocationSource {
  Future<bool> isServiceEnabled();

  Future<bool> requestPermission();

  Future<Position?> getCurrentPosition();

  Stream<Position> getPositionStream();
}

/// Implementasi nyata yang menghubungkan engine dengan Geolocator.
class GeolocatorRunningLocationSource implements RunningLocationSource {
  const GeolocatorRunningLocationSource();

  @override
  Future<bool> isServiceEnabled() {
    return LokasiService.cekLayananAktif();
  }

  @override
  Future<bool> requestPermission() {
    return LokasiService.mintaIzin();
  }

  @override
  Future<Position?> getCurrentPosition() {
    return LokasiService.ambilSatuTitik();
  }

  @override
  Stream<Position> getPositionStream() {
    return LokasiService.pasangStream();
  }
}

/// Mesin lari VoltStride V2.
///
/// Tanggung jawab engine:
/// - mengelola state sesi lari;
/// - meminta dan menerima data GPS;
/// - menolak titik yang tidak layak atau tidak masuk akal;
/// - menghitung jarak dari posisi GPS mentah yang sudah divalidasi;
/// - melakukan smoothing hanya untuk visualisasi route;
/// - menghitung elapsed time, moving time, pace, dan split;
/// - menangani pause/resume tanpa lonjakan jarak;
/// - menghasilkan [RunSession] saat sesi selesai.
class RunningEngine extends ChangeNotifier {
  static const double maxAccuracyMeters = 50.0;
  static const double maxSpeedKmh = 35.0;
  // Jangan membuang setiap langkah pelan. Ambang adaptif di bawah menjaga
  // gerakan kecil tetap dihitung tanpa menjumlahkan jitter GPS yang sangat kecil.
  static const double minMovementMeters = 0.7;
  static const double maxMovementThresholdMeters = 1.25;
  static const double movingSpeedMps = 1.0;
  static const double minPaceSpeedMps = 0.7;
  static const double maxPaceSpeedMps = 8.0;
  static const double minimumPaceDistanceMeters = 15.0;
  static const int paceWindowSeconds = 12;
  static const int minimumPaceWindowSeconds = 8;
  static const double minimumAveragePaceDistanceMeters = 100.0;
  static const int updateIntervalMilliseconds = 1000;

  RunningEngine({RunningLocationSource? locationSource})
      : _locationSource =
            locationSource ?? const GeolocatorRunningLocationSource();

  final RunningLocationSource _locationSource;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _uiTimer;
  Timer? _notificationTimer;
  Stopwatch? _stopwatch;
  bool _notificationUpdateInProgress = false;
  bool _disposed = false;
  int _startGeneration = 0;

  RunStatus _status = RunStatus.idle;
  String? _errorMessage;

  DateTime? _startedAt;
  DateTime? _finishedAt;

  Duration _movingTime = Duration.zero;
  Duration _lastSplitMovingTime = Duration.zero;

  double _distanceMeters = 0.0;
  double? _currentPaceSecondsPerKm;
  double? _gpsAccuracyMeters;

  int _acceptedPoints = 0;
  int _rejectedPoints = 0;

  double? _lastRawLatitude;
  double? _lastRawLongitude;
  double? _lastRawAltitudeMeters;
  DateTime? _lastRawTimestamp;

  double? _filteredLatitude;
  double? _filteredLongitude;
  double? _filteredAccuracyMeters;

  double _lastSplitDistanceMeters = 0.0;
  int _lastAcceptedElapsedMilliseconds = 0;
  int _lastHundredMeterCrossingElapsedMilliseconds = 0;
  double _nextHundredMeterMark = 100.0;
  IntervalRunPlan? _intervalPlan;
  bool _useGps = true;
  RunActivityType _activityType = RunActivityType.run;
  RunEnvironment _environment = RunEnvironment.outdoor;

  /// Setelah resume, titik GPS pertama hanya menjadi anchor baru.
  /// Titik tersebut tidak menghasilkan jarak terhadap posisi sebelum pause.
  bool _awaitingResumeAnchor = false;

  final List<RunPoint> _route = <RunPoint>[];
  final List<RunSplit> _splits = <RunSplit>[];
  final List<RunLap100m> _hundredMeterLaps = <RunLap100m>[];
  final List<PaceSample> _paceSamples = <PaceSample>[];

  RunSession? _lastFinishedSession;

  RunStatus get status => _status;
  String? get errorMessage => _errorMessage;
  RunSession? get lastFinishedSession => _lastFinishedSession;

  bool get isActive =>
      _status == RunStatus.acquiringGps ||
      _status == RunStatus.running ||
      _status == RunStatus.paused;

  double get distanceMeters => _distanceMeters;
  double get distanceKm => _distanceMeters / 1000.0;
  Duration get elapsed => _stopwatch?.elapsed ?? Duration.zero;
  Duration get movingTime => _movingTime;

  double? get currentPaceSecondsPerKm => _currentPaceSecondsPerKm;

  double? get averagePaceSecondsPerKm {
    if (_movingTime.inMilliseconds <= 0 ||
        _distanceMeters < minimumAveragePaceDistanceMeters) {
      return null;
    }

    return _movingTime.inMilliseconds / 1000.0 /
        (_distanceMeters / 1000.0);
  }

  double? get gpsAccuracyMeters => _gpsAccuracyMeters;
  int get acceptedPoints => _acceptedPoints;
  int get rejectedPoints => _rejectedPoints;
  int get splitCount => _splits.length;
  int get routeLength => _route.length;

  List<RunPoint> get route => List<RunPoint>.unmodifiable(_route);
  List<RunSplit> get splits => List<RunSplit>.unmodifiable(_splits);
  List<RunLap100m> get hundredMeterLaps =>
      List<RunLap100m>.unmodifiable(_hundredMeterLaps);
  IntervalRunPlan? get intervalPlan => _intervalPlan;

  double get gpsCleanRatio {
    final int total = _acceptedPoints + _rejectedPoints;
    if (total == 0) return 0.0;
    return _acceptedPoints / total;
  }

  /// Memulai sesi lari baru.
  Future<void> start({
    IntervalRunPlan? intervalPlan,
    bool useGps = true,
    RunActivityType activityType = RunActivityType.run,
    RunEnvironment environment = RunEnvironment.outdoor,
    Future<void> Function()? onGpsReady,
  }) async {
    if (_disposed || isActive) return;
    final int generation = ++_startGeneration;

    _resetSessionData();
    _intervalPlan = intervalPlan;
    _useGps = useGps;
    _activityType = activityType;
    _environment = environment;
    _errorMessage = null;
    _status = RunStatus.acquiringGps;
    _notifyIfAlive();

    if (!useGps) {
      try {
        await onGpsReady?.call();
      } catch (_) {
        if (!_isStaleStart(generation)) {
          _fail('Persiapan aktivitas gagal. Coba mulai lagi.');
        }
        return;
      }
      if (_isStaleStart(generation)) return;
      _startedAt = DateTime.now();
      _stopwatch = Stopwatch()..start();
      _status = RunStatus.running;
      _uiTimer?.cancel();
      _uiTimer = Timer.periodic(
        const Duration(milliseconds: updateIntervalMilliseconds),
        (_) => _notifyIfAlive(),
      );
      _startNotificationUpdates();
      _notifyIfAlive();
      return;
    }

    bool serviceEnabled;
    try {
      serviceEnabled = await _locationSource.isServiceEnabled();
    } catch (_) {
      if (!_isStaleStart(generation)) {
        _fail('Tidak dapat memeriksa layanan lokasi. Coba lagi.');
      }
      return;
    }
    if (_isStaleStart(generation)) return;
    if (!serviceEnabled) {
      _fail('Layanan lokasi perangkat sedang mati.');
      return;
    }

    bool permissionGranted;
    try {
      permissionGranted = await _locationSource.requestPermission();
    } catch (_) {
      if (!_isStaleStart(generation)) {
        _fail('Tidak dapat meminta izin lokasi. Periksa pengaturan aplikasi.');
      }
      return;
    }
    if (_isStaleStart(generation)) return;
    if (!permissionGranted) {
      _fail('Izin lokasi belum diberikan.');
      return;
    }

    Position? firstPosition;
    try {
      firstPosition = await _locationSource
          .getCurrentPosition()
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
    } catch (_) {
      if (!_isStaleStart(generation)) {
        _fail('Gagal membaca lokasi GPS. Periksa sinyal dan izin lokasi.');
      }
      return;
    }
    if (_isStaleStart(generation)) return;

    if (firstPosition == null) {
      _fail(
        'Belum mendapatkan posisi GPS. Coba pindah ke area yang lebih terbuka.',
      );
      return;
    }

    if (!_isPositionUsable(firstPosition)) {
      _fail(
        'Akurasi GPS terlalu rendah. Tunggu sampai sinyal membaik.',
      );
      return;
    }

    try {
      await onGpsReady?.call();
    } catch (_) {
      if (!_isStaleStart(generation)) {
        _fail('Persiapan sebelum mulai gagal. Coba mulai lagi.');
      }
      return;
    }
    if (_isStaleStart(generation)) return;

    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _seedPosition(firstPosition);
    _status = RunStatus.running;

    try {
      _positionSubscription = _locationSource.getPositionStream().listen(
        _onPosition,
        onError: _onPositionError,
        cancelOnError: false,
      );
    } catch (_) {
      _fail('Pelacakan GPS tidak dapat dimulai. Coba mulai aktivitas lagi.');
      return;
    }

    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(
      const Duration(milliseconds: updateIntervalMilliseconds),
      (_) => _notifyIfAlive(),
    );
    _startNotificationUpdates();

    _notifyIfAlive();
  }

  /// Menjeda stopwatch dan membekukan akumulasi sesi.
  ///
  /// Stream GPS tetap berjalan supaya permission dan subscription tidak
  /// perlu dibuat ulang. Posisi yang datang saat pause diabaikan.
  void pause() {
    if (_status != RunStatus.running) return;

    _stopwatch?.stop();
    _status = RunStatus.paused;
    _currentPaceSecondsPerKm = null;
    unawaited(_updateRunNotificationSafely());
    _notifyIfAlive();
  }

  /// Melanjutkan sesi tanpa menghitung perpindahan selama masa pause.
  ///
  /// Titik GPS pertama setelah resume menjadi anchor baru. Dengan begitu,
  /// perpindahan dari lokasi terakhir sebelum pause ke lokasi pertama setelah
  /// resume tidak dianggap sebagai jarak lari.
  void resume() {
    if (_status != RunStatus.paused) return;

    _stopwatch?.start();
    _awaitingResumeAnchor = true;
    _currentPaceSecondsPerKm = null;
    _status = RunStatus.running;
    unawaited(_updateRunNotificationSafely());
    _notifyIfAlive();
  }

  /// Mengakhiri sesi dan menghasilkan snapshot final.
  RunSession? finish({double? indoorDistanceMeters}) {
    if (!isActive) {
      return _lastFinishedSession;
    }

    _finishedAt = DateTime.now();
    _stopwatch?.stop();
    if (!_useGps && indoorDistanceMeters != null &&
        indoorDistanceMeters.isFinite && indoorDistanceMeters >= 0) {
      _distanceMeters = indoorDistanceMeters;
      _movingTime = elapsed;
    }
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    unawaited(RunningNotificationService.stop());

    _status = RunStatus.finished;
    _currentPaceSecondsPerKm = null;

    final RunSession session = _buildSession();
    _lastFinishedSession = session;
    _notifyIfAlive();
    return session;
  }

  /// Menghapus hasil sesi dan kembali ke keadaan siap.
  void reset() {
    if (_disposed) return;
    _startGeneration++;
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    unawaited(RunningNotificationService.stop());
    _stopwatch?.stop();

    _status = RunStatus.idle;
    _errorMessage = null;
    _lastFinishedSession = null;
    _resetSessionData();
    _notifyIfAlive();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _startGeneration++;
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _notificationTimer?.cancel();
    unawaited(RunningNotificationService.stop());
    _stopwatch?.stop();
    super.dispose();
  }

  void _resetSessionData() {
    _stopwatch = null;
    _startedAt = null;
    _finishedAt = null;
    _movingTime = Duration.zero;
    _lastSplitMovingTime = Duration.zero;
    _distanceMeters = 0.0;
    _currentPaceSecondsPerKm = null;
    _gpsAccuracyMeters = null;
    _acceptedPoints = 0;
    _rejectedPoints = 0;
    _lastRawLatitude = null;
    _lastRawLongitude = null;
    _lastRawAltitudeMeters = null;
    _lastRawTimestamp = null;
    _filteredLatitude = null;
    _filteredLongitude = null;
    _filteredAccuracyMeters = null;
    _lastSplitDistanceMeters = 0.0;
    _lastAcceptedElapsedMilliseconds = 0;
    _lastHundredMeterCrossingElapsedMilliseconds = 0;
    _nextHundredMeterMark = 100.0;
    _intervalPlan = null;
    _awaitingResumeAnchor = false;
    _notificationUpdateInProgress = false;
    _route.clear();
    _splits.clear();
    _hundredMeterLaps.clear();
    _paceSamples.clear();
  }

  bool _isPositionUsable(Position position) {
    final double accuracy = position.accuracy;

    if (!accuracy.isFinite || accuracy <= 0) return false;
    if (accuracy > maxAccuracyMeters) return false;
    if (!position.latitude.isFinite || !position.longitude.isFinite) {
      return false;
    }

    return true;
  }

  void _seedPosition(Position position) {
    final int activeElapsedMilliseconds =
        _stopwatch?.elapsedMilliseconds ?? 0;
    // The first fix is acquired before the 5-second countdown. Anchor it to
    // the real start moment, not the old acquisition timestamp, so the first
    // movement is not divided by the GPS wait + countdown duration.
    final DateTime timestamp = DateTime.now();

    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawAltitudeMeters = _altitudeOf(position);
    _lastRawTimestamp = timestamp;

    _filteredLatitude = position.latitude;
    _filteredLongitude = position.longitude;
    _filteredAccuracyMeters = position.accuracy;
    _gpsAccuracyMeters = position.accuracy;
    _lastAcceptedElapsedMilliseconds = activeElapsedMilliseconds;
    _acceptedPoints = 1;
    _paceSamples
      ..clear()
      ..add(PaceSample(timestamp: timestamp, distanceMeters: _distanceMeters));

    _route.add(
      RunPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: timestamp,
        accuracyMeters: position.accuracy,
        altitudeMeters: _altitudeOf(position),
        startsNewSegment: true,
      ),
    );
  }

  void _onPosition(Position position) {
    if (_disposed || _status != RunStatus.running) return;

    _gpsAccuracyMeters = position.accuracy;

    if (!_isPositionUsable(position)) {
      _rejectedPoints++;
      _notifyIfAlive();
      return;
    }

    final double? previousLatitude = _lastRawLatitude;
    final double? previousLongitude = _lastRawLongitude;
    final double? previousAltitudeMeters = _lastRawAltitudeMeters;
    final DateTime? previousTimestamp = _lastRawTimestamp;

    if (_awaitingResumeAnchor) {
      _seedResumeAnchor(position);
      _notifyIfAlive();
      return;
    }

    if (previousTimestamp == null ||
        previousLatitude == null ||
        previousLongitude == null) {
      _seedResumeAnchor(position);
      _notifyIfAlive();
      return;
    }

    final int elapsedBeforeUpdate = _lastAcceptedElapsedMilliseconds;
    final int elapsedAfterUpdate =
        _stopwatch?.elapsedMilliseconds ?? elapsedBeforeUpdate;
    final int activeElapsedDelta = elapsedAfterUpdate - elapsedBeforeUpdate;

    // GPS timestamp normally provides the best interval, including when the
    // Android location provider delivers a delayed batch. If the timestamp is
    // duplicated or moves backwards, repair it from the monotonic Stopwatch.
    DateTime trackingTimestamp = position.timestamp;
    if (!trackingTimestamp.isAfter(previousTimestamp)) {
      trackingTimestamp = previousTimestamp.add(
        Duration(milliseconds: activeElapsedDelta > 0 ? activeElapsedDelta : 1),
      );
    }

    final double rawDistanceMeters = distanceBetweenMeters(
      latitude1: previousLatitude,
      longitude1: previousLongitude,
      latitude2: position.latitude,
      longitude2: position.longitude,
    );

    final double dtSeconds =
        trackingTimestamp.difference(previousTimestamp).inMilliseconds / 1000.0;

    if (dtSeconds <= 0 || !dtSeconds.isFinite) {
      _rejectedPoints++;
      _reanchorAfterRejectedJump(
        position,
        timestamp: trackingTimestamp,
        elapsedMilliseconds: elapsedAfterUpdate,
      );
      _notifyIfAlive();
      return;
    }

    final double speedMps = rawDistanceMeters / dtSeconds;
    final double speedKmh = speedMps * 3.6;

    if (!speedKmh.isFinite || speedKmh > maxSpeedKmh) {
      // Kode lama membuang lonjakan tanpa memperbarui titik acuan. Akibatnya,
      // semua titik sesudahnya dibandingkan dengan koordinat lama dan GPS
      // dapat terlihat macet sepanjang sesi. Re-anchor tanpa menambahkan jarak
      // dan mulai segmen peta baru agar satu lonjakan tidak merusak sesi.
      _rejectedPoints++;
      _reanchorAfterRejectedJump(
        position,
        timestamp: trackingTimestamp,
        elapsedMilliseconds: elapsedAfterUpdate,
      );
      _notifyIfAlive();
      return;
    }

    final double distanceBeforeUpdate = _distanceMeters;
    final double movementThreshold = _movementThresholdFor(position);
    _acceptPosition(
      position,
      timestamp: trackingTimestamp,
      elapsedMilliseconds: elapsedAfterUpdate,
    );

    // Titik GPS yang valid selalu masuk ke rute yang telah dihaluskan. Jarak
    // hanya ditambah bila perpindahannya lebih besar daripada ambang noise.
    // Ambang 2,5 m sebelumnya membuang hampir semua langkah pelan ketika GPS
    // mengirim satu titik per detik.
    if (rawDistanceMeters >= movementThreshold) {
      _distanceMeters += rawDistanceMeters;

      final Duration segmentDuration =
          trackingTimestamp.difference(previousTimestamp);
      if (speedMps >= movingSpeedMps) {
        _movingTime += segmentDuration;
      }

      _recordHundredMeterLaps(
        distanceBeforeMeters: distanceBeforeUpdate,
        segmentDistanceMeters: rawDistanceMeters,
        startLatitude: previousLatitude,
        startLongitude: previousLongitude,
        endLatitude: position.latitude,
        endLongitude: position.longitude,
        startAltitudeMeters: previousAltitudeMeters,
        endAltitudeMeters: _altitudeOf(position),
        elapsedBeforeMilliseconds: elapsedBeforeUpdate,
        elapsedAfterMilliseconds: elapsedAfterUpdate,
      );
      _createCompletedSplits();
    }

    _appendRoutePoint(position, timestamp: trackingTimestamp);
    _recordPaceSample(trackingTimestamp);
    _notifyIfAlive();
  }

  double _movementThresholdFor(Position position) {
    final double previousAccuracy =
        _filteredAccuracyMeters ?? position.accuracy;
    final double bestAccuracy = math
        .min(position.accuracy, previousAccuracy)
        .toDouble();
    final double adaptiveThreshold = bestAccuracy * 0.15;
    return adaptiveThreshold
        .clamp(minMovementMeters, maxMovementThresholdMeters)
        .toDouble();
  }

  void _seedResumeAnchor(Position position) {
    final int activeElapsedMilliseconds =
        _stopwatch?.elapsedMilliseconds ?? _lastAcceptedElapsedMilliseconds;
    final DateTime timestamp = position.timestamp;

    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawAltitudeMeters = _altitudeOf(position);
    _lastRawTimestamp = timestamp;
    _filteredLatitude = position.latitude;
    _filteredLongitude = position.longitude;
    _filteredAccuracyMeters = position.accuracy;
    _gpsAccuracyMeters = position.accuracy;
    _lastAcceptedElapsedMilliseconds = activeElapsedMilliseconds;
    _acceptedPoints++;
    _awaitingResumeAnchor = false;
    _paceSamples
      ..clear()
      ..add(PaceSample(timestamp: timestamp, distanceMeters: _distanceMeters));
    _currentPaceSecondsPerKm = null;

    _route.add(
      RunPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: timestamp,
        accuracyMeters: position.accuracy,
        altitudeMeters: _altitudeOf(position),
        startsNewSegment: true,
      ),
    );
  }

  void _reanchorAfterRejectedJump(
    Position position, {
    required DateTime timestamp,
    required int elapsedMilliseconds,
  }) {
    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawAltitudeMeters = _altitudeOf(position);
    _lastRawTimestamp = timestamp;
    _lastAcceptedElapsedMilliseconds = elapsedMilliseconds;
    _filteredLatitude = position.latitude;
    _filteredLongitude = position.longitude;
    _filteredAccuracyMeters = position.accuracy;
    _gpsAccuracyMeters = position.accuracy;
    _currentPaceSecondsPerKm = null;
    _paceSamples
      ..clear()
      ..add(PaceSample(timestamp: timestamp, distanceMeters: _distanceMeters));

    _route.add(
      RunPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        timestamp: timestamp,
        accuracyMeters: position.accuracy,
        altitudeMeters: _altitudeOf(position),
        startsNewSegment: true,
      ),
    );
  }

  void _acceptPosition(
    Position position, {
    required DateTime timestamp,
    required int elapsedMilliseconds,
  }) {
    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawAltitudeMeters = _altitudeOf(position);
    _lastRawTimestamp = timestamp;
    _gpsAccuracyMeters = position.accuracy;
    _lastAcceptedElapsedMilliseconds = elapsedMilliseconds;
    _acceptedPoints++;
  }

  void _appendRoutePoint(
    Position position, {
    required DateTime timestamp,
  }) {
    final double filteredLatitude = _smoothCoordinate(
      previousValue: _filteredLatitude,
      measurement: position.latitude,
      previousAccuracy: _filteredAccuracyMeters,
      measurementAccuracy: position.accuracy,
    );

    final double filteredLongitude = _smoothCoordinate(
      previousValue: _filteredLongitude,
      measurement: position.longitude,
      previousAccuracy: _filteredAccuracyMeters,
      measurementAccuracy: position.accuracy,
    );

    _filteredLatitude = filteredLatitude;
    _filteredLongitude = filteredLongitude;
    _filteredAccuracyMeters = position.accuracy;

    _route.add(
      RunPoint(
        latitude: filteredLatitude,
        longitude: filteredLongitude,
        timestamp: timestamp,
        accuracyMeters: position.accuracy,
        altitudeMeters: _altitudeOf(position),
      ),
    );
  }

  void _recordHundredMeterLaps({
    required double distanceBeforeMeters,
    required double segmentDistanceMeters,
    required double? startLatitude,
    required double? startLongitude,
    required double endLatitude,
    required double endLongitude,
    required double? startAltitudeMeters,
    required double? endAltitudeMeters,
    required int elapsedBeforeMilliseconds,
    required int elapsedAfterMilliseconds,
  }) {
    if (startLatitude == null || startLongitude == null ||
        segmentDistanceMeters <= 0 ||
        elapsedAfterMilliseconds < elapsedBeforeMilliseconds) {
      return;
    }

    final int elapsedDelta =
        elapsedAfterMilliseconds - elapsedBeforeMilliseconds;
    while (_nextHundredMeterMark <=
        distanceBeforeMeters + segmentDistanceMeters) {
      final double fraction =
          ((_nextHundredMeterMark - distanceBeforeMeters) /
                  segmentDistanceMeters)
              .clamp(0.0, 1.0);
      final int crossingElapsedMilliseconds = elapsedBeforeMilliseconds +
          (elapsedDelta * fraction).round();
      final int lapDurationMilliseconds =
          crossingElapsedMilliseconds -
              _lastHundredMeterCrossingElapsedMilliseconds;

      if (lapDurationMilliseconds > 0) {
        _hundredMeterLaps.add(
          RunLap100m(
            distanceMeters: _nextHundredMeterMark,
            durationMilliseconds: lapDurationMilliseconds,
            latitude: startLatitude +
                (endLatitude - startLatitude) * fraction,
            longitude: startLongitude +
                (endLongitude - startLongitude) * fraction,
            altitudeMeters: startAltitudeMeters != null &&
                    endAltitudeMeters != null
                ? startAltitudeMeters +
                    (endAltitudeMeters - startAltitudeMeters) * fraction
                : null,
          ),
        );
      }

      _lastHundredMeterCrossingElapsedMilliseconds =
          crossingElapsedMilliseconds;
      _nextHundredMeterMark += 100.0;
    }
  }

  void _recordPaceSample(DateTime timestamp) {
    _paceSamples.add(
      PaceSample(
        timestamp: timestamp,
        distanceMeters: _distanceMeters,
      ),
    );

    final DateTime cutoff = timestamp.subtract(
      const Duration(seconds: paceWindowSeconds),
    );

    // Pertahankan satu sampel tepat sebelum batas jendela untuk menghitung
    // jarak/waktu secara stabil.
    while (_paceSamples.length > 2 &&
        _paceSamples[1].timestamp.isBefore(cutoff)) {
      _paceSamples.removeAt(0);
    }

    _currentPaceSecondsPerKm = null;
    if (_paceSamples.length < 2) return;

    int anchorIndex = 0;
    for (int index = 0; index < _paceSamples.length - 1; index++) {
      if (!_paceSamples[index].timestamp.isAfter(cutoff)) {
        anchorIndex = index;
      } else {
        break;
      }
    }

    final PaceSample anchor = _paceSamples[anchorIndex];
    final PaceSample latest = _paceSamples.last;
    final int elapsedMilliseconds =
        latest.timestamp.difference(anchor.timestamp).inMilliseconds;
    final double distanceMeters =
        latest.distanceMeters - anchor.distanceMeters;

    if (elapsedMilliseconds < minimumPaceWindowSeconds * 1000 ||
        distanceMeters < minimumPaceDistanceMeters) {
      return;
    }

    final double elapsedSeconds = elapsedMilliseconds / 1000.0;
    final double speedMps = distanceMeters / elapsedSeconds;
    if (!speedMps.isFinite ||
        speedMps < minPaceSpeedMps ||
        speedMps > maxPaceSpeedMps) {
      return;
    }

    _currentPaceSecondsPerKm = 1000.0 / speedMps;
  }

  double? _altitudeOf(Position position) {
    final double altitude = position.altitude;
    return altitude.isFinite ? altitude : null;
  }

  double _smoothCoordinate({
    required double? previousValue,
    required double measurement,
    required double? previousAccuracy,
    required double measurementAccuracy,
  }) {
    if (previousValue == null || previousAccuracy == null) {
      return measurement;
    }

    final double previous =
        previousAccuracy.clamp(1.0, maxAccuracyMeters);
    final double current =
        measurementAccuracy.clamp(1.0, maxAccuracyMeters);

    final double measurementWeight =
        (previous / (previous + current)).clamp(0.35, 0.85);

    return previousValue +
        (measurement - previousValue) * measurementWeight;
  }

  void _createCompletedSplits() {
    final int completedKilometers =
        (_distanceMeters / 1000.0).floor();

    while (_splits.length < completedKilometers) {
      final int kilometer = _splits.length + 1;
      final Duration splitDuration =
          _movingTime - _lastSplitMovingTime;
      final double splitDistance =
          _distanceMeters - _lastSplitDistanceMeters;

      if (splitDistance <= 0 || splitDuration.inMilliseconds <= 0) {
        return;
      }

      final double pace =
          splitDuration.inMilliseconds / 1000.0 /
              (splitDistance / 1000.0);

      _splits.add(
        RunSplit(
          kilometer: kilometer,
          durationSeconds: splitDuration.inSeconds,
          paceSecondsPerKm: pace.round(),
          distanceMeters: splitDistance,
        ),
      );

      _lastSplitDistanceMeters = _distanceMeters;
      _lastSplitMovingTime = _movingTime;
    }
  }

  RunSession _buildSession() {
    return RunSession(
      startedAt: _startedAt ?? DateTime.now(),
      finishedAt: _finishedAt,
      distanceMeters: _distanceMeters,
      elapsed: elapsed,
      movingTime: _movingTime,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm,
      currentPaceSecondsPerKm: _currentPaceSecondsPerKm,
      gpsAccuracyMeters: _gpsAccuracyMeters,
      acceptedPoints: _acceptedPoints,
      rejectedPoints: _rejectedPoints,
      route: List<RunPoint>.unmodifiable(_route),
      splits: List<RunSplit>.unmodifiable(_splits),
      hundredMeterLaps: List<RunLap100m>.unmodifiable(_hundredMeterLaps),
      intervalPlan: _intervalPlan,
      activityType: _activityType,
      environment: _environment,
    );
  }

  void _startNotificationUpdates() {
    _notificationTimer?.cancel();
    unawaited(_updateRunNotificationSafely());
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_updateRunNotificationSafely()),
    );
  }

  Future<void> _updateRunNotificationSafely() async {
    if (_status != RunStatus.running && _status != RunStatus.paused) return;
    if (_notificationUpdateInProgress) return;
    _notificationUpdateInProgress = true;

    final double? pace =
        _currentPaceSecondsPerKm ?? averagePaceSecondsPerKm;
    final double? speedKmh = pace != null && pace > 0 ? 3600.0 / pace : null;
    try {
      await RunningNotificationService.showRunStats(
        elapsed: elapsed,
        distanceMeters: _distanceMeters,
        speedKmh: speedKmh,
        paceSecondsPerKm: pace,
        paused: _status == RunStatus.paused,
        activityLabel: _intervalPlan == null ? _activityType.label : 'Lari interval',
      );
    } catch (_) {
      // Kegagalan notifikasi tidak boleh menghentikan perekaman GPS.
    } finally {
      _notificationUpdateInProgress = false;
    }
  }

  bool _isStaleStart(int generation) =>
      _disposed || generation != _startGeneration;

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  void _fail(String message) {
    if (_disposed) return;
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;
    _notificationTimer?.cancel();
    _notificationTimer = null;
    unawaited(RunningNotificationService.stop());
    _stopwatch?.stop();
    _status = RunStatus.error;
    _errorMessage = message;
    _notifyIfAlive();
  }

  void _onPositionError(Object error) {
    if (_disposed || _status != RunStatus.running) return;

    _errorMessage = 'Stream GPS bermasalah: $error';
    _rejectedPoints++;
    _notifyIfAlive();
  }

  void _cancelPositionSubscription() {
    final StreamSubscription<Position>? subscription =
        _positionSubscription;
    _positionSubscription = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }
}
