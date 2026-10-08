import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../services/lokasi_service.dart';
import '../models/run_session.dart';

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
  static const double minMovementMeters = 2.5;
  static const double movingSpeedMps = 1.0;
  static const double minPaceSpeedMps = 0.8;
  static const int updateIntervalMilliseconds = 250;

  RunningEngine({RunningLocationSource? locationSource})
      : _locationSource =
            locationSource ?? const GeolocatorRunningLocationSource();

  final RunningLocationSource _locationSource;

  StreamSubscription<Position>? _positionSubscription;
  Timer? _uiTimer;
  Stopwatch? _stopwatch;

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
  DateTime? _lastRawTimestamp;

  double? _filteredLatitude;
  double? _filteredLongitude;
  double? _filteredAccuracyMeters;

  double _lastSplitDistanceMeters = 0.0;

  /// Setelah resume, titik GPS pertama hanya menjadi anchor baru.
  /// Titik tersebut tidak menghasilkan jarak terhadap posisi sebelum pause.
  bool _awaitingResumeAnchor = false;

  final List<RunPoint> _route = <RunPoint>[];
  final List<RunSplit> _splits = <RunSplit>[];

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
    if (_movingTime.inMilliseconds <= 0 || _distanceMeters <= 0) {
      return null;
    }

    return _movingTime.inMilliseconds / 1000.0 /
        (_distanceMeters / 1000.0);
  }

  double? get gpsAccuracyMeters => _gpsAccuracyMeters;
  int get acceptedPoints => _acceptedPoints;
  int get rejectedPoints => _rejectedPoints;
  int get splitCount => _splits.length;

  List<RunPoint> get route => List<RunPoint>.unmodifiable(_route);
  List<RunSplit> get splits => List<RunSplit>.unmodifiable(_splits);

  double get gpsCleanRatio {
    final int total = _acceptedPoints + _rejectedPoints;
    if (total == 0) return 0.0;
    return _acceptedPoints / total;
  }

  /// Memulai sesi lari baru.
  Future<void> start() async {
    if (isActive) return;

    _resetSessionData();
    _errorMessage = null;
    _status = RunStatus.acquiringGps;
    notifyListeners();

    final bool serviceEnabled =
        await _locationSource.isServiceEnabled();
    if (!serviceEnabled) {
      _fail('Layanan lokasi perangkat sedang mati.');
      return;
    }

    final bool permissionGranted =
        await _locationSource.requestPermission();
    if (!permissionGranted) {
      _fail('Izin lokasi belum diberikan.');
      return;
    }

    final Position? firstPosition =
        await _locationSource.getCurrentPosition();

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

    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _seedPosition(firstPosition);
    _status = RunStatus.running;

    _positionSubscription = _locationSource.getPositionStream().listen(
      _onPosition,
      onError: _onPositionError,
      cancelOnError: false,
    );

    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(
      const Duration(milliseconds: updateIntervalMilliseconds),
      (_) => notifyListeners(),
    );

    notifyListeners();
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
    notifyListeners();
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
    notifyListeners();
  }

  /// Mengakhiri sesi dan menghasilkan snapshot final.
  RunSession? finish() {
    if (!isActive) {
      return _lastFinishedSession;
    }

    _finishedAt = DateTime.now();
    _stopwatch?.stop();
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;

    _status = RunStatus.finished;
    _currentPaceSecondsPerKm = null;

    final RunSession session = _buildSession();
    _lastFinishedSession = session;
    notifyListeners();
    return session;
  }

  /// Menghapus hasil sesi dan kembali ke keadaan siap.
  void reset() {
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;
    _stopwatch?.stop();

    _status = RunStatus.idle;
    _errorMessage = null;
    _lastFinishedSession = null;
    _resetSessionData();
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPositionSubscription();
    _uiTimer?.cancel();
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
    _lastRawTimestamp = null;
    _filteredLatitude = null;
    _filteredLongitude = null;
    _filteredAccuracyMeters = null;
    _lastSplitDistanceMeters = 0.0;
    _awaitingResumeAnchor = false;
    _route.clear();
    _splits.clear();
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
    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawTimestamp = position.timestamp;

    _filteredLatitude = position.latitude;
    _filteredLongitude = position.longitude;
    _filteredAccuracyMeters = position.accuracy;
    _gpsAccuracyMeters = position.accuracy;
    _acceptedPoints = 1;

    _route.add(_toRunPoint(position));
  }

  void _onPosition(Position position) {
    if (_status != RunStatus.running) return;

    _gpsAccuracyMeters = position.accuracy;

    if (!_isPositionUsable(position)) {
      _rejectedPoints++;
      notifyListeners();
      return;
    }

    final DateTime? previousTimestamp = _lastRawTimestamp;
    final double? previousLatitude = _lastRawLatitude;
    final double? previousLongitude = _lastRawLongitude;

    if (previousTimestamp != null &&
        !position.timestamp.isAfter(previousTimestamp)) {
      _rejectedPoints++;
      notifyListeners();
      return;
    }

    if (_awaitingResumeAnchor) {
      _seedResumeAnchor(position);
      notifyListeners();
      return;
    }

    if (previousTimestamp == null ||
        previousLatitude == null ||
        previousLongitude == null) {
      _seedResumeAnchor(position);
      notifyListeners();
      return;
    }

    final double rawDistanceMeters = distanceBetweenMeters(
      latitude1: previousLatitude,
      longitude1: previousLongitude,
      latitude2: position.latitude,
      longitude2: position.longitude,
    );

    final double dtSeconds =
        position.timestamp.difference(previousTimestamp).inMilliseconds /
            1000.0;

    if (dtSeconds <= 0) {
      _rejectedPoints++;
      notifyListeners();
      return;
    }

    final double speedMps = rawDistanceMeters / dtSeconds;
    final double speedKmh = speedMps * 3.6;

    if (!speedKmh.isFinite || speedKmh > maxSpeedKmh) {
      _rejectedPoints++;
      notifyListeners();
      return;
    }

    _acceptPosition(position);

    if (rawDistanceMeters >= minMovementMeters) {
      _distanceMeters += rawDistanceMeters;

      final Duration segmentDuration =
          position.timestamp.difference(previousTimestamp);

      if (speedMps >= movingSpeedMps) {
        _movingTime += segmentDuration;
      }

      if (speedMps >= minPaceSpeedMps) {
        _currentPaceSecondsPerKm = 1000.0 / speedMps;
      } else {
        _currentPaceSecondsPerKm = null;
      }

      _appendRoutePoint(position);
      _createCompletedSplits();
    } else {
      _currentPaceSecondsPerKm = null;
    }

    notifyListeners();
  }

  void _seedResumeAnchor(Position position) {
    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawTimestamp = position.timestamp;
    _filteredLatitude = position.latitude;
    _filteredLongitude = position.longitude;
    _filteredAccuracyMeters = position.accuracy;
    _gpsAccuracyMeters = position.accuracy;
    _acceptedPoints++;
    _awaitingResumeAnchor = false;

    _route.add(_toRunPoint(position));
  }

  void _acceptPosition(Position position) {
    _lastRawLatitude = position.latitude;
    _lastRawLongitude = position.longitude;
    _lastRawTimestamp = position.timestamp;
    _gpsAccuracyMeters = position.accuracy;
    _acceptedPoints++;
  }

  void _appendRoutePoint(Position position) {
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
        timestamp: position.timestamp,
        accuracyMeters: position.accuracy,
      ),
    );
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

  RunPoint _toRunPoint(Position position) {
    return RunPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      accuracyMeters: position.accuracy,
    );
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
    );
  }

  void _fail(String message) {
    _cancelPositionSubscription();
    _uiTimer?.cancel();
    _uiTimer = null;
    _stopwatch?.stop();
    _status = RunStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  void _onPositionError(Object error) {
    if (_status != RunStatus.running) return;

    _errorMessage = 'Stream GPS bermasalah: $error';
    _rejectedPoints++;
    notifyListeners();
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
