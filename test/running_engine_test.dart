import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:voltstride/features/running/models/run_session.dart';
import 'package:voltstride/features/running/services/running_engine.dart';

class FakeRunningLocationSource implements RunningLocationSource {
  FakeRunningLocationSource({required Position firstPosition})
      : _firstPosition = firstPosition;

  final Position _firstPosition;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  bool serviceEnabled = true;
  bool permissionGranted = true;
  bool disposed = false;

  @override
  Future<bool> isServiceEnabled() async => serviceEnabled;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<Position?> getCurrentPosition() async => _firstPosition;

  @override
  Stream<Position> getPositionStream() => _controller.stream;

  void emit(Position position) {
    _controller.add(position);
  }

  Future<void> close() async {
    if (disposed) return;
    disposed = true;
    await _controller.close();
  }
}

Position makePosition({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
  double accuracy = 5,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
    isMocked: false,
  );
}

void main() {
  group('RunningEngine state machine', () {
    late FakeRunningLocationSource source;
    late RunningEngine engine;

    final DateTime startTime = DateTime(2026, 10, 9, 6);

    setUp(() {
      source = FakeRunningLocationSource(
        firstPosition: makePosition(
          latitude: 0,
          longitude: 0,
          timestamp: startTime,
        ),
      );
      engine = RunningEngine(locationSource: source);
    });

    tearDown(() async {
      engine.dispose();
      await source.close();
    });

    test('start berpindah dari acquiring GPS ke running', () async {
      await engine.start();

      expect(engine.status, RunStatus.running);
      expect(engine.acceptedPoints, 1);
      expect(engine.distanceMeters, 0);
    });

    test('pause menghentikan akumulasi jarak dari stream GPS', () async {
      await engine.start();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.008983,
          timestamp: startTime.add(const Duration(minutes: 5)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final double distanceBeforePause = engine.distanceMeters;
      expect(distanceBeforePause, closeTo(1000, 3));

      engine.pause();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.017966,
          timestamp: startTime.add(const Duration(minutes: 10)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.status, RunStatus.paused);
      expect(engine.distanceMeters, closeTo(distanceBeforePause, 0.001));
    });

    test('resume memakai posisi pertama sebagai anchor baru', () async {
      await engine.start();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.008983,
          timestamp: startTime.add(const Duration(minutes: 5)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      engine.pause();
      engine.resume();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.017966,
          timestamp: startTime.add(const Duration(minutes: 10)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.status, RunStatus.running);
      expect(engine.distanceMeters, closeTo(1000, 3));

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.026949,
          timestamp: startTime.add(const Duration(minutes: 15)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.distanceMeters, closeTo(2000, 4));
      expect(engine.movingTime, const Duration(minutes: 10));
    });

    test('finish menghasilkan RunSession final', () async {
      await engine.start();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.008983,
          timestamp: startTime.add(const Duration(minutes: 5)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final RunSession? session = engine.finish();

      expect(engine.status, RunStatus.finished);
      expect(session, isNotNull);
      expect(session!.distanceMeters, closeTo(1000, 3));
      expect(session.finishedAt, isNotNull);
    });

    test('perpindahan yang terlalu cepat ditolak', () async {
      await engine.start();

      source.emit(
        makePosition(
          latitude: 0,
          longitude: 0.0044915,
          timestamp: startTime.add(const Duration(seconds: 10)),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(engine.distanceMeters, 0);
      expect(engine.rejectedPoints, 1);
      expect(engine.acceptedPoints, 1);
    });

    test('pace tidak muncul dari jarak kecil dalam waktu panjang', () async {
      await engine.start();

      for (int index = 1; index <= 6; index++) {
        source.emit(
          makePosition(
            latitude: 0,
            longitude: index * 0.00008983,
            timestamp: startTime.add(Duration(seconds: index * 30)),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      expect(engine.distanceMeters, closeTo(60, 3));
      expect(engine.currentPaceSecondsPerKm, isNull);
      expect(engine.averagePaceSecondsPerKm, isNull);
    });

    test('pace stabil dihitung dari jendela beberapa detik', () async {
      await engine.start();

      for (int index = 1; index <= 12; index++) {
        source.emit(
          makePosition(
            latitude: 0,
            longitude: index * 0.000044915,
            timestamp: startTime.add(Duration(seconds: index)),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      expect(engine.currentPaceSecondsPerKm, isNotNull);
      expect(engine.currentPaceSecondsPerKm!, closeTo(200, 3));
    });
  });

  test('RunSession dapat disimpan dan dipulihkan dari representasi SQLite', () {
    runSessionStorageSerializationTest();
  });
}


void runSessionStorageSerializationTest() {
  // Kept as a top-level helper to make the persistence contract explicit.
  final RunSession session = RunSession(
    startedAt: DateTime.utc(2026, 10, 9, 6),
    finishedAt: DateTime.utc(2026, 10, 9, 6, 30),
    distanceMeters: 5820,
    elapsed: const Duration(minutes: 30, seconds: 28),
    movingTime: const Duration(minutes: 29, seconds: 51),
    averagePaceSecondsPerKm: 314,
    currentPaceSecondsPerKm: null,
    gpsAccuracyMeters: 8,
    acceptedPoints: 187,
    rejectedPoints: 6,
    route: <RunPoint>[
      RunPoint(
        latitude: -7.797068,
        longitude: 110.370529,
        timestamp: DateTime.utc(2026, 10, 9, 6),
        accuracyMeters: 8,
      ),
    ],
    splits: const <RunSplit>[
      RunSplit(
        kilometer: 1,
        durationSeconds: 314,
        paceSecondsPerKm: 314,
        distanceMeters: 1000,
      ),
    ],
  );

  final RunSession restored = RunSession.fromStorageMap(session.toStorageMap());
  expect(restored.distanceMeters, closeTo(5820, 0.001));
  expect(restored.elapsed, const Duration(minutes: 30, seconds: 28));
  expect(restored.route, hasLength(1));
  expect(restored.splits.single.paceText, '5:14/km');
}
