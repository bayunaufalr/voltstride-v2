import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/volt_theme.dart';

/// ============================================================
/// TIMER PAGE: INTERVAL ROUND TIMER
/// ============================================================
/// Interval round timer untuk latihan tinju dan agility.
///
/// Dua komponen waktu yang dipakai bersamaan dan punya tugas berbeda:
///
///   - `Stopwatch` adalah sumber kebenaran waktu. Ia menghitung
///     milidetik nyata sejak ronde dimulai, tidak terpengaruh callback
///     timer yang ditunda oleh sistem operasi.
///
///   - `Timer.periodic(200ms)` hanya membangunkan UI supaya angka
///     di layar ikut turun setiap 200 milidetik. Ia TIDAK menghitung
///     waktu sendiri.
///
/// Kenapa tidak cukup pakai satu timer saja?
/// Karena `Timer.periodic` bisa terlambat. Kalau Android sedang sibuk
/// memuat aplikasi lain, callback bisa tertunda 300 sampai 800 milidetik.
/// Kalau waktu dihitung dari `tick * 0.2`, timer 3 menit bisa meleset
/// 10 sampai 20 detik di akhir sesi. Dengan menghitung waktu dari
/// Stopwatch setiap kali UI di-refresh, angka di layar selalu sama
/// dengan waktu nyata.
///
/// Getaran fisik memakai `HapticFeedback` supaya pengguna bisa tahu
/// fase berganti tanpa harus melihat layar. Ini penting untuk latihan
/// tinju dan agility, di mana kepala tidak boleh menatap layar.
class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
  // ------------------------------------------------------------
  // CONTROLLER INPUT
  // ------------------------------------------------------------

  final TextEditingController _cDurasiRonde =
      TextEditingController(text: '180');
  final TextEditingController _cIstirahat =
      TextEditingController(text: '60');
  final TextEditingController _cJumlahRonde =
      TextEditingController(text: '6');

  @override
  void dispose() {
    _cDurasiRonde.dispose();
    _cIstirahat.dispose();
    _cJumlahRonde.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------
  // STATE TIMER
  // ------------------------------------------------------------

  /// Sumber kebenaran waktu untuk fase yang sedang berjalan.
  final Stopwatch _sw = Stopwatch();

  /// Timer pemicu pembaruan UI.
  Timer? _timer;

  /// Fase sesi saat ini.
  ///
  /// Siklusnya:
  ///   siap -> jeda -> ronde -> istirahat -> ronde -> ... -> selesai
  ///
  /// `jeda` dipakai untuk hitung mundur sebelum ronde dimulai dan
  /// setelah ronde selesai, jadi transisi tidak terasa mendadak.
  String _fase = 'siap';

  /// Detik tersisa di fase sekarang.
  ///
  /// Angka ini TIDAK dihitung dengan mengurangi satu per tick. Nilai ini
  /// dihitung dari selisih Stopwatch terhadap durasi fase, jadi tetap
  /// benar walau tick terlambat.
  int _sisaDetik = 0;

  /// Ronde yang sedang berjalan, mulai dari 1.
  int _rondeSekarang = 0;

  /// Total ronde yang harus diselesaikan.
  int _totalRonde = 6;

  /// Lama hitung mundur sebelum ronde dimulai, dalam detik.
  ///
  /// 3 detik memberi waktu pelari untuk positioning sebelum ronde.
  /// Nilai ini jadi konstanta, bukan state, karena selalu sama di
  /// setiap sesi. Yang berubah per sesi adalah durasi ronde dan
  /// istirahat yang dibaca dari form.
  static const int durasiHitungMundur = 3;

  // ------------------------------------------------------------
  // KONTROL
  // ------------------------------------------------------------

  /// Membaca input form dengan nilai default yang aman.
  ///
  /// clamp dipakai supaya nilai aneh seperti 0 atau negatif tidak
  /// bisa merusak perhitungan waktu.
  void _mulaiSesi() {
    final int durasi = int.tryParse(_cDurasiRonde.text) ?? 180;
    final int jumlah = int.tryParse(_cJumlahRonde.text) ?? 6;

    // Dijepit ke rentang yang masuk akal.
    _totalRonde = jumlah.clamp(1, 99);
    _rondeSekarang = 0;
    _sisaDetik = durasi.clamp(5, 3600);

    // Reset stopwatch supaya waktu mulai dari nol.
    _sw.reset();
    _sw.start();

    // Mulai dari hitung mundur, bukan langsung ronde, supaya pelari
    // sempat mengambil posisi.
    _fase = 'jeda';
    _durasiFase = durasiHitungMundur;
    _waktuMulaiFase = 0;
    _sisaDetik = durasiHitungMundur;

    // Mulai timer UI.
    _timer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      _tick,
    );

    // Getaran tanda mulai.
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  /// Menghentikan sesi sepenuhnya.
  void _hentiSesi() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
    _fase = 'siap';
    _sisaDetik = 0;
    _rondeSekarang = 0;
    HapticFeedback.mediumImpact();
    setState(() {});
  }

  /// Satu siklus pemeriksaan, dipanggil setiap 200 milidetik.
  ///
  /// Prinsipnya satu kalimat: sisa waktu dihitung dari selisih
  /// Stopwatch terhadap waktu mulai fase, bukan dari pengurangan satu
  /// per tick. Itulah yang membuat timer tidak meleset meski sistem
  /// operasi menunda callback.
  void _tick(Timer _) {
    // Sesi yang belum mulai atau sudah selesai tidak dihitung.
    if (_fase == 'siap' || _fase == 'selesai') return;

    // Waktu yang sudah berjalan di fase ini, dalam detik desimal.
    final double sejakMulaiFase =
        _sw.elapsedMilliseconds / 1000.0 - _waktuMulaiFase;

    // Sisa waktu fase. ceil() dipakai supaya angka di layar tetap
    // benar: pada 0,9 detik tersisa, layar masih menampilkan 1.
    final int sisaBaru = (_durasiFase - sejakMulaiFase).ceil();

    // Kalau detik belum berubah, tidak ada yang perlu dibangun ulang.
    // Pemeriksaan ini menghemat sebagian besar build yang sia-sia.
    if (sisaBaru == _sisaDetik) return;

    setState(() => _sisaDetik = sisaBaru < 0 ? 0 : sisaBaru);

    // Getaran countdown tiga detik terakhir.
    if (sisaBaru == 3) {
      HapticFeedback.selectionClick();
    }

    // Fase sudah habis? Lanjut ke fase berikutnya.
    if (sisaBaru <= 0) {
      switch (_fase) {
        case 'jeda':
          _mulaiRonde();
          break;
        case 'ronde':
          _selesaiRonde();
          break;
        case 'istirahat':
          _selesaiIstirahat();
          break;
      }
    }
  }

  // ------------------------------------------------------------
  // TRANSISI FASE
  // ------------------------------------------------------------

  /// Waktu dalam detik saat fase sekarang dimulai.
  ///
  /// Disimpan setiap kali fase berganti. Semua perhitungan sisa waktu
  /// memakai nilai ini sebagai acuan, sehingga tidak ada akumulasi
  /// error dari pengurangan berulang.
  double _waktuMulaiFase = 0;

  /// Durasi fase sekarang dalam detik.
  int _durasiFase = 0;

  /// Memulai satu ronde.
  void _mulaiRonde() {
    _rondeSekarang++;
    _fase = 'ronde';

    // Durasi ronde dari input form.
    _durasiFase =
        int.tryParse(_cDurasiRonde.text)?.clamp(5, 3600) ?? 180;

    // Acuan waktu fase ini.
    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = _durasiFase;

    // Getaran kuat: ronde dimulai.
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  /// Ronde selesai: pindah ke istirahat, atau ke selesai kalau ini
  /// ronde terakhir.
  void _selesaiRonde() {
    if (_rondeSekarang >= _totalRonde) {
      _selesaiSesi();
      return;
    }

    // Masuk fase istirahat.
    _fase = 'istirahat';
    _durasiFase =
        int.tryParse(_cIstirahat.text)?.clamp(0, 1800) ?? 60;

    // Kalau istirahat 0, langsung ke ronde berikutnya.
    if (_durasiFase <= 0) {
      _mulaiRonde();
      return;
    }

    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = _durasiFase;

    // Getaran ringan: sekarang istirahat.
    HapticFeedback.lightImpact();
    setState(() {});
  }

  /// Istirahat selesai: lanjut ronde berikutnya.
  void _selesaiIstirahat() {
    // Hitung mundur singkat sebelum ronde berikutnya.
    _fase = 'jeda';
    _durasiFase = durasiHitungMundur;
    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = durasiHitungMundur;
    setState(() {});
  }

  /// Sesi selesai sepenuhnya.
  void _selesaiSesi() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
    _fase = 'selesai';
    _sisaDetik = 0;

    // Getaran sangat berat: sesi khatam.
    HapticFeedback.heavyImpact();
    setState(() {});
  }

  // ------------------------------------------------------------
  // WARNA FASE
  // ------------------------------------------------------------

  /// Warna layar sesuai fase.
  ///
  /// Hijau saat ronde, kuning saat istirahat, violet saat selesai.
  /// Warna ini yang paling penting secara visual, jadi dipakai untuk
  /// [AnimatedContainer] yang berubah ukuran dan warna bersamaan.
  Color get _warnaFase {
    switch (_fase) {
      case 'ronde':
        return VoltWarna.hijau;
      case 'istirahat':
        return VoltWarna.kuning;
      case 'selesai':
        return VoltWarna.violet;
      case 'jeda':
        return VoltWarna.aksen;
      default:
        return VoltWarna.kartu;
    }
  }

  /// Label fase untuk ditampilkan.
  String get _labelFase {
    switch (_fase) {
      case 'ronde':
        return 'RONDE';
      case 'istirahat':
        return 'ISTIRAHAT';
      case 'jeda':
        return 'BERSIAP';
      case 'selesai':
        return 'SELESAI';
      default:
        return 'SIAP';
    }
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final bool aktif =
        _fase != 'siap' && _fase != 'selesai';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  const Text(
                    'INTERVAL ROUND TIMER',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: VoltWarna.teksPutih,
                      letterSpacing: 1,
                    ),
                  ),
                  const Spacer(),
                  if (aktif)
                    Text(
                      'Ronde $_rondeSekarang / $_totalRonde',
                      style: const TextStyle(
                        color: VoltWarna.aksen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),

            // --- Layar timer dengan warna yang berubah ---
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedContainer(
                  // Durasi animasi 400ms untuk perubahan warna yang
                  // smooth tapi tetap terasa responsif.
                  duration:
                      const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: _warnaFase,
                    borderRadius:
                        BorderRadius.circular(24),

                    // Glow lembut saat timer aktif.
                    boxShadow: aktif
                        ? [
                            BoxShadow(
                              color: _warnaFase
                                  .withOpacity(0.35),
                              blurRadius: 40,
                              spreadRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _labelFase,
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w800,
                            color:
                                _warnaFase ==
                                        VoltWarna.kartu
                                    ? VoltWarna.teksAbu
                                    : VoltWarna.latar,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Angka waktu. Format mm:ss.
                        Text(
                          _fmtMenitDetik(_sisaDetik),
                          style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            color:
                                _warnaFase ==
                                        VoltWarna.kartu
                                    ? VoltWarna.teksPutih
                                    : VoltWarna.latar,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Progress bar fase, dihitung dari durasi fase.
                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _progresFase,
                              minHeight: 6,
                              backgroundColor:
                                  VoltWarna.latar
                                      .withOpacity(0.15),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                _warnaFase ==
                                        VoltWarna.kartu
                                    ? VoltWarna.aksen
                                    : VoltWarna.latar,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // --- Input durasi ---
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _InputDurasi(
                          controller: _cDurasiRonde,
                          label: 'Durasi Ronde',
                          satuan: 'detik',
                          ikon: Icons.timer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InputDurasi(
                          controller: _cIstirahat,
                          label: 'Istirahat',
                          satuan: 'detik',
                          ikon: Icons.self_improvement,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _InputDurasi(
                          controller: _cJumlahRonde,
                          label: 'Jumlah Ronde',
                          satuan: 'ronde',
                          ikon: Icons.repeat,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Tombol mulai atau henti.
                  FilledButton.icon(
                    onPressed:
                        aktif ? _hentiSesi : _mulaiSesi,
                    icon: Icon(
                      aktif
                          ? Icons.stop
                          : Icons.play_arrow,
                    ),
                    label: Text(
                      aktif ? 'Henti' : 'Mulai Sesi',
                    ),
                    style: aktif
                        ? FilledButton.styleFrom(
                            backgroundColor:
                                VoltWarna.merah,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Progres fase dari 0 sampai 1.
  ///
  /// Dihitung dari waktu yang sudah berjalan dibagi durasi fase, bukan
  /// dari `_sisaDetik`, karena yang latter sudah di-round ke bilangan
  /// bulat dan akan terlihat tersendat.
  double get _progresFase {
    if (_durasiFase <= 0) return 0;

    final double sejak =
        _sw.elapsedMilliseconds / 1000.0 -
            _waktuMulaiFase;

    return (sejak / _durasiFase).clamp(0.0, 1.0);
  }

  /// Format detik menjadi mm:ss.
  static String _fmtMenitDetik(int detik) {
    final int menit = detik ~/ 60;
    final int sisa = detik % 60;

    return '$menit:${sisa.toString().padLeft(2, '0')}';
  }
}

/// Widget input durasi yang dipakai berulang di form timer.
class _InputDurasi extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String satuan;
  final IconData ikon;

  const _InputDurasi({
    required this.controller,
    required this.label,
    required this.satuan,
    required this.ikon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(
        color: VoltWarna.teksPutih,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        suffixText: satuan,
        prefixIcon: Icon(
          ikon,
          size: 20,
        ),
        isDense: true,
      ),
    );
  }
}