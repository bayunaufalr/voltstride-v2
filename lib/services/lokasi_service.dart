import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// ============================================================
/// LOKASI SERVICE
/// ============================================================
/// Lapisan paling bawah yang menyentuh paket `geolocator`.
///
/// Tanggung jawab file ini hanya satu: mengubah API platform menjadi
/// `Stream<Position>` yang sudah dikonfigurasi untuk akurasi tinggi.
/// Semua logika bisnis (filter, statistik) berada di file lain supaya
/// mudah diuji tanpa perangkat.
class LokasiService {
  LokasiService._();

  /// Ambang akurasi yang diminta ke sistem, dalam meter.
  static const int ambangAkurasiDiminta = 10;

  /// Filter jarak minimum antar titik, dalam meter.
  ///
  /// Nilai 0 dipakai agar titik tidak dibuang oleh plugin hanya karena
  /// perpindahannya kecil. Penyaringan noise dilakukan di lapisan
  /// `PelacakLari` menggunakan Kalman filter.
  static const int filterJarakMinimum = 0;

  /// Meminta izin lokasi kepada pengguna.
  ///
  /// Mengembalikan true jika izin foreground sudah diberikan.
  static Future<bool> mintaIzin() async {
    LocationPermission status = await Geolocator.checkPermission();

    if (status == LocationPermission.denied) {
      status = await Geolocator.requestPermission();
    }

    return status == LocationPermission.whileInUse ||
        status == LocationPermission.always;
  }

  /// Memastikan layanan lokasi perangkat dalam keadaan aktif.
  static Future<bool> cekLayananAktif() async {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Membuat pengaturan lokasi sesuai platform.
  ///
  /// Geolocator versi modern menggunakan `AndroidSettings` secara
  /// langsung pada Android dan `AppleSettings` secara langsung pada
  /// iOS/macOS. `LocationSettings` dasar dipakai pada platform lain.
  static LocationSettings _pengaturanLokasi() {
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
        );

      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return AppleSettings(
          accuracy: LocationAccuracy.best,
          activityType: ActivityType.fitness,
          showBackgroundLocationIndicator: false,
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

  /// Membuat stream posisi GPS dengan pengaturan akurasi tinggi.
  static Stream<Position> pasangStream() {
    final LocationSettings pengaturan = _pengaturanLokasi();

    return Geolocator.getPositionStream(
      locationSettings: pengaturan,
    );
  }

  /// Mengambil satu titik posisi sekali pakai.
  ///
  /// Dipakai untuk mengambil titik awal (seed) atau koordinat pengguna
  /// sebelum subscription stream dimulai, supaya Kalman filter punya
  /// referensi posisi awal.
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
