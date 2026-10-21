import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

/// Perangkat BLE yang menyiarkan layanan Heart Rate standar.
class HeartRateDevice {
  const HeartRateDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

/// Membaca Heart Rate dari perangkat Bluetooth Low Energy berprofil standar.
/// Jam tertentu harus mengaktifkan fitur siaran HR sebelum bisa ditemukan.
class HeartRateService {
  HeartRateService._();

  static final HeartRateService instance = HeartRateService._();

  static const MethodChannel _methods =
      MethodChannel('voltstride/heart_rate');
  static const EventChannel _events =
      EventChannel('voltstride/heart_rate_events');

  final StreamController<int> _bpmController =
      StreamController<int>.broadcast();
  final ValueNotifier<int?> currentBpm = ValueNotifier<int?>(null);
  final ValueNotifier<String?> connectedDeviceName =
      ValueNotifier<String?>(null);

  StreamSubscription<dynamic>? _measurementSubscription;
  String? _connectedDeviceId;

  Stream<int> get heartRateStream => _bpmController.stream;
  bool get isConnected => _connectedDeviceId != null;

  Future<List<HeartRateDevice>> scanForDevices({
    Duration duration = const Duration(seconds: 8),
  }) async {
    await _requestPermissions();
    final List<dynamic> raw =
        await _methods.invokeMethod<List<dynamic>>('scan', <String, Object?>{
              'durationSeconds': duration.inSeconds.clamp(3, 20).toInt(),
            }) ??
            <dynamic>[];
    final List<HeartRateDevice> devices = raw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> value) => HeartRateDevice(
              id: value['id'] as String,
              name: value['name'] as String? ?? 'Heart-rate sensor',
              rssi: (value['rssi'] as num?)?.toInt() ?? -100,
            ))
        .toList(growable: true);
    devices.sort((HeartRateDevice a, HeartRateDevice b) {
      final int nameOrder = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return nameOrder != 0 ? nameOrder : b.rssi.compareTo(a.rssi);
    });
    return devices;
  }

  Future<void> connect(HeartRateDevice device) async {
    await _requestPermissions();
    await disconnect();

    // Dengarkan stream sebelum koneksi supaya pengukuran pertama tidak hilang.
    _measurementSubscription = _events.receiveBroadcastStream().listen(
      (dynamic value) {
        if (value is int) {
          _recordBpm(value);
        } else if (value is Map && value['type'] == 'disconnected') {
          _connectedDeviceId = null;
          connectedDeviceName.value = null;
          currentBpm.value = null;
        }
      },
      onError: (Object _) {
        // Kegagalan sensor tidak menghentikan perekaman GPS atau stopwatch.
      },
    );

    try {
      await _methods.invokeMethod<void>('connect', <String, Object?>{
        'deviceId': device.id,
      });
      _connectedDeviceId = device.id;
      connectedDeviceName.value = device.name;
    } catch (_) {
      await _measurementSubscription?.cancel();
      _measurementSubscription = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    await _measurementSubscription?.cancel();
    _measurementSubscription = null;
    try {
      await _methods.invokeMethod<void>('disconnect');
    } finally {
      _connectedDeviceId = null;
      connectedDeviceName.value = null;
      currentBpm.value = null;
    }
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError('BLE heart-rate sensors are currently supported on Android.');
    }

    final int sdkVersion =
        await _methods.invokeMethod<int>('androidSdkVersion') ?? 31;
    if (sdkVersion >= 31) {
      final Map<permissions.Permission, permissions.PermissionStatus> statuses =
          await <permissions.Permission>[
        permissions.Permission.bluetoothScan,
        permissions.Permission.bluetoothConnect,
      ].request();
      final bool scanAllowed =
          statuses[permissions.Permission.bluetoothScan]?.isGranted ?? false;
      final bool connectAllowed =
          statuses[permissions.Permission.bluetoothConnect]?.isGranted ?? false;
      if (scanAllowed && connectAllowed) return;

      if (statuses.values.any((permissions.PermissionStatus status) =>
          status.isPermanentlyDenied || status.isRestricted)) {
        await openAppSettings();
      }
      throw StateError(
        'Allow Bluetooth scan and connection permissions for VoltStride.',
      );
    }

    final permissions.PermissionStatus location =
        await permissions.Permission.locationWhenInUse.request();
    if (location.isGranted) return;
    if (location.isPermanentlyDenied || location.isRestricted) {
      await openAppSettings();
    }
    throw StateError('Allow location permission to scan Bluetooth devices.');
  }

  Future<void> openAppSettings() async {
    await permissions.openAppSettings();
  }

  void _recordBpm(int bpm) {
    if (bpm < 25 || bpm > 240) return;
    currentBpm.value = bpm;
    if (!_bpmController.isClosed) _bpmController.add(bpm);
  }
}
