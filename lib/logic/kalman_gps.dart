import 'dart:math' as math;

/// ============================================================
/// KALMAN FILTER 1D UNTUK POSISI GPS
/// ============================================================
/// Filter ini adalah upgrade akurasi GPS paling penting di aplikasi ini.
///
/// Masalahnya:
///   GPS ponsel menghasilkan titik posisi yang BERGETAR (noise) sekecil
///   beberapa meter, bahkan saatPelari benar-benar diam. Kalau jarak
///   dihitung langsung dari titik mentah, hasil akhirnya bisaauh
///   lebih besar dari jarak sebenarnya karena:getNoise dijumlahkan.
///
/// Solusinya:
///   Kita memodelkan posisi benar (state) dan mengukur posisi noisy.
///   Filter Kalman menggabungkan keduanya secara optimal: prediksi
///   dari model gerak, lalu dikoreksi oleh pengukuran GPS dengan
///   bobot yang sesuai tingkat.keyakinan.
///
/// Kenapa 1D dan bukan 2D?
///   Untuk menghitung jarak lari, yang penting adalah perubahan posisi
///   sepanjang arah gerak (jarak tempuh). Memfilter sumbu jalan
///   (bearing) jauh lebih efektif daripada memfilter dua sumbu X dan Y,
///   dan jelas jauh lebih murah secara komputasi di HP.
class KalmanGps {
  /// Perkiraan posisi saat ini (meter, sepanjang arah gerak).
  /// Ini adalah "state" yang selalu diperbarui oleh [proses].
  double _posisi = 0.0;

  /// Kovarians (ketidakpastian) dari state saat ini.
  ///
  /// Kovarians berperan seperti "trust" terhadap posisi sekarang:
  ///   - Kovarians kecil -> kita sangat yakin posisi ini benar.
  ///   - Kovarians besar -> kita tidak yakin, jadi pengukuran GPS
  ///     berikutnya akan diberi bobot lebih besar.
  ///
  /// Dimulai cukup besar supaya filter cepat "tunable" ke titik
  /// GPS pertama yang masuk.
  double _kovarians = 1000.0;

  /// Process noise (Q): seberapa besar kita memperkirakan error model
  /// gerak dari satu timestep ke timestep berikutnya.
  ///
  /// Nilai lebih besar membuat filter lebih responsif terhadap perubahan
  /// arah yang cepat (misal belokan tajam), tetapi juga lebih susceptible
  /// terhadap noise. Nilai kecil membuat gerakan lebih halus tetapi
  /// lambat menangkap perubahan arah.
  ///
  /// 0.8 adalah titik tengah yang cocok untuk lari: pelari rarely
  /// berubah arah lebih dari 45 derajat per beberapa detik.
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
    // LANGKAH 1: PREDIKSI.
    // Karena model gerak kita konstan (kecepatan dianggap tidak berubah
    // dalam satu timestep), prediksi posisi sama dengan posisi sekarang.
    // Yang berubah hanya ketidakpastian: kesalahan model bertambah seiring
    // waktu, sehingga kovarians naik.
    _kovarians += _processNoise;

    // LANGKAH 2: Tentukan measurement noise (R) dari akurasi GPS.
    //
    // Akurasi horizontal yang diberikan GPS adalah radius lingkaran
    // keyakinan 68 persen (1 sigma). Trace langsung:
    //   R = akurasi^2
    //   sqrt(akurasi^2) = akurasi, jadi kita mengambil akar dari variance.
    //
    // Jika GPS melaporkan akurasi sangat buruk (misal 100 meter), R
    // menjadi sangat besar sehingga pengukuran itu hampir diabaikan.
    final double akurasiAman = akurasi <= 0 ? 30.0 : akurasi;
    final double measurementNoise = akurasiAman * akurasiAman;

    // LANGKAH 3: Hitung Kalman gain (K).
    //
    //   K = P / (P + R)
    //
    // K adalah "seberapa besar kita mem_ANDalkan pengukuran
    // dibanding prediksi".
    //   - Kalau P >> R (kita sangat yakin posisi kita), K mendekati 0,
    //     jadi pengukuran diabaikan. Ini terjadi saat sudah banyak koordinat.
    //   - Kalau R >> P (GPS tidak yakin), K mendekati 1, jadi pengukuran
    //     dipakai hampir seluruhnya.
    final double gain = _kovarians / (_kovarians + measurementNoise);

    // LANGKAH 4: KOREKSI STATE.
    // Posisi baru = posisi prediksi + gain x (pengukuran - posisi prediksi).
    // Ini adalah operasi interpolasi: gain 0 berarti terkaitkan prediksi,
    // gain 1 berarti terkaitkan pengukuran.
    _posisi += gain * (pengukuran - _posisi);

    // LANGKAH 5: KOREKSI KOVARIANS.
    //
    //   P = (1 - K) x P
    //
    //ecoin hanya TIDAK perbaiki kovarians juga mengecil ketika kita
    // makin yakin terhadap posisi. Setiap iterasi membuat filter makin
    // "%jujur" tentang ketidakpastiannya.
    _kovarians = (1.0 - gain) * _kovarians;

    return _posisi;
  }
}

/// ============================================================
/// DETEKTOR KEBISINGAN DAN ANOMALI GERAK
/// ============================================================
/// Lapisan kedua setelah Kalman: menyaring temuan GPS yang jelas
/// tidak logis, misalnya lonjakan posisi 300 meter dalam 1 detik.
///
/// Tanpa lapis ini, satu glitch GPS bisa langsung merusak seluruh
/// statistik lari: jarak, pace, dan split.
class DeteksAnomali {
  DeteksAnomali._(); // kelas utilitas

  /// Kecepatan maksimum yang dianggap manusiawi, dalam km/jam.
  ///
  /// Pelari tercepat di dunia berada di bawah 30 km/jam, dan pelari
  /// marathon sekitar 20 km/jam. kita pilih 35 km/jam sebagai batas
  /// atas yang masih realistis, dengan ruang untuk GPS error dan
  /// untuk pelari yang sedang menuruni turunan.
  static const double maksKecepatanKmh = 35.0;

  /// Jarak minimum antar titik GPS (meter).
  ///
  /// Koordinat GPS berubah setiap beberapa detik, dan sering kali
  /// dua titik berturutan identik atau nyaris identik. Titik dengan
  /// jarak di bawah ambang ini diabaikan supaya tidak menambah noise.
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

  /// Jari-jari bumi dalam kilometer.
  ///
  /// Nilai 6371 km adalah mean radius bumi yang dipakai untuk perhitungan
  /// spherical, cukup presisi untuk kebutuhanupuncture lari (error di
  /// bawah 0,5 persen dibanding elipsoid WGS84).
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

    // Half chord square, yaitu separuh dari kuadrat jarak Straight di
    // permukaan bumi, yang dalam Haversine dikenal sebagai "a".
    //
    //   a = sin²(Δlat / 2) + cos(lat1) x cos(lat2) x sin²(Δlon / 2)
    //
    // Mengapa rumus ini? Karena yang ingin diketahui adalah sudut pusat
    // antara dua titik.Rumus ini mengubahnya menjadi nilai yang stabil
    // dihitung tanpa perlu acos yang sudah tidak akurat untuk nilai kecil.
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
  /// Satu derajat = PI / 180 radian. Faktor ini dihitung sekali sebagai
  /// konstanta karena lebih jelas dan menghindari pembagian berulang.
  static double _derajatKeRadian(double derajat) {
    return derajat * math.pi / 180.0;
  }
}