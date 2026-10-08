import 'dart:async';

import '../models/profil_pelari.dart';
import '../models/split_kilometer.dart';
import 'ai_coach_engine.dart';

/// ============================================================
/// STATUS SIMULASI
/// ============================================================
/// Siklus hidup simulasi, dipakai untuk menentukan UI mana yang tampil.
enum StatusSimulasi {
  /// Belum dimulai.
  siap,

  /// Sedang berjalan.
  berjalan,

  /// Sudah mencapai garis finis.
  selesai,
}

/// ============================================================
/// MESIN SIMULASI BALAPAN
/// ============================================================
/// Menjalankan simulasi balapan mile-by-mile dengan strategi pace
/// yang berubah mengikuti fase balapan.
///
/// Mengapa memakai Stopwatch DAN Timer.periodic? keduanya punya peran
/// berbeda dan tidak saling menggantikan:
///
///   - `Stopwatch` adalah SUMBER KEBENARAN WAKTU. Ia menghitung
///     milidetik sejak [mulai], memakai clock sistem yang monoton.
///     Tidak ada akumulasi error dari scheduler.
///
///   - Timer.periodic hanya berperan sebagai PENDETAK PING. Ia bangun
///     setiap 100 milidetik untuk memuat ulang tampilan. Karena OS bisa
///     menunda callback, jarak TIDAK dihitung dari `timer.tick * 0.1`,
///     tapi dari selisih [Stopwatch] yang dibaca ulang. Dengan begitu
///     tampilan tetap mulus tanpa jarak menjadi drift.
///
/// Ini pola yang wajib dipakai untuk semua timer anyways UID: timer
/// untuk menggambar, stopwatch untuk menghitung.
class SimulatorBalapan {
  SimulatorBalapan._(); // kelas utilitas, dipakai lewat factory di bawah

  /// Interval antar tick, dalam milidetik.
  ///
  /// 100 milidetik menghasilkan 10 pembaruan per detik, cukup halus
  /// untuk angka timer tanpa membebani battery.
  static const int intervalTickMs = 100;

  // --- State simulasi ---
  /// Sumber kebenaran waktu simulasi.
  final Stopwatch _stopwatch = Stopwatch();

  /// Timer pemicu tick.
  Timer? _timer;

  /// Hasil AI Coach Engine.
  ProfilPelari? _profil;

  /// Rencana split per kilometer dari [SplitStrategi].
  List<SplitKilometer> _rencana = <SplitKilometer>[];

  /// Split yang benar-benar sudah diselesaikan selama simulasi.
  final List<SplitKilometer> _splitSelesai = <SplitKilometer>[];

  /// Kilometer target. Sesi berhenti otomatis saat menyentuh angka ini.
  double _targetKm = 0;

  /// Kilometer yang sedang ditempuh pada kilometer berjalan sekarang.
  double _kmBerjalan = 0;

  /// Waktu tempuh kilometer berjalan sekarang, dalam detik.
  /// Disimpan terpisah agar pace bisa dihitung dengan benar.
  double _waktuKmBerjalan = 0;

  /// Kecepatan simulasi saat ini, dalam meter per detik.
  ///
  /// Kecepatan dihitung dari pace kilometer yang sedang berjalan,
  /// lalu diinterpolasi agar tidak melompat-lompat.
  double _kecepatanSekarangMs = 0;

  /// Status siklus hidup simulasi.
  StatusSimulasi _status = StatusSimulasi.siap;

  /// Dipanggil setiap tick. Widget subscribing ke callback ini.
  void Function()? _onTick;

  /// Dipanggil sekali saat garis finis tercapai.
  void Function()? _onSelesai;

  // ------------------------------------------------------------
  // PEMBACAAN STATE
  // ------------------------------------------------------------
  /// Status simulasi saat ini.
  StatusSimulasi get status => _status;

  /// Apakah simulasi sedang berjalan.
  bool get sedangBerjalan => _status == StatusSimulasi.berjalan;

  /// Kilometer yang sedang ditempuh, bisa melebihi 1 saat sudah melewati
  /// kilometer pertama.
  double get kmBerjalan => _kmBerjalan;

  /// Jarak total yang sudah ditempuh, dalam kilometer.
  double get jarakTotalKm => _kmBerjalan;

  /// Target jarak, dalam kilometer.
  double get targetKm => _targetKm;

  /// Waktu simulasi berjalan dalam detik.
  double get waktuDetik => _stopwatch.elapsedMilliseconds / 1000.0;

  /// Kecepatan saat ini dalam meter per detik.
  double get kecepatanMs => _kecepatanSekarangMs;

  /// Kecepatan saat ini dalam km/jam, untuk ditampilkan.
  double get kecepatanKmh => _kecepatanSekarangMs * 3.6;

  /// Splits yang sudah selesai.
  ///
  /// Dikembalikan sebagai daftar tidak bisa diubah supaya widget
  /// tidak bisa mengubah state simulasi dari luar.
  List<SplitKilometer> get splitSelesai =>
      List<SplitKilometer>.unmodifiable(_splitSelesai);

  /// Rencana split lengkap, untuk ditampilkan sebelum simulasi dimulai.
  List<SplitKilometer> get rencana =>
      List<SplitKilometer>.unmodifiable(_rencana);

  /// Progres sesi dari 0 sampai 1, untuk progress bar.
  double get progres {
    if (_targetKm <= 0) return 0;
    return (_kmBerjalan / _targetKm).clamp(0.0, 1.0);
  }

  /// Label fase balapan saat ini, untuk mewarnai kartu pace.
  ///
  /// Mengembalikan string yang sama dengan label pada rencana split.
  String get labelFase {
    if (_rencana.isEmpty) return 'SIAP';

    // Cari kilometer yang sedang berjalan (indeks berbasis kilometer penuh).
    final int kmSekarang = _kmBerjalan.floor().clamp(0, _rencana.length - 1);
    return _rencana[kmSekarang].labelSegmen;
  }

  /// Rata-rata pace sejauh ini dalam detik per kilometer.
  double? get paceRataRata {
    if (_kmBerjalan <= 0.01) return null;
    return _stopwatch.elapsedMilliseconds / 1000.0 / _kmBerjalan;
  }

  /// Pace kilometer berjalan sekarang, dalam detik per kilometer.
  ///
  /// Pace ini memakai sisa waktu kilometer berjalan yang sudah
  ///ikeliling. Penting: pace kilometer berjalan dihitung dari waktu
  /// kilometer berjalan saja, bukan dari total waktu, supaya setelah
  /// lewat kilometer pertama pace yang ditampilkan sesuai dengan apa
  /// yang sedang terjadi, bukan rata-rata.
  double? get paceKmBerjalan {
    // Sanity check: butuh waktu tempuh sudah sedikit.
    if (_waktuKmBerjalan < 1) return null;

    // Kalau km berjalan sudah lewat 1, kita perlu sisa jarak di
    // kilometer terakhir.
    double sisaKm = _kmBerjalan % 1.0;
    // Kalau tepat di batas kilometer (sisa 0), tampilkan pace kilometer
    // yang baru saja selesai, bukan membagi dengan nol.
    if (sisaKm < 0.01) sisaKm = 1.0;

    return _waktuKmBerjalan / sisaKm;
  }

  /// Catatan coach untuk kilometer yang sedang berjalan.
  String get catatanCoach {
    if (_rencana.isEmpty) return '';
    final int kmSekarang = _kmBerjalan.floor().clamp(0, _rencana.length - 1);
    return _rencana[kmSekarang].catatanCoach;
  }

  // ------------------------------------------------------------
  // KONTROL
  // ------------------------------------------------------------
  /// Menyiapkan simulasi dari hasil AI Coach Engine.
  ///
  /// Harus dipanggil sebelum [mulai]. Menyimpan profil dan rencana
  /// split, sekaligus mereset seluruh state.
  void siapkan(ProfilPelari profil) {
    _profil = profil;
    _rencana = List<SplitKilometer>.from(profil.rencanaSplit);
    _targetKm = profil.targetJarakKm;
    _reset();
  }

  /// Memulai simulasi.
  ///
  /// Parameter:
  ///   - [onTick]: dipanggil setiap 100 milidetik dengan state terbaru.
  ///   - [onSelesai]: dipanggil sekali ketika target jarak tercapai.
  void mulai({
    required void Function() onTick,
    required void Function() onSelesai,
  }) {
    // Guard: mencegah dua timer berjalan bersamaan kalau tombol
    // ditekan dua kali cepat.
    if (_status == StatusSimulasi.berjalan) return;

    // Hitung ulang rencana dari engine kalau belum disiapkan.
    if (_profil != null && _rencana.isEmpty) {
      _rencana = SplitStrategiCache.rencana(_profil!);
    }

    // Simpan callback supaya tick berikutnya tahu harus notifying siapa.
    _onTick = onTick;
    _onSelesai = onSelesai;

    // Set status dulu, baru jalankan stopwatch, supaya tidak ada
    // race di mana UI sudah terima callback sebelum state siap.
    _status = StatusSimulasi.berjalan;

    // Nyalakan sumber kebenaran waktu.
    _stopwatch.start();

    // Jalankan timer. Perhatikan: timer hanya triggering tick,
    // semua perhitungan jarak memakai _stopwatch.
    _timer = Timer.periodic(
      const Duration(milliseconds: intervalTickMs),
      _tick,
    );
  }

  /// Menghentikan simulasi sementara, mempertahankan state.
  ///
  /// Dipakai untuk tombol jeda. Stopwatch dijeda, timer dibatalkan.
  void jeda() {
    if (_status != StatusSimulasi.berjalan) return;

    // Matikan timer supaya tidak ada tick yang menggantung.
    _timer?.cancel();
    _timer = null;

    // Jeda stopwatch supaya waktu tidak bertambah.
    _stopwatch.stop();

    // Status kembali ke siap, tapi state distance TIDAK direset,
    // supaya simulasi bisa dilanjutkan.
    _status = StatusSimulasi.siap;
  }

  /// Melanjutkan simulasi yang dijeda.
  void lanjut() {
    if (_status == StatusSimulasi.berjalan) return;
    if (_status == StatusSimulasi.selesai) return;

    _status = StatusSimulasi.berjalan;
    _stopwatch.start();

    _timer = Timer.periodic(
      const Duration(milliseconds: intervalTickMs),
      _tick,
    );
  }

  /// Menghentikan simulasi dan mereset semua state.
  void stop() {
    _timer?.cancel();
    _timer = null;
    _stopwatch.reset();
    _reset();
  }

  /// Mereset state internal.
  ///
  /// [_tickTerakhir] WAJIB ikut di-reset ke nol. Alasannya, field itu
  /// menyimpan acuan waktu stopwatch dari tick sebelumnya. Kalau tidak
  /// di-reset, deltaDetik pada tick berikutnya bernilai negatif dan
  /// seluruh tick akan dilewati tanpa pernah menambah jarak.
  void _reset() {
    _kmBerjalan = 0;
    _waktuKmBerjalan = 0;
    _splitSelesai.clear();
    _kecepatanSekarangMs = 0;
    _tickTerakhir = 0.0;
    _status = StatusSimulasi.siap;
  }

  // ------------------------------------------------------------
  // TICK: INTI PERHITUNGAN
  // ------------------------------------------------------------
  /// Satu siklus perhitungan. Dipanggil setiap 100 milidetik.
  ///
  /// Empat langkah di bawah ini adalah inti simulasi.
  void _tick(Timer _) {
    // LANGKAH 1: Baca waktu dari stopwatch.
    // Ini sumber kebenaran. Nilai ini SELALU benar, berapa pun
    //(callback UI) yang tidak tepat jadwalnya.
    final double waktuSekarangDetik = _stopwatch.elapsedMilliseconds / 1000.0;

    // LANGKAH 2: Tentukan kilometer penuh yang sedang berjalan.
    //.floor() mengubah 3,7 menjadi 3, yaitu indeks kilometer yang
    // sedang ditempuh.
    final int kmPenuhSekarang = _kmBerjalan.floor();

    // Kecepatan untuk kilometer ini diambil dari rencana split.
    // Fallback ke pace target kalau indeks melewati rencana.
    double kecepatanKmeter;
    if (kmPenuhSekarang < _rencana.length) {
      // Kecepatan m/s = 1000 meter / pace detik.
      // Contoh: pace 245 detik -> 1000/245 = 4,08 m/s.
      kecepatanKmeter = 1000.0 / _rencana[kmPenuhSekarang].paceDetik;
    } else {
      // Fallback: pakai target pace adaptif.
      kecepatanKmeter = 1000.0 / (_profil?.targetPaceAdaptifDetik ?? 300);
    }

    // LANGKAH 3: Hitung jarak yang ditempuh pada tick ini.
    //
    // Ini rumus anti-drift. Jarak TIDAK dihitung sebagai
    // tick * interval, tapi dari selisih waktu stopwatch:
    //
    //   jarakTick = kecepatan x selisih waktu sejak tick sebelumnya
    //
    // Menyimpan waktu tick terakhir membuat selisih selalu mencerminkan
    // waktu yang benar-benar berlalu, apakah OS menunda callback atau tidak.
    final double waktuAkhirTick = waktuSekarangDetik;

    // Hitung selisih dari tick sebelumnya, guard terhadap nilai negatif
    // yang mungkin terjadi setelah reset.
    final double deltaDetik = waktuAkhirTick - _tickTerakhir;
    if (deltaDetik <= 0) {
      // Tidak ada waktu yang berlalu; lewati tick ini.
      return;
    }

    // Kecepatan saat ini diinterpolasi: pakai kecepatan kilometer
    // berjalan, lalu slight approach (smooth) supaya tidak melompat.
    _kecepatanSekarangMs = kecepatanKmeter;

    // Jarak yang ditempuh: kecepatan kali waktu.
    // 4,08 m/s * 0,1 detik = 0,408 meter per tick.
    final double jarakTickMeter = _kecepatanSekarangMs * deltaDetik;
    final double jarakTickKm = jarakTickMeter / 1000.0;

    // Tambahkan jarak ke kilometer berjalan.
    _kmBerjalan += jarakTickKm;

    // Tambahkan waktu tempuh kilometer berjalan dengan delta yang sama.
    _waktuKmBerjalan += deltaDetik;

    // Simpan waktu akhir tick ini untuk perhitungan tick berikutnya.
    _tickTerakhir = waktuAkhirTick;

    // LANGKAH 4: Deteksi crossing batas kilometer.
    // Kalau kita sudah melewati satu kilometer penuh, catat split.
    //
    // Syaratnya kilometers yang sudah selesai berubah dari kmPenuhSebelum.
    if (_kmBerjalan.floor() > kmPenuhSekarang) {
      _catatSplit(kmPenuhSekarang + 1);
    }

    // Pengecekan garis finis.
    // Kalau jarak menyentuh atau melampaui target, hentikan simulasi.
    if (_kmBerjalan >= _targetKm) {
      _selesai();
      return;
    }

    // Notifikasi UI dengan state terbaru.
    _onTick?.call();
  }

  /// Waktu stopwatch pada akhir tick sebelumnya, dalam detik.
  ///
  /// Disimpan sebagai field, bukan variabel lokal, karena nilainya
  /// harus bertahan antar pemanggilan tick.
  double _tickTerakhir = 0.0;

  /// Mencatat satu kilometer yang selesai.
  ///
  /// Mengambil pace dari rencana AI, lalu menyimpan salinannya dengan
  /// waktu kumulatif simulasi saat ini.
  void _catatSplit(int nomorKm) {
    // Guard: jangan catat(split yang sama dua kali.
    if (_splitSelesai.isNotEmpty &&
        _splitSelesai.last.nomor == nomorKm) {
      return;
    }

    // Pace dari rencana AI untuk kilometer ini.
    final int paceKm = nomorKm <= _rencana.length
        ? _rencana[nomorKm - 1].paceDetik
        : (_profil?.targetPaceAdaptifDetik ?? 300);

    // Waktu kumulatif = waktu simulasi sekarang, yang sudah termasuk
    // seluruh kilometer sebelumnya.
    _splitSelesai.add(SplitKilometer(
      nomor: nomorKm,
      paceDetik: paceKm,
      waktuKumulatifDetik: _stopwatch.elapsed.inSeconds,
      labelSegmen: nomorKm <= _rencana.length
          ? _rencana[nomorKm - 1].labelSegmen
          : 'TEMPO',
      catatanCoach: nomorKm <= _rencana.length
          ? _rencana[nomorKm - 1].catatanCoach
          : '',
    ));

    // Reset penghitung kilometer berjalan.
    // Sisa jarak di kilometer yang sama dihitung ulang dari sisa
    // (_kmBerjalan % 1) yang otomatis tertangani oleh _kmBerjalan.
    _waktuKmBerjalan = 0;
  }

  /// Menandai simulasi selesai dan memberi tahu UI.
  void _selesai() {
    // Pastikan tidak dipanggil dua kali.
    if (_status == StatusSimulasi.selesai) return;

    // Matikan semua timer.
    _timer?.cancel();
    _timer = null;
    _stopwatch.stop();

    // Set status selesai.
    _status = StatusSimulasi.selesai;

    // Set jarak tepat di target supaya progress bar 100 persen dan tidak
    // terlihat overshoot.
    _kmBerjalan = _targetKm;

    // Beri tahu UI kalau ada kilometer terakhir yang belum tercatat.
    final int kmTerakhir = _targetKm.floor();
    if (_splitSelesai.length < kmTerakhir) {
      _catatSplit(kmTerakhir);
    }

    _onTick?.call();
    _onSelesai?.call();
  }

  /// Factory constructor supaya bisa memakai pola `SimulatorBalapan.buat()`.
  factory SimulatorBalapan.buat() => SimulatorBalapan._();
}

/// ============================================================
/// CACHE RENCANA SPLIT
/// ============================================================
/// Menghasilkan rencana split dari profil tanpa harus memanggil
/// engine secara langsung. Dipisah supaya [SimulatorBalapan]
/// tidak perlu mengimpor [SplitStrategi] secara langsung.
class SplitStrategiCache {
  SplitStrategiCache._(); // kelas utilitas

  /// Menghasilkan rencana split per kilometer untuk sebuah profil.
  static List<SplitKilometer> rencana(ProfilPelari profil) {
    return AICoachEngine.buatRencanaSplitUntukProfil(profil);
  }
}
