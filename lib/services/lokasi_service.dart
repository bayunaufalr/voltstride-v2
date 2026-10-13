import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Sumber lokasi untuk pelacakan lari. Pada Android, stream GPS memakai
/// foreground service + notifikasi persisten agar tetap berjalan saat layar
/// terkunci atau aplikasi berpindah ke latar belakang.
class LokasiService {
  LokasiService._();

  static const int ambangAkurasiDiminta = 10;
  static const int filterJarakMinimum = 0;

  static Future<bool> mintaIzin() async {
    LocationPermission status = await Geolocator.checkPermission();
    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }
    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  static Future<bool> cekLayananAktif() =>
      Geolocator.isLocationServiceEnabled();

  static LocationSettings _pengaturanLokasi({bool untukPelacakanAktif = false}) {
    if (kIsWeb) {
      return const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: filterJarakMinimum,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: filterJarakMinimum,
          intervalDuration: const Duration(seconds: 1),
          forceLocationManager: false,
          foregroundNotificationConfig: untukPelacakanAktif
              ? const ForegroundNotificationConfig(
                  notificationTitle: 'VoltStride sedang merekam lari',
                  notificationText: 'GPS tetap aktif saat layar terkunci. Buka VoltStride untuk kontrol sesi.',
                  notificationChannelName: 'Pelacakan Lari',
                  enableWakeLock: true,
                  setOngoing: true,
                )
              : null,
        );
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.best,
          activityType: ActivityType.fitness,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
          distanceFilter: filterJarakMinimum,
        );
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: filterJarakMinimum,
        );
    }
  }

  static Stream<Position> pasangStream() {
    return Geolocator.getPositionStream(
      locationSettings: _pengaturanLokasi(untukPelacakanAktif: true),
    );
  }

  static Future<Position?> ambilSatuTitik() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _pengaturanLokasi(),
      );
    } on LocationServiceDisabledException {
      return null;
    } on PermissionDeniedException {
      return null;
    } on TimeoutException {
      return null;
    }
  }
}
