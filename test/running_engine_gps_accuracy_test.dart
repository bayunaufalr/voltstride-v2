import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:voltstride/features/running/services/running_engine.dart';

void main() {
  group('RunningEngine GPS distance filtering', () {
    test('counts plausible slow movement below the old 2.5 m threshold', () async {
      final DateTime base = DateTime.utc(2026, 10, 14, 12);
      final _FakeLocationSource source = _FakeLocationSource(
        _position(latitude: -7.8, longitude: 110.3, timestamp: base),
      );
      final RunningEngine engine = RunningEngine(locationSource: source);
      addTearDown(engine.dispose);
      addTearDown(source.close);

      await engine.start();
      for (int index = 1; index <= 4; index++) {
        source.emit(
          _position(
            latitude: -7.8,
            longitude: 110.3 + _longitudeDeltaForMeters(1.8 * index),
            timestamp: base.add(Duration(seconds: index)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(engine.distanceMeters, greaterThan(6.0));
      expect(engine.route.length, greaterThanOrEqualTo(5));
    });

    test('recovers distance after one implausible GPS jump', () async {
      final DateTime base = DateTime.utc(2026, 10, 14, 12);
      const double startLatitude = -7.8;
      const double startLongitude = 110.3;
      final double jumpLongitude =
          startLongitude + _longitudeDeltaForMeters(1200);
      final _FakeLocationSource source = _FakeLocationSource(
        _position(
          latitude: startLatitude,
          longitude: startLongitude,
          timestamp: base,
        ),
      );
      final RunningEngine engine = RunningEngine(locationSource: source);
      addTearDown(engine.dispose);
      addTearDown(source.close);

      await engine.start();
      source.emit(
        _position(
          latitude: startLatitude,
          longitude: jumpLongitude,
          timestamp: base.add(const Duration(seconds: 1)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      source.emit(
        _position(
          latitude: startLatitude,
          longitude: jumpLongitude + _longitudeDeltaForMeters(1.8),
          timestamp: base.add(const Duration(seconds: 2)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(engine.distanceMeters, greaterThan(1.4));
      expect(engine.distanceMeters, lessThan(2.2));
      expect(engine.rejectedPoints, greaterThanOrEqualTo(1));
    });
  });
}

class _FakeLocationSource implements RunningLocationSource {
  _FakeLocationSource(this.initialPosition);

  final Position initialPosition;
  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<Position?> getCurrentPosition() async => initialPosition;

  @override
  Stream<Position> getPositionStream() => _controller.stream;

  void emit(Position position) => _controller.add(position);

  Future<void> close() => _controller.close();
}

Position _position({
  required double latitude,
  required double longitude,
  required DateTime timestamp,
}) {
  return Position(
    latitude: latitude,
    longitude: longitude,
    timestamp: timestamp,
    accuracy: 3,
    altitude: 100,
    altitudeAccuracy: 3,
    heading: 0,
    headingAccuracy: 1,
    speed: 1.8,
    speedAccuracy: 0.2,
    isMocked: true,
  );
}

double _longitudeDeltaForMeters(double meters) {
  const double latitudeRadians = -7.8 * math.pi / 180;
  final double metersPerLongitudeDegree =
      111320 * math.cos(latitudeRadians);
  return meters / metersPerLongitudeDegree;
}
