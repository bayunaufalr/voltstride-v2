import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/volt_theme.dart';
import '../features/running/services/running_notification_service.dart';

// Stopwatch jadi patokan waktu; timer cuma buat refresh UI.

class TimerPage extends StatefulWidget {
  const TimerPage({super.key});

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> {
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

  final Stopwatch _sw = Stopwatch();

  Timer? _timer;

  String _fase = 'siap';

  int _sisaDetik = 0;

  int _rondeSekarang = 0;

  int _totalRonde = 6;
  bool _paused = false;

  static const int durasiHitungMundur = 3;

  void _mulaiSesi() {
    final int durasi = int.tryParse(_cDurasiRonde.text) ?? 180;
    final int jumlah = int.tryParse(_cJumlahRonde.text) ?? 6;

    _totalRonde = jumlah.clamp(1, 99);
    _rondeSekarang = 0;
    _paused = false;
    _sisaDetik = durasi.clamp(5, 3600);

    _sw.reset();
    _sw.start();

    _fase = 'jeda';
    _durasiFase = durasiHitungMundur;
    _waktuMulaiFase = 0;
    _sisaDetik = durasiHitungMundur;

    _timer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      _tick,
    );

    HapticFeedback.mediumImpact();
    setState(() {});
    _notifyTimerState(ongoing: true);
  }

  void _hentiSesi() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
    _fase = 'siap';
    _sisaDetik = 0;
    _rondeSekarang = 0;
    _paused = false;
    HapticFeedback.mediumImpact();
    setState(() {});
    unawaited(RunningNotificationService.stopIntervalTimer());
  }

  void _tick(Timer _) {
    // Stopwatch yang menentukan waktu, bukan jumlah callback Timer.
    if (_fase == 'siap' || _fase == 'selesai' || _paused) return;

    final double sejakMulaiFase =
        _sw.elapsedMilliseconds / 1000.0 - _waktuMulaiFase;

    final int sisaBaru = (_durasiFase - sejakMulaiFase).ceil();

    if (sisaBaru == _sisaDetik) return;

    setState(() => _sisaDetik = sisaBaru < 0 ? 0 : sisaBaru);

    if (sisaBaru == 3) {
      HapticFeedback.selectionClick();
    }

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

  double _waktuMulaiFase = 0;

  int _durasiFase = 0;

  void _mulaiRonde() {
    _rondeSekarang++;
    _fase = 'ronde';

    _durasiFase =
        int.tryParse(_cDurasiRonde.text)?.clamp(5, 3600) ?? 180;

    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = _durasiFase;

    HapticFeedback.heavyImpact();
    setState(() {});
    _notifyTimerState(ongoing: true);
  }

  void _selesaiRonde() {
    if (_rondeSekarang >= _totalRonde) {
      _selesaiSesi();
      return;
    }

    _fase = 'istirahat';
    _durasiFase =
        int.tryParse(_cIstirahat.text)?.clamp(0, 1800) ?? 60;

    if (_durasiFase <= 0) {
      _mulaiRonde();
      return;
    }

    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = _durasiFase;

    HapticFeedback.lightImpact();
    setState(() {});
    _notifyTimerState(ongoing: true);
  }

  void _selesaiIstirahat() {
    _fase = 'jeda';
    _durasiFase = durasiHitungMundur;
    _waktuMulaiFase =
        _sw.elapsedMilliseconds / 1000.0;
    _sisaDetik = durasiHitungMundur;
    setState(() {});
    _notifyTimerState(ongoing: true);
  }

  void _selesaiSesi() {
    _timer?.cancel();
    _timer = null;
    _sw.stop();
    _fase = 'selesai';
    _sisaDetik = 0;

    HapticFeedback.heavyImpact();
    setState(() {});
    _notifyTimerState(ongoing: false);
  }

  Future<void> _notifyTimerState({required bool ongoing}) async {
    final String phase = _labelFase;
    final String detail;
    if (_fase == 'ronde') {
      detail = 'Ronde $_rondeSekarang/$_totalRonde · ${_fmtMenitDetik(_sisaDetik)} tersisa';
    } else if (_fase == 'istirahat') {
      detail = 'Pemulihan · ${_fmtMenitDetik(_sisaDetik)} tersisa';
    } else if (_fase == 'jeda') {
      detail = 'Bersiap · ${_fmtMenitDetik(_sisaDetik)}';
    } else {
      detail = '$_totalRonde ronde selesai';
    }
    try {
      await RunningNotificationService.showIntervalTimerState(
        title: 'VoltStride · $phase',
        body: detail,
        ongoing: ongoing,
      );
    } catch (_) {
      // Timer di layar tetap berfungsi walau Android menolak notifikasi.
    }
  }

  void _pauseResume() {
    if (_fase == 'siap' || _fase == 'selesai') return;
    if (_paused) {
      _sw.start();
      _paused = false;
    } else {
      _sw.stop();
      _paused = true;
    }
    HapticFeedback.selectionClick();
    setState(() {});
    _notifyTimerState(ongoing: true);
  }

  void _skipPhase() {
    if (_fase == 'siap' || _fase == 'selesai' || _paused) return;
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
                  Text(
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
                      style: TextStyle(
                        color: VoltWarna.aksen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                child: AnimatedContainer(
                  duration:
                      const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  decoration: BoxDecoration(
                    color: _warnaFase,
                    borderRadius:
                        BorderRadius.zero,

                    boxShadow: aktif
                        ? [
                            BoxShadow(
                              color: _warnaFase
                                  .withValues(alpha: 0.35),
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

                        SizedBox(
                          width: 200,
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.zero,
                            child: LinearProgressIndicator(
                              value: _progresFase,
                              minHeight: 6,
                              backgroundColor:
                                  VoltWarna.latar
                                      .withValues(alpha: 0.15),
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

                  if (aktif) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pauseResume,
                            icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                            label: Text(_paused ? 'Lanjutkan' : 'Jeda'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _skipPhase,
                            icon: const Icon(Icons.skip_next_rounded),
                            label: const Text('Lewati'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _hentiSesi,
                            icon: const Icon(Icons.stop),
                            label: const Text('Henti'),
                            style: FilledButton.styleFrom(
                              backgroundColor: VoltWarna.merah,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: _mulaiSesi,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Mulai Sesi'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  double get _progresFase {
    if (_durasiFase <= 0) return 0;

    final double sejak =
        _sw.elapsedMilliseconds / 1000.0 -
            _waktuMulaiFase;

    return (sejak / _durasiFase).clamp(0.0, 1.0);
  }

  static String _fmtMenitDetik(int detik) {
    final int menit = detik ~/ 60;
    final int sisa = detik % 60;

    return '$menit:${sisa.toString().padLeft(2, '0')}';
  }
}

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
      style: TextStyle(
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