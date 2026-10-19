import 'kalman_gps.dart';

/// Pelacak GPS generasi lama yang mengubah koordinat menjadi statistik lari.
///
/// Kelas ini menghitung perpindahan dengan Haversine, memeriksa anomali,
/// lalu memakai filter Kalman untuk menghaluskan jarak kumulatif. Kode ini
/// dipakai oleh `TrackerPage` lama. Halaman rekam aktif saat ini memakai
/// `RunningEngine` di `features/running/services/running_engine.dart`, yang
/// mempunyai alur validasi dan penghitungan jarak tersendiri.
class PelacakLari {
  /// Filter Kalman untuk merapikan posisi sepanjang arah gerak.
  final KalmanGps _kalman = KalmanGps();

  /// Koordinat titik GPS terakhir yang diterima.
  /// Null berarti belum ada titik yang dipakai sebagai acuan.
  double? _latTerakhir;

  /// Longitude titik terakhir yang diterima.
  double? _lonTerakhir;

  /// Waktu (milidetik epoch) titik terakhir yang diterima.
  int? _waktuTerakhirMs;

  /// Kilometer yang sedang ditempuh, antara dua batas kilometer bulat.
  /// Dipakai untuk mendeteksi saat pelari melewati satu kilometer penuh.
  double _kmBerjalan = 0.0;

  /// Kilometer penuh yang sudah selesai pada sesi ini.
  int _kmSelesai = 0;

  /// Total jarak terakumulasi dalam kilometer.
  ///
  /// Ini angka yang ditampilkan ke pengguna, bukan penjumlahan mentah
  /// jarak GPS, melainkan penjumlahan jarak antar posisi terfilter.
  double _totalJarakKm = 0.0;

  /// Waktu tempuh kilometer terakhir yang selesai, dalam detik.
  int? _paceKmTerakhirDetik;

  /// Total waktu tempuh seluruh sesi dalam detik.
  ///
  /// Sumbernya adalah Stopwatch milik pemanggil, bukan penjumlahan
  /// delta waktu antar titik GPS. Alasannya, delta GPS bisa hilang saat
  /// sinyal terputus sementara sehingga total waktu jadi kurang dari
  /// waktu sebenarnya.
  double _totalWaktuDetik = 0.0;

  /// Panjang lintasan yang sudah tercatat, untuk menggambar route.
  final List<TitikLari> lintasan = <TitikLari>[];

  /// Jumlah titik GPS yang ditolak karena alasan akurasi atau anomali.
  ///
  /// Angka ini ditampilkan di panel debug akurasi GPS agar pengguna
  /// bisa melihat seberapa sering data GPS tidak dipakai.
  int titikDitolak = 0;

  /// Jumlah titik GPS yang berhasil diproses.
  int titikDiterima = 0;

  // ------------------------------------------------------------
  // PEMBACAAN STATISTIK
  // ------------------------------------------------------------

  /// Total jarak terfilter dalam kilometer.
  double get totalJarakKm => _totalJarakKm;

  /// Total waktu tempuh sesi dalam detik.
  double get totalWaktuDetik => _totalWaktuDetik;

  /// Kilometer yang sedang berjalan, misal 0,42 KM.
  double get kmBerjalan => _kmBerjalan;

  /// Jumlah kilometer penuh yang sudah selesai.
  int get kmSelesai => _kmSelesai;

  /// Pace kilometer terakhir yang selesai, dalam detik per kilometer.
  int? get paceKmTerakhirDetik => _paceKmTerakhirDetik;

  /// Kecepatan rata-rata sesi dalam km/jam.
  ///
  /// Mengembalikan 0 bila waktu tempuh belum cukup untuk dihitung,
  /// supaya tidak terjadi pembagian dengan nol pada sesi yang baru mulai.
  double get kecepatanRataRataKmh {
    if (_totalWaktuDetik <= 0) return 0;
    return (_totalJarakKm / _totalWaktuDetik) * 3600.0;
  }

  /// Pace rata-rata seluruh sesi dalam detik per kilometer.
  double? get paceRataRataDetik {
    if (_totalJarakKm <= 0.01) return null;
    return _totalWaktuDetik / _totalJarakKm;
  }

  /// Pace real-time: gabungan pace kilometer terakhir dengan pace
  /// rata-rata sesi.
  ///
  /// Bukan window 30 detik murni. Alasannya, data GPS per detik terlalu
  /// kasar untuk dijadikan window pendek: satu tikungan bisa mengubah
  /// pace sesaat secara signifikan. Penggabungan bobot 70 persen untuk
  /// kilometer terakhir dengan 30 persen rata-rata sesi menghasilkan
  /// angka yang responsif tanpa terlihat liar.
  double? get paceRealTimeDetik {
    // Butuh minimal 5 detik data, kalau tidak pace berfluktuasi berlebihan
    // pada detik-detik pertama.
    if (_totalWaktuDetik < 5) return null;

    final double? rataRata = paceRataRataDetik;
    if (rataRata == null) return null;

    final double? paceTerakhir = _paceKmTerakhirDetik?.toDouble();
    // Kalau belum ada kilometer yang selesai, rata-rata sesi adalah
    // satu-satunya data yang tersedia.
    if (paceTerakhir == null) return rataRata;

    return (paceTerakhir * 0.7) + (rataRata * 0.3);
  }

  // ------------------------------------------------------------
  // RESET
  // ------------------------------------------------------------
  /// Mengosongkan seluruh state sehingga pelacak siap untuk sesi baru.
  ///
  /// Harus dipanggil saat mulai atau selesai lari. Kalau tidak, state
  /// sesi lama akan tercampur dan jarak akan terhitung akumulatif.
  void reset() {
    _kalman.reset();
    _latTerakhir = null;
    _lonTerakhir = null;
    _waktuTerakhirMs = null;
    _kmBerjalan = 0.0;
    _kmSelesai = 0;
    _totalJarakKm = 0.0;
    _totalWaktuDetik = 0.0;
    _paceKmTerakhirDetik = null;
    lintasan.clear();
    titikDitolak = 0;
    titikDiterima = 0;
  }

  /// Menyinkronkan waktu tempuh sesi dari Stopwatch milik pemanggil.
  ///
  /// Stopwatch adalah sumber kebenaran waktu, karena tick-nya berasal
  /// dari clock sistem yang monoton, tidak terpengaruh oleh kelonggaran
  /// timer maupun disruptions GPS.
  void sinkronkanWaktu(double stopwatchDetik) {
    _totalWaktuDetik = stopwatchDetik;
  }

  // ------------------------------------------------------------
  // PEMROSESAN TITIK GPS
  // ------------------------------------------------------------
  /// Memproses satu titik GPS baru dan mengembalikan kilometer yang
  /// baru saja selesai, atau null bila belum ada kilometer yang selesai.
  ///
  /// Parameter:
  ///   - [lat]: latitude titik baru dalam derajat.
  ///   - [lon]: longitude titik baru dalam derajat.
  ///   - [waktuMs]: waktu pengambilan titik dalam milidetik epoch.
  ///   - [akurasiMeter]: radius akurasi horizontal dari GPS.
  ///
  /// Mengembalikan nomor kilometer yang selesai pada pemanggilan ini,
  /// atau null jika kilometer ini belum genap.
  int? prosesTitik({
    required double lat,
    required double lon,
    required int waktuMs,
    required double akurasiMeter,
  }) {
    // LANGKAH 1: Buang titik yang akurasinya terlalu buruk.
    // Ini lapis saringan pertama. Titik dengan akurasi lebih buruk dari
    // ambang tidak pernah sampai ke filter, karena memprosesnya hanya
    // menambah noise pada state Kalman.
    if (akurasiMeter > ambangAkurasiMaksMeter || akurasiMeter < 0) {
      titikDitolak++;
      return null;
    }

    // LANGKAH 2: Titik pertama hanya dipakai sebagai titik awal.
    // Tanpa titik sebelumnya kita tidak bisa menghitung jarak maupun
    // kecepatan, jadi yang kita lakukan hanya menyimpan posisi acuan.
    if (_latTerakhir == null || _lonTerakhir == null) {
      _simpanTitikAwal(lat, lon, waktuMs);
      return null;
    }

    // LANGKAH 3: Hitung jarak kasar dari titik sebelumnya.
    final double jarakKasar = GeoUtil.jarakAntarTitik(
      lat1: _latTerakhir!,
      lon1: _lonTerakhir!,
      lat2: lat,
      lon2: lon,
    );

    // Hitung delta waktu antar titik dalam detik.
    final int deltaMs = waktuMs - _waktuTerakhirMs!;
    final double deltaDetik = deltaMs / 1000.0;

    // LANGKAH 4: Saring anomali gerak.
    // Lonjakan posisi akibat kesalahan GPS ditolak di sini, sebelum
    // sempat merusak total jarak.
    if (!DeteksAnomali.valid(jarakMeter: jarakKasar, dtDetik: deltaDetik)) {
      titikDitolak++;
      return null;
    }

    // LANGKAH 5: Koreksi posisi baru dengan filter Kalman.
    //
    // Distance kasar di atas belum dipakai langsung. Kita sudah
    // menghitung jarak dari posisi SEBENARNYA (terfilter) ke titik baru,
    // sehingga noise yang lalu sudah ikut terkoreksi.
    //
    // Panjang lintasan terfilter sejauh ini adalah _totalJarakKm dalam
    // meter, dan jarak yang baru ditambahkan adalah selisih antara
    // posisi terfilter terakhir dengan posisi terfilter baru.
    //
    // Karena filter bekerja pada posisi sepanjang lintasan, kita
    // memberi tahu filter bahwa posisi sekarang adalah
    // (jarakLintasanSekarang + jarakKasarDariAwal).
    //
    // Pendekatan ini menyederhanakan filter 1D: koordinat geografis
    // diproyeksikan menjadi jarak kumulatif sepanjang lintasan.
    final double posisiSebelum = _totalJarakKm * 1000.0;
    final double pengukuranBaru = posisiSebelum + jarakKasar;
    final double posisiSesudah =
        _kalman.proses(pengukuranBaru, akurasiMeter);

    // Jarak tambahan yang benar = selisih posisi terfilter, bukan jarak kasar.
    // Inilah yang membuat total jarak jauh lebih akurat.
    final double jarakTambahan = (posisiSesudah - posisiSebelum) / 1000.0;

    // LANGKAH 6: Akumulasi jarak terfilter.
    // Waktu tempuh tidak dihitung di sini. Waktu sesi berasal dari
    // Stopwatch lewat [sinkronkanWaktu], karena delta waktu antar titik
    // GPS bisa hilang saat sinyal terputus sementara.
    _totalJarakKm += jarakTambahan;

    // Simpan posisi dan waktu titik ini sebagai acuan berikutnya.
    _latTerakhir = lat;
    _lonTerakhir = lon;
    _waktuTerakhirMs = waktuMs;

    // Catat titik untuk menggambar lintasan nanti.
    lintasan.add(TitikLari(
      lat: lat,
      lon: lon,
      jarakKm: _totalJarakKm,
      waktuMs: waktuMs,
    ));

    titikDiterima++;

    // LANGKAH 7: Deteksi batas kilometer.
    _kmBerjalan += jarakTambahan;

    // Syarat: jarak sudah mencapai satu kilometer penuh,
    // DAN tersedia waktu tempuh untuk menghitung pace.
    if (_kmBerjalan >= 1.0 && _totalWaktuDetik > 0) {
      _kmSelesai++;

      // Pace kilometer ini dihitung dari waktu kumulatif sesi dibagi
      // jumlah kilometer selesai. Ini otomatis menjadi pace rata-rata
      // kilometer yang baru saja selesai, dan otomatis memperhitungkan
      // perlambatan di tikungan maupun bagian naik.
      final int paceBaru = (_totalWaktuDetik / _kmSelesai).round();
      _paceKmTerakhirDetik = paceBaru;

      // Pecah sisa meter ke kilometer berjalan berikutnya.
      _kmBerjalan -= 1.0;

      return _kmSelesai;
    }

    return null;
  }

  /// Menyimpan titik GPS pertama sebagai acuan.
  ///
  /// Filter Kalman juga diberi titik awal supaya state internalnya
  /// mulai dekat dengan posisi sebenarnya, bukan melebar dari nol.
  void _simpanTitikAwal(double lat, double lon, int waktuMs) {
    _latTerakhir = lat;
    _lonTerakhir = lon;
    _waktuTerakhirMs = waktuMs;

    // Beri tahu filter posisi saat ini adalah nol meter (titik awal lintasan).
    _kalman.proses(0.0, 10.0);

    lintasan.add(TitikLari(
      lat: lat,
      lon: lon,
      jarakKm: 0.0,
      waktuMs: waktuMs,
    ));

    titikDiterima++;
  }

  /// Ambang akurasi GPS maksimum yang masih diterima, dalam meter.
  ///
  /// 50 meter dipilih longgar agar pengguna di area sinyal buruk tetap
  /// bisa merekam sesi. Titik di atas ambang ini diabaikan, bukan
  /// diperhitungkan, karena memaksakan data buruk hanya merusak hasil.
  static const double ambangAkurasiMaksMeter = 50.0;
}

/// ============================================================
/// MODEL: TITIK LARI
/// ============================================================
/// Satu titik yang sudah lolos filter, disimpan untuk menggambar
/// lintasan pada peta dan untuk mengunggah GPX ke Strava.
class TitikLari {
  /// Latitude dalam derajat.
  final double lat;

  /// Longitude dalam derajat.
  final double lon;

  /// Jarak kumulatif dari titik awal, dalam kilometer.
  final double jarakKm;

  /// Waktu pengambilan titik, dalam milidetik epoch.
  final int waktuMs;

  TitikLari({
    required this.lat,
    required this.lon,
    required this.jarakKm,
    required this.waktuMs,
  });
}
