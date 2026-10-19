import 'dart:math' as math;

/// Filter Kalman satu dimensi untuk menghaluskan nilai posisi kumulatif.
///
/// Kelas ini digunakan oleh pelacak lama (`PelacakLari`). Mesin GPS yang
/// dipakai alur aplikasi utama sekarang berada di
/// `features/running/services/running_engine.dart` dan memakai penyaringan
/// yang berbeda. Keduanya sengaja dipertahankan supaya kode lama tetap dapat
/// dipelajari, tetapi jangan menganggap filter ini otomatis dipakai oleh
/// halaman rekam yang baru.
///
/// Filter menggabungkan perkiraan posisi sebelumnya dengan pengukuran baru.
/// Pengukuran GPS yang akurasinya buruk diberi bobot lebih kecil, sehingga
/// perubahan kecil akibat noise tidak langsung menggeser hasil terlalu jauh.
class KalmanGps {
  /// Perkiraan posisi saat ini (meter, sepanjang arah gerak).
  /// Ini adalah "state" yang selalu diperbarui oleh [proses].
  double _posisi = 0.0;

  /// Perkiraan ketidakpastian posisi saat ini.
  /// Nilai besar membuat filter lebih mudah mengikuti pengukuran baru;
  /// nilai kecil membuat hasil sebelumnya lebih dipertahankan.
  double _kovarians = 1000.0;

  /// Process noise (Q), yaitu ruang tambahan untuk perubahan posisi yang
  /// mungkin terjadi di antara dua pengukuran. Nilai ini merupakan parameter
  /// penyetelan; kecocokannya tetap perlu diuji dengan rekaman GPS nyata.
  static const double _processNoise = 0.8;

  /// Mengambil posisi terfilter saat ini (meter).
  double get posisi => _posisi;

  /// Mengambil kovarians saat ini, berguna untuk debug atau UI.
  double get kovarians => _kovarians;

  /// Reset filter ke kondisi awal.
  ///
  /// Dipanggil setiap kali lari dimulai atau pengguna menekan tombol
  /// pause lalu lanjut, supaya state lama tidak mencemari sesi baru.
  void reset() {
    _posisi = 0.0;
    _kovarians = 1000.0;
  }

  /// Menjalankan satu siklus filter Kalman.
  ///
  /// Parameter:
  ///   - [pengukuran]: posisi terukur dari GPS dalam meter.
  ///   - [akurasi]: radius akurasi horizontal GPS dalam meter.
  ///     Nilai ini datang langsung dari API GPS (Accuracy field).
  ///     Ini kunci Kalman filter: makin kecil radius, makin kita percaya.
  ///
  /// Mengembalikan posisi terfilter yang baru.
  double proses(double pengukuran, double akurasi) {
    // 1. Prediksi: pertahankan posisi terakhir dan naikkan perkiraan
    // ketidakpastian sebelum data GPS berikutnya diproses.
    _kovarians += _processNoise;

    // 2. Perlakukan kuadrat radius akurasi sebagai perkiraan noise
    // pengukuran. Semakin besar nilai akurasi dalam meter, semakin kecil
    // kepercayaan filter terhadap koordinat yang baru diterima.
    final double akurasiAman = akurasi <= 0 ? 30.0 : akurasi;
    final double measurementNoise = akurasiAman * akurasiAman;

    // 3. Kalman gain menentukan seberapa besar pengukuran baru mengubah
    // hasil. Gain besar berarti data baru lebih berpengaruh; gain kecil
    // berarti posisi sebelumnya lebih dipertahankan.
    final double gain = _kovarians / (_kovarians + measurementNoise);

    // 4. Perbarui posisi dengan bergerak sebagian atau seluruhnya menuju
    // pengukuran baru, sesuai besar Kalman gain.
    _posisi += gain * (pengukuran - _posisi);

    // 5. Perbarui ketidakpastian. Setelah pengukuran digunakan, perkiraan
    // ketidakpastian biasanya mengecil sebanding dengan gain.
    _kovarians = (1.0 - gain) * _kovarians;

    return _posisi;
  }
}

/// Pemeriksaan sederhana untuk menolak perpindahan GPS yang tidak masuk akal.
/// Bagian ini termasuk sistem pelacak lama; mesin lari utama memiliki
/// pemeriksaan posisi dan kecepatan sendiri di `RunningEngine`.
class DeteksAnomali {
  DeteksAnomali._(); // kelas utilitas

  /// Batas kecepatan untuk menandai lonjakan koordinat, dalam km/jam.
  /// Ini ambang penyaringan teknis, bukan klaim batas kemampuan seseorang.
  static const double maksKecepatanKmh = 35.0;

  /// Perpindahan di bawah ambang ini dianggap terlalu kecil untuk dihitung
  /// oleh algoritma pelacak lama. Uji perilakunya sebelum mengubah nilai ini.
  static const double jarakMinimumMeter = 1.5;

  /// Memeriksa apakah perpindahan antar titik masuk akal.
  ///
  /// Parameter:
  ///   - [jarakMeter]: jarak antara dua titik GPS berturutan.
  ///   - [dtDetik]: selisih waktu antar dua titik, dalam detik.
  ///
  /// Mengembalikan true bila perpindahan dianggap valid.
  static bool valid({
    required double jarakMeter,
    required double dtDetik,
  }) {
    // Syarat 1: selisih waktu harus positif. Jika tidak, data tidak bisa
    // dipakai untuk menghitung kecepatan.
    if (dtDetik <= 0) return false;

    // Syarat 2: jarak harus melewati ambang minimum. Titik yang terlalu
    // dekat hanya noise, bukan perpindahan nyata.
    if (jarakMeter < jarakMinimumMeter) return false;

    // Syarat 3: kecepatan tidak boleh melebihi batas manusiawi.
    final double kecepatanKmh = (jarakMeter / dtDetik) * 3.6;
    if (kecepatanKmh > maksKecepatanKmh) return false;

    return true;
  }
}

/// ============================================================
/// UTILITAS GEO
/// ============================================================
/// Perhitungan geodesi untuk mengubah koordinat GPS menjadi jarak.
class GeoUtil {
  GeoUtil._(); // kelas utilitas

  /// Jari-jari rata-rata bumi dalam kilometer untuk pendekatan Haversine.
  static const double jariJariBumiKm = 6371.0;

  /// Menghitung jarak (meter) antara dua koordinat GPS.
  ///
  /// Menggunakan rumus Haversine, yang jauh lebih stabil untuk jarak
  /// pendek dibandingkan rumus cosine yang tidak akurat untuk titik
  /// yang berdekatan (masalah floating point saat jarak mendekati nol).
  ///
  /// Parameter:
  ///   - [lat1], [lon1]: koordinat titik pertama.
  ///   - [lat2], [lon2]: koordinat titik kedua.
  ///
  /// Mengembalikan jarak dalam meter sebagai double.
  static double jarakAntarTitik({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    // Ubah derajat menjadi radian, karena fungsi trigonometri di Dart
    // (sin, cos, asin) selalu bekerja dalam radian.
    final double lat1Rad = _derajatKeRadian(lat1);
    final double lat2Rad = _derajatKeRadian(lat2);
    final double deltaLatRad = _derajatKeRadian(lat2 - lat1);
    final double deltaLonRad = _derajatKeRadian(lon2 - lon1);

    // Bagian ini menghitung komponen 'a' dalam rumus Haversine.
    //
    //   a = sin²(Δlat / 2) + cos(lat1) x cos(lat2) x sin²(Δlon / 2)
    //
    // Nilai ini digunakan untuk menghitung sudut pusat antara kedua titik.
    final double sinLat = math.sin(deltaLatRad / 2);
    final double sinLon = math.sin(deltaLonRad / 2);
    final double a = sinLat * sinLat +
        math.cos(lat1Rad) * math.cos(lat2Rad) * sinLon * sinLon;

    // Sudut pusat c = 2 x atan2(sqrt(a), sqrt(1 - a)).
    // Kita memakai atan2, bukan arcsin, karena atan2 lebih stabil di
    // kedua ujung rentang nilai a.
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    // Jarak = jari-jari bumi x sudut pusat (radian).
    // Dikalikan 1000 untuk mengubah kilometer menjadi meter.
    return jariJariBumiKm * c * 1000.0;
  }

  /// Mengubah derajat menjadi radian.
  ///
  /// Satu derajat sama dengan PI / 180 radian.
  static double _derajatKeRadian(double derajat) {
    return derajat * math.pi / 180.0;
  }
}