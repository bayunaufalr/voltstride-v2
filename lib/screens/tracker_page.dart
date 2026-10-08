import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../logic/ai_coach_engine.dart';
import '../logic/pelacak_lari.dart';
import '../logic/penyusun_rencana.dart';
import '../logic/race_simulator.dart';
import '../models/profil_pelari.dart';
import '../models/rencana_latihan.dart';
import '../models/split_kilometer.dart';
import '../services/lokasi_service.dart';
import '../services/online_coach_service.dart';
import '../services/strava_api_client.dart';
import '../theme/volt_theme.dart';

/// ============================================================
/// TRACKER PAGE: MODUL UTAMA VOLTSTRIDE
/// ============================================================
/// Halaman ini adalah inti aplikasi dan punya empat bagian yang
/// saling terhubung lewat [_ProfilPelari] hasil perhitungan engine:
///
///   1. AI COACH FORM
///      Empat input: umur, target jarak, target pace, pace 10KM terakhir.
///      Tombol "Rancang Latihan AI" memanggil [AICoachEngine] dan
///      [PenyusunRencana] secara lokal lewat setState.
///
///   2. LIVE GPS RUN
///      Pengukuran lari sungguhan memakai geolocator dengan akurasi
///      tinggi, Kalman filter, dan deteksi anomali. Stopwatch adalah
///      sumber kebenaran waktu.
///
///   3. RACE SIMULATION
///      Menjalankan strategi split AI per kilometer secara live dengan
///      Timer.periodic dan Stopwatch.
///
///   4. ONLINE COACH
///      Chat dan penyesuaian rencana lewat HTTP, dengan fallback ke
///      hasil lokal saat server tidak terjangkau.
class TrackerPage extends StatefulWidget {
  const TrackerPage({super.key});

  @override
  State<TrackerPage> createState() => _TrackerPageState();
}

class _TrackerPageState extends State<TrackerPage> {
  // ------------------------------------------------------------
  // CONTROLLER FORM
  // ------------------------------------------------------------
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _cUmur = TextEditingController();
  final TextEditingController _cJarak = TextEditingController();
  final TextEditingController _cTargetPace = TextEditingController();
  final TextEditingController _cPace10k = TextEditingController();

  @override
  void dispose() {
    // Controller harus di-dispose supaya tidak terjadi memory leak
    // saat pengguna berpindah tab lalu kembali.
    _cUmur.dispose();
    _cJarak.dispose();
    _cTargetPace.dispose();
    _cPace10k.dispose();
    // Timer dan stream GPS juga harus dihentikan.
    _timerUi?.cancel();
    _streamPosisi?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------
  // STATE AI COACH
  // ------------------------------------------------------------
  /// Hasil perhitungan AI Coach Engine. Null sampai tombol ditekan.
  ProfilPelari? _profil;

  /// Rencana latihan hasil [PenyusunRencana].
  RencanaLatihan? _rencana;

  /// Rencana hasil server, kalau online coach berhasil.
  RencanaLatihan? _rencanaOnline;

  /// Riwayat chat online coach.
  final List<Map<String, String>> _riwayatChat = <Map<String, String>>[];

  /// TextField chat.
  final TextEditingController _cChat = TextEditingController();

  /// Status proses asynchronous, supaya UI bisa menampilkan spinner.
  bool _memproses = false;

  // ------------------------------------------------------------
  // STATE LIVE GPS
  // ------------------------------------------------------------
  /// Mesin pelacak yang mengolah titik GPS menjadi statistik.
  final PelacakLari _pelacak = PelacakLari();

  /// Sumber kebenaran waktu untuk sesi GPS.
  final Stopwatch _swGps = Stopwatch();

  /// Timer untuk memompa ulang UI dari Stopwatch.
  ///
  /// Sengaja terpisah dari stream GPS: Even if GPS update melambat,
  ///  timer ini tetap membuat angka waktu terus naik mulus.
  Timer? _timerUi;

  /// Langganan stream posisi GPS.
  StreamSubscription<Position>? _streamPosisi;

  /// Status sesi GPS: apakah sedang merekam.
  bool _gpsAktif = false;

  /// Pesan error terakhir terkait GPS, untuk ditampilkan ke pengguna.
  String? _pesanGps;

  // ------------------------------------------------------------
  // STATE SIMULASI BALAPAN
  // ------------------------------------------------------------
  /// Mesin simulasi balapan.
  final SimulatorBalapan _simulator = SimulatorBalapan.buat();

  @override
  void initState() {
    super.initState();

    // Isi form dengan nilai default yang masuk akal supaya pengguna
    // bisa langsung menekan tombol tanpa mengisi semuanya.
    _cUmur.text = '25';
    _cJarak.text = '10';
    _cTargetPace.text = '5.00';
    _cPace10k.text = '5.40';

    // Timer UI untuk sesi GPS: membaca Stopwatch setiap 250 milidetik.
    // 250 milidetik cukup halus untuk angka timer dan hemat baterai
    // dibanding 100 milidetik.
    _timerUi = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_gpsAktif) return;

      // Sinkronkan waktu sesi ke mesin pelacak. Tanpa ini, pace tidak
      // bisa dihitung karena waktu tempuh selalu nol.
      _pelacak.sinkronkanWaktu(_swGps.elapsedMilliseconds / 1000.0);

      // setState hanya saat sedang merekam, supaya tidak rebuild
      // widget yang tidak perlu.
      if (mounted) setState(() {});
    });
  }

  // ------------------------------------------------------------
  // 1. AI COACH FORM
  // ------------------------------------------------------------

  /// Membaca dan memvalidasi input form, lalu menjalankan engine.
  ///
  /// Alur:
  ///   1. Validasi form (Field kosong atau format salah ditolak).
  ///   2. Konversi input teks ke angka.
  ///   3. Panggil [AICoachEngine.hitungProfil] di thread utama.
  ///      Perhitungan ini ringan (sekitar beberapa puluh operasi
  ///      floating point) sehingga aman di isolate utama.
  ///   4. Panggil [PenyusunRencana.susun] untuk program mingguan.
  ///   5. Siapkan simulator balapan dengan hasil tersebut.
  void _jalankanAICoach() {
    // Validasi form dulu.
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _memproses = true);

    // Konversi input. Parse bisa gagal, tapi sudah ditangani validator.
    final int umur = int.parse(_cUmur.text);
    final double jarak = double.parse(_cJarak.text);
    final int targetPace = _detikDariPace(_cTargetPace.text);
    final int pace10k = _detikDariPace(_cPace10k.text);

    // Panggil engine.
    final ProfilPelari profil = AICoachEngine.hitungProfil(
      umur: umur,
      targetJarakKm: jarak,
      targetPaceDetik: targetPace,
      pace10kTerakhirDetik: pace10k,
    );

    // Susun rencana latihan mingguan.
    final RencanaLatihan rencana = PenyusunRencana.susun(profil);

    // Siapkan simulator dengan hasil ini.
    _simulator.siapkan(profil);

    setState(() {
      _profil = profil;
      _rencana = rencana;
      _rencanaOnline = null; // reset hasil server sebelumnya
      _memproses = false;
    });

    // Beri getaran ringan sebagai feedback bahwa aksi berhasil.
    HapticFeedback.selectionClick();
  }

  /// Mengubah pace bergaya "5.00" menjadi detik, yaitu 300.
  ///
  /// Format yang dipakai pengguna: "menit.desimal" seperti 5.00 atau 4.75.
  /// Konversinya:
  ///   5.00 -> 5 menit 0 detik = 300 detik
  ///   4.75 -> 4 menit 45 detik = 285 detik
  static int _detikDariPace(String teks) {
    final String bersih = teks.trim().replaceAll(',', '.');
    final double nilai = double.tryParse(bersih) ?? 5.0;

    final int menit = nilai.floor();
    // Detik dari bagian desimal: 0.75 dari 75 detik.
    final int detik = ((nilai - menit) * 100).round();

    return menit * 60 + detik;
  }

  // ------------------------------------------------------------
  // 2. LIVE GPS RUN
  // ------------------------------------------------------------

  /// Memulai perekaman lari dengan GPS.
  ///
  /// Alur:
  ///   1. Pastikan layanan lokasi perangkat menyala.
  ///   2. Minta izin lokasi bila belum diberikan.
  ///   3. Reset mesin pelacak supaya tidak ada sisa sesi lama.
  ///   4. Nyalakan Stopwatch sebagai sumber waktu.
  ///   5. Subscribe stream GPS dan arahkan tiap titik ke [_pelacak].
  ///
  /// Setiap kegagalan di salah satu langkah menghasilkan pesan yang
  /// bisa ditindaklanjuti, bukan crash.
  Future<void> _mulaiGps() async {
    // LANGKAH 1: cek layanan lokasi menyala.
    final bool aktif = await LokasiService.cekLayananAktif();
    if (!aktif) {
      setState(() => _pesanGps =
          'GPS perangkat sedang mati. Aktifkan lokasi dulu.');
      return;
    }

    // LANGKAH 2: minta izin lokasi.
    final bool diizinkan = await LokasiService.mintaIzin();
    if (!diizinkan) {
      setState(() => _pesanGps =
          'Izin lokasi dibutuhkan untuk mengukur jarak lari.');
      return;
    }

    // LANGKAH 3: reset state pelacak.
    _pelacak.reset();

    // LANGKAH 4: nyalakan stopwatch.
    _swGps.reset();
    _swGps.start();

    // LANGKAH 5: subscribe stream GPS.
    // .onError dipakai agar error GPS tidak menghentikan seluruh stream.
    _streamPosisi = LokasiService.pasangStream().listen(
      (Position posisi) {
        // Teruskan titik mentah ke mesin pelacak.
        // Timestamp posisi sudah dalam milidetik epoch.
        _pelacak.prosesTitik(
          lat: posisi.latitude,
          lon: posisi.longitude,
          waktuMs: posisi.timestamp.millisecondsSinceEpoch,
          // akurasi horizontal sudah dalam meter.
          akurasiMeter: posisi.accuracy,
        );
        // rebuild UI supaya jarak dan pace ikut terupdate.
        if (mounted) setState(() {});
      },
      onError: (Object error) {
        if (mounted) {
          setState(() => _pesanGps = 'Gangguan sinyal GPS: $error');
        }
      },
    );

    setState(() {
      _gpsAktif = true;
      _pesanGps = null;
    });

    // Getaran saat mulai merekam.
    HapticFeedback.mediumImpact();
  }

  /// Menghentikan perekaman GPS.
  ///
  /// Sesi yang dihentikan tetap menampilkan statistiknya supaya
  /// pengguna bisa membandingkan jarak dan pace sebelum memulai lagi.
  void _hentiGps() {
    // Matikan stream GPS.
    _streamPosisi?.cancel();
    _streamPosisi = null;

    // Hentikan stopwatch.
    _swGps.stop();

    setState(() {
      _gpsAktif = false;
    });

    // Getaran selesai.
    HapticFeedback.mediumImpact();
  }

  // ------------------------------------------------------------
  // 3. RACE SIMULATION
  // ------------------------------------------------------------

  /// Menjalankan atau melanjutkan simulasi balapan AI.
  ///
  /// Dua kondisi yang ditangani oleh satu tombol:
  ///   1. Simulasi belum pernah berjalan: siapkan dari profil lalu mulai
  ///      dari kilometer nol.
  ///   2. Simulasi sedang dijeda di tengah jalan: lanjut dari jarak
  ///      sekarang, jangan di-reset.
  ///
  /// Simulasi hanya bisa jalan kalau profil sudah dihitung lewat
  /// [_jalankanAICoach]. Tombol dinonaktifkan kalau belum ada profil.
  void _mulaiSimulasi() {
    final ProfilPelari? profil = _profil;
    if (profil == null) return;

    // Kalau sudah ada jarak tempuh, berarti sesi ini dijeda.
    // Melanjutkan lebih baik daripada mengulang dari nol.
    if (_simulator.kmBerjalan > 0 &&
        _simulator.status != StatusSimulasi.selesai) {
      _simulator.lanjut();
      setState(() {});
      HapticFeedback.mediumImpact();
      return;
    }

    // Siapkan ulang simulator dengan data terbaru.
    _simulator.siapkan(profil);

    // Mulai dengan callback yang memanggil setState agar UI terupdate.
    _simulator.mulai(
      onTick: () {
        if (mounted) setState(() {});
      },
      onSelesai: () {
        // Selesai: getaran panjang yang menandai achievement.
        HapticFeedback.heavyImpact();
        if (mounted) setState(() {});
      },
    );

    HapticFeedback.mediumImpact();
  }

  // ------------------------------------------------------------
  // 4. ONLINE COACH
  // ------------------------------------------------------------

  /// Mengirim pesan ke online coach dan menampilkan jawabannya.
  ///
  /// Alur:
  ///   1. Validasi pesan tidak kosong.
  ///   2. Tambahkan pesan pengguna ke riwayat dan tampilkan.
  ///   3. Panggil server secara async.
  ///   4. Tampilkan jawaban, atau fallback lokal kalau server gagal.
  Future<void> _kirimChat() async {
    final String pesan = _cChat.text.trim();
    if (pesan.isEmpty || _profil == null) return;

    // Masukkan pesan pengguna ke riwayat.
    setState(() {
      _riwayatChat.add(<String, String>{
        'role': 'user',
        'content': pesan,
      });
      _cChat.clear();
      _memproses = true;
    });

    // Panggil server.
    final String? jawaban = await OnlineCoachService.tanyaCoach(
      profil: _profil!,
      pertanyaan: pesan,
      riwayat: _riwayatChat,
    );

    if (!mounted) return;

    setState(() {
      if (jawaban != null) {
        // Server menjawab. Tampilkan jawabannya.
        _riwayatChat.add(<String, String>{
          'role': 'coach',
          'content': jawaban,
        });
      } else {
        // Server gagal. Fallback ke jawaban lokal dari engine.
        // Ini menjamin aplikasi tetap berguna saat offline.
        _riwayatChat.add(<String, String>{
          'role': 'coach',
          'content': _jawabanLokal(pesan),
        });
      }
      _memproses = false;
    });
  }

  /// Menyusun jawaban lokal berdasarkan aturan sederhana.
  ///
  /// Kata kunci dicocokkan ke [ProfilPelari] dan [RencanaLatihan]
  /// sehingga jawaban lokal tetap spesifik pada data pelari.
  String _jawabanLokal(String pertanyaan) {
    final ProfilPelari? profil = _profil;
    if (profil == null) {
      return 'Isi form dan tekan Rancang Latihan AI dulu.';
    }

    final String q = pertanyaan.toLowerCase();

    // Permintaan jadwal minggu ini.
    if (q.contains('minggu ini') || q.contains('jadwal')) {
      final RencanaLatihan? rencana = _rencanaOnline ?? _rencana;
      if (rencana == null || rencana.minggu.isEmpty) {
        return 'Belum ada rencana. Tekan Rancang Latihan AI dulu.';
      }

      // Ambil sesi minggu pertama.
      final MingguLatihan mg = rencana.minggu.first;
      final String sesi = mg.sesi
          .map((SesiLatihan s) => '- ${s.ringkasan}')
          .join('\n');
      return 'Jadwal minggu ${mg.nomor} (${mg.tema}):\n$sesi';
    }

    // Permintaan tentang pace.
    if (q.contains('pace') || q.contains('kecepatan')) {
      return 'Target pace kamu ${_fmtPace(profil.targetPaceAdaptifDetik)} per km. '
          'Zona latihan: ${profil.petaZona.ringkasan}.';
    }

    // Permintaan tentang zona jantung.
    if (q.contains('denyut') || q.contains('jantung') || q.contains('hr')) {
      return 'HR max estimasi ${profil.hrMaxEstimasi} BPM. '
          'Zona tempo ${profil.zonaTempo.rentangTeks}.';
    }

    // Permintaan tentang program.
    if (q.contains('program') || q.contains('rencana')) {
      final RencanaLatihan? rencana = _rencana;
      if (rencana == null) {
        return 'Tekan Rancang Latihan AI dulu untuk melihat program.';
      }
      return '${rencana.ringkasan}\n${rencana.tujuan}';
    }

    // Default: kirimkan ringkasan profil.
    return profil.ringkasanSaran;
  }

  /// Meminta server menyesuaikan rencana latihan.
  Future<void> _mintaRencanaOnline() async {
    if (_profil == null || _rencana == null) return;

    setState(() => _memproses = true);

    final RencanaLatihan? hasil = await OnlineCoachService.mintaRencana(
      profil: _profil!,
      rencanaLokal: _rencana!,
    );

    if (!mounted) return;

    setState(() {
      // Kalau server berhasil, pakai hasilnya. Kalau tidak, tetap pakai
      // rencana lokal dan beri tahu pengguna.
      if (hasil != null) {
        _rencanaOnline = hasil;
      }
      _memproses = false;
    });
  }

  // ------------------------------------------------------------
  // STRAVA
  // ------------------------------------------------------------

  /// Mengirim hasil simulasi balapan ke Strava.
  ///
  /// Memakai payload JSON yang sudah disiapkan [StravaApiClient].
  Future<void> _sinkronkanStrava() async {
    final ProfilPelari? profil = _profil;
    if (profil == null) return;

    // Susun daftar split dari simulasi kalau ada, atau dari rencana AI.
    final List<SplitKilometer> splits = _simulator.splitSelesai.isNotEmpty
        ? _simulator.splitSelesai
        : profil.rencanaSplit;

    // Jarak dan durasi dari simulasi kalau sudah jalan, atau dari
    // estimasi engine kalau belum.
    final double jarak = jarakEfektifDariSimulasi(profil);
    final int durasi = durasiEfektifDariSimulasi(profil);

    // Kecepatan rata-rata dalam meter per detik.
    final double kecepatanMs = durasi > 0 ? jarak * 1000.0 / durasi : 0;

    // Bangun payload JSON.
    final Map<String, dynamic> payload = StravaApiClient.buatPayload(
      namaAktivitas: 'Simulasi Balapan AI ${profil.targetJarakKm} KM',
      deskripsi: 'Disimulasikan oleh VoltStride AI Coach.',
      jarakKm: jarak,
      durasiDetik: durasi,
      splits: splits,
      rataRataKecepatanMs: kecepatanMs,
    );

    // Kirim ke Strava.
    final String? error = await StravaApiClient.unggahActivity(payload: payload);

    if (!mounted) return;

    // Tampilkan hasil ke pengguna.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error == null
              ? 'Activity berhasil dikirim ke Strava.'
              : error,
        ),
        backgroundColor: error == null ? VoltWarna.hijau : VoltWarna.merah,
      ),
    );
  }

  /// Format detik menjadi "M'SS"".
  static String _fmtPace(int detik) {
    final int m = detik ~/ 60;
    final int s = detik % 60;
    return "$m'${s.toString().padLeft(2, '0')}\"";
  }

  // ==========================================================
  // BUILD
  // ==========================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Tidak ada AppBar karena halaman ini memakai Section yang
      // punya header sendiri lewat widget header di bawah.
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: <Widget>[
            _buildHeader(),
            const SizedBox(height: 20),
            _buildFormAICoach(),
            if (_profil != null) ...<Widget>[
              const SizedBox(height: 20),
              _buildKartuProfil(),
              const SizedBox(height: 20),
              _buildLiveGps(),
              const SizedBox(height: 20),
              _buildSimulasi(),
              const SizedBox(height: 20),
              _buildRencana(),
              const SizedBox(height: 20),
              _buildOnlineCoach(),
            ],
          ],
        ),
      ),
    );
  }

  /// Header halaman.
  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Judul besar dengan aksen neon.
        const Text(
          'VOLTSTRIDE',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: VoltWarna.aksen,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'AI Running Coach',
          style: TextStyle(
            fontSize: 15,
            color: VoltWarna.teksAbu,
            fontWeight: FontWeight.w600,
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  /// Form input AI Coach.
  Widget _buildFormAICoach() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Input Profil Pelari',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: VoltWarna.teksPutih,
                ),
              ),
              const SizedBox(height: 16),

              // --- Input umur ---
              TextFormField(
                controller: _cUmur,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Umur',
                  suffixText: 'tahun',
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                validator: (String? v) {
                  final int? nilai = int.tryParse(v ?? '');
                  if (nilai == null || nilai < 10 || nilai > 90) {
                    return 'Umur harus antara 10 sampai 90';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // --- Input target jarak ---
              TextFormField(
                controller: _cJarak,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Target Jarak',
                  suffixText: 'KM',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (String? v) {
                  final double? nilai = double.tryParse(v ?? '');
                  if (nilai == null || nilai <= 0 || nilai > 100) {
                    return 'Jarak harus antara 0 sampai 100 KM';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // --- Input target pace ---
              TextFormField(
                controller: _cTargetPace,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Target Pace',
                  // Contoh format yang diminta pengguna: 4.00.
                  helperText: 'Format menit per km, contoh 4.00',
                  prefixIcon: Icon(Icons.speed_outlined),
                ),
                validator: (String? v) {
                  if (_detikDariPace(v ?? '') <= 0) {
                    return 'Pace tidak valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // --- Input pace 10KM terakhir ---
              TextFormField(
                controller: _cPace10k,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Pace 10KM Terakhir',
                  helperText: 'Data aktual capability kamu',
                  prefixIcon: Icon(Icons.timer_outlined),
                ),
                validator: (String? v) {
                  if (_detikDariPace(v ?? '') <= 0) {
                    return 'Pace tidak valid';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // --- Tombol rancang latihan AI ---
              FilledButton.icon(
                onPressed: _memproses ? null : _jalankanAICoach,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Rancang Latihan AI'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kartu hasil perhitungan AI Coach.
  Widget _buildKartuProfil() {
    final ProfilPelari p = _profil!;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Hasil Analisis AI',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: VoltWarna.teksPutih,
              ),
            ),
            const SizedBox(height: 16),

            // Baris-baris statistik utama.
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatistikBox(
                    label: 'Target Pace',
                    nilai: _fmtPace(p.targetPaceAdaptifDetik),
                    satuan: '/km',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Skor Fitness',
                    nilai: p.skorKebugaran.toStringAsFixed(0),
                    satuan: '/100',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Est. Finish',
                    nilai: _fmtDurasi(p.estimasiDurasiDetik),
                    satuan: '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Detail zona.
            _BarisDetail('Zona Tempo', p.zonaTempo.rentangTeks),
            _BarisDetail('HR Max', '${p.hrMaxEstimasi} BPM'),
            _BarisDetail('Skor Kebugaran', '${p.skorKebugaran.toStringAsFixed(1)} / 100'),
            _BarisDetail('Selisih vs Target', '${p.selisihVsTarget} detik'),
            _BarisDetail('Peta Zona', p.petaZona.ringkasan),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Ringkasan saran.
            Text(
              p.ringkasanSaran,
              style: const TextStyle(
                color: VoltWarna.teksAbu,
                height: 1.5,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu live GPS run.
  Widget _buildLiveGps() {
    final double? pace = _pelacak.paceRealTimeDetik;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.gps_fixed, color: VoltWarna.aksen),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Live GPS Run',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: VoltWarna.teksPutih,
                    ),
                  ),
                ),
                // Indikator status yang berubah warna.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gpsAktif
                        ? VoltWarna.hijau.withOpacity(0.2)
                        : VoltWarna.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _gpsAktif ? 'REC' : 'IDLE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _gpsAktif ? VoltWarna.hijau : VoltWarna.teksAbu,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Angka besar: jarak.
            Center(
              child: Column(
                children: <Widget>[
                  Text(
                    _pelacak.totalJarakKm.toStringAsFixed(3),
                    style: const TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.w900,
                      color: VoltWarna.aksen,
                      height: 1,
                    ),
                  ),
                  const Text(
                    'KILOMETER',
                    style: TextStyle(
                      fontSize: 11,
                      color: VoltWarna.teksAbu,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Baris metrik sekunder.
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatistikBox(
                    label: 'Waktu',
                    nilai: _fmtDurasi(_swGps.elapsed.inSeconds),
                    satuan: '',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Pace',
                    nilai: pace == null ? '--' : _fmtPace(pace.round()),
                    satuan: '/km',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Kecepatan',
                    nilai: _pelacak.kecepatanRataRataKmh.toStringAsFixed(1),
                    satuan: 'km/h',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Panel akurasi GPS. Ini yang membedakan versi yang
            // memakai filter Kalman dari yang tidak.
            _PanelAkurasiGps(pelacak: _pelacak),
            const SizedBox(height: 16),

            // Pesan error bila ada.
            if (_pesanGps != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: VoltWarna.merah.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _pesanGps!,
                  style: const TextStyle(color: VoltWarna.merah, fontSize: 12),
                ),
              ),

            // Tombol mulai atau henti.
            FilledButton.icon(
              onPressed: _gpsAktif ? _hentiGps : _mulaiGps,
              icon: Icon(_gpsAktif ? Icons.stop_circle : Icons.play_arrow),
              label: Text(_gpsAktif ? 'Hentikan Rekam' : 'Mulai Lari GPS'),
              style: _gpsAktif
                  ? FilledButton.styleFrom(backgroundColor: VoltWarna.merah)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu simulasi balapan.
  Widget _buildSimulasi() {
    final bool jalan = _simulator.sedangBerjalan;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Race Simulation AI',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: VoltWarna.teksPutih,
              ),
            ),
            const SizedBox(height: 16),

            // Indikator fase balapan saat ini.
            if (_simulator.status != StatusSimulasi.siap)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _warnaFase.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.directions_run, color: _warnaFase),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _simulator.catatanCoach,
                        style: TextStyle(
                          color: _warnaFase,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Angka-angka simulasi.
            Row(
              children: <Widget>[
                Expanded(
                  child: _StatistikBox(
                    label: 'Jarak',
                    nilai: _simulator.jarakTotalKm.toStringAsFixed(2),
                    satuan: 'KM',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Pace',
                    nilai: _simulator.paceKmBerjalan == null
                        ? '--'
                        : _fmtPace(_simulator.paceKmBerjalan!.round()),
                    satuan: '/km',
                  ),
                ),
                Expanded(
                  child: _StatistikBox(
                    label: 'Fase',
                    nilai: _simulator.labelFase,
                    satuan: '',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress bar finish.
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _simulator.progres,
                minHeight: 10,
                backgroundColor: VoltWarna.surface,
                valueColor: AlwaysStoppedAnimation<Color>(_warnaFase),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Target ${_simulator.targetKm.toStringAsFixed(0)} KM',
              style: const TextStyle(fontSize: 11, color: VoltWarna.teksAbu),
            ),
            const SizedBox(height: 16),

            // Tombol kontrol simulasi.
            //
            // Label tombol utama menyesuaikan kondisi: kalau sudah ada
            // jarak tempuh, sesi dijeda, jadi tombolnya berarti "Lanjut"
            // bukan "Mulai".
            Row(
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: jalan ? null : _mulaiSimulasi,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _simulator.kmBerjalan > 0
                          ? 'Lanjut Simulasi'
                          : 'Mulai Simulasi',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: jalan
                        ? () {
                            _simulator.jeda();
                            setState(() {});
                          }
                        : null,
                    icon: const Icon(Icons.pause),
                    label: const Text('Jeda'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tombol sinkronkan Strava.
            OutlinedButton.icon(
              onPressed: _profil == null ? null : _sinkronkanStrava,
              icon: const Icon(Icons.sync),
              label: const Text('Sinkronkan ke Strava'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu rencana latihan mingguan.
  Widget _buildRencana() {
    final RencanaLatihan? rencana = _rencanaOnline ?? _rencana;
    // Guard: rencana tanpa minggu sama sekali tidak bisa dirender,
    // karena seluruh isi kartu dibangun dari minggu pertama.
    if (rencana == null || rencana.minggu.isEmpty) {
      return const SizedBox.shrink();
    }

    // Ambil minggu pertama untuk ditampilkan ringkas.
    final MingguLatihan mg = rencana.minggu.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.calendar_month, color: VoltWarna.violet),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Rencana Latihan',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: VoltWarna.teksPutih,
                    ),
                  ),
                ),
                // Badge sumber: AI lokal atau online coach.
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: VoltWarna.violet.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _rencanaOnline != null ? 'COACH' : 'AI',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: VoltWarna.violet,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              rencana.ringkasan,
              style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),

            // Jadwal minggu pertama.
            Text(
              'Minggu ${mg.nomor}: ${mg.tema} (${mg.totalJarakKm.toStringAsFixed(1)} KM)',
              style: const TextStyle(
                color: VoltWarna.aksen,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),

            // Chip setiap sesi.
            ...mg.sesi.map((SesiLatihan s) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Nama hari.
                    SizedBox(
                      width: 40,
                      child: Text(
                        _namaHari(s.hari),
                        style: const TextStyle(
                          color: VoltWarna.teksRedup,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            s.ringkasan,
                            style: const TextStyle(
                              color: VoltWarna.teksPutih,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            s.instruksi,
                            style: const TextStyle(
                              color: VoltWarna.teksAbu,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),

            // Tombol minta server menyesuaikan rencana.
            OutlinedButton.icon(
              onPressed: _memproses ? null : _mintaRencanaOnline,
              icon: const Icon(Icons.cloud_sync),
              label: const Text('Minta Online Coach Sesuaikan'),
            ),
          ],
        ),
      ),
    );
  }

  /// Kartu online coach chat.
  Widget _buildOnlineCoach() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Online Coach',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: VoltWarna.teksPutih,
              ),
            ),
            const SizedBox(height: 16),

            // Riwayat chat.
            if (_riwayatChat.isEmpty)
              const Text(
                'Tanya apa saja tentang programmu, misalnya '
                '"jadwal minggu ini" atau "pace saya harus berapa".',
                style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
              )
            else
              ..._riwayatChat.map(_buildPesanChat),

            const SizedBox(height: 12),

            // Input chat.
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _cChat,
                    style: const TextStyle(color: VoltWarna.teksPutih),
                    decoration: const InputDecoration(
                      hintText: 'Tanya coach...',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _kirimChat(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _memproses ? null : _kirimChat,
                  icon: const Icon(Icons.send, color: VoltWarna.aksen),
                ),
              ],
            ),

            // Spinner saat request.
            if (_memproses)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Widget untuk satu pesan chat.
  ///
  /// Pesan user ditampilkan rata kanan dengan warna aksen,
  /// pesan coach rata kiri dengan warna netral.
  Widget _buildPesanChat(Map<String, String> pesan) {
    final bool dariUser = pesan['role'] == 'user';

    return Align(
      alignment: dariUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: dariUser ? VoltWarna.aksen : VoltWarna.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          pesan['content'] ?? '',
          style: TextStyle(
            color: dariUser ? VoltWarna.latar : VoltWarna.teksPutih,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // HELPER SIMULASI
  // ------------------------------------------------------------

  /// Jarak efektif yang dipakai saat membuat payload Strava.
  ///
  /// Aturan: kalau simulasi sudah berjalan, pakai jarak simulasi.
  /// Kalau belum, pakai jarak target dari profil. Ini supaya tombol
  /// sinkronkan Strava tetap berguna walaupun simulasi belum dijalankan.
  double jarakEfektifDariSimulasi(ProfilPelari profil) {
    if (_simulator.status == StatusSimulasi.siap &&
        _simulator.jarakTotalKm <= 0) {
      return profil.targetJarakKm;
    }
    return _simulator.jarakTotalKm;
  }

  /// Durasi efektif yang dipakai saat membuat payload Strava.
  ///
  /// Aturan sama dengan [jarakEfektifDariSimulasi]: pakai hasil
  /// simulasi kalau ada, kalau tidak pakai estimasi engine.
  int durasiEfektifDariSimulasi(ProfilPelari profil) {
    if (_simulator.status == StatusSimulasi.siap &&
        _simulator.waktuDetik <= 0) {
      return profil.estimasiDurasiDetik;
    }
    return _simulator.waktuDetik.round();
  }

  // ------------------------------------------------------------
  // HELPER UI
  // ------------------------------------------------------------

  /// Warna sesuai fase simulasi saat ini.
  ///
  /// Hijau saat berlari normal, kuning saat recovery, violet saat selesai.
  Color get _warnaFase {
    if (_simulator.status == StatusSimulasi.selesai) {
      return VoltWarna.violet;
    }
    final String fase = _simulator.labelFase;
    if (fase == 'PEMASAN' || fase == 'STABIL') return VoltWarna.kuning;
    if (fase == 'SPRINT') return VoltWarna.hijau;
    return VoltWarna.aksen;
  }

  /// Widget statistik kecil: label besar di atas, nilai di bawah.
  Widget _StatistikBox({
    required String label,
    required String nilai,
    required String satuan,
  }) {
    return Column(
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            color: VoltWarna.teksRedup,
            letterSpacing: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              nilai,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: VoltWarna.teksPutih,
              ),
            ),
            if (satuan.isNotEmpty)
              Text(
                satuan,
                style: const TextStyle(
                  fontSize: 11,
                  color: VoltWarna.teksAbu,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Baris detail label: nilai.
  Widget _BarisDetail(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(
                color: VoltWarna.teksPutih,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Panel informasi akurasi GPS.
  ///
  /// Widget ini menunjukkan data yang hanya bisa ada kalau
  /// pemrosesan GPS memakai filter: jumlah titik diterima, ditolak,
  /// dan rasio penerimaan.
  Widget _PanelAkurasiGps({required PelacakLari pelacak}) {
    final int total = pelacak.titikDiterima + pelacak.titikDitolak;
    final double rasio = total == 0 ? 0 : pelacak.titikDiterima / total * 100;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VoltWarna.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.filter_alt, color: VoltWarna.teksAbu, size: 16),
              const SizedBox(width: 8),
              Text(
                'AKURASI GPS: ${rasio.toStringAsFixed(0)}% Clean',
                style: const TextStyle(
                  fontSize: 10,
                  color: VoltWarna.teksAbu,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Diterima: ${pelacak.titikDiterima} titik | '
            'Ditolak: ${pelacak.titikDitolak} titik | '
            'Kalman filter aktif',
            style: const TextStyle(fontSize: 10, color: VoltWarna.teksRedup),
          ),
        ],
      ),
    );
  }

  /// Nama hari dari angka (1 = Senin sampai 7 = Minggu).
  static String _namaHari(int hari) {
    const List<String> nama = <String>[
      'Sen',
      'Sel',
      'Rab',
      'Kam',
      'Jum',
      'Sab',
      'Min',
    ];
    if (hari < 1 || hari > 7) return '-';
    return nama[hari - 1];
  }

  /// Format durasi detik menjadi HH:MM:SS atau MM:SS.
  static String _fmtDurasi(int detik) {
    final int jam = detik ~/ 3600;
    final int menit = (detik % 3600) ~/ 60;
    final int dtk = detik % 60;

    if (jam > 0) {
      return '$jam:${menit.toString().padLeft(2, '0')}:'
          '${dtk.toString().padLeft(2, '0')}';
    }
    return '$menit:${dtk.toString().padLeft(2, '0')}';
  }
}
