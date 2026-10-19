import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../theme/volt_theme.dart';
import '../running/models/run_session.dart';
import '../running/services/run_history_repository.dart';
import 'account_service.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.onOpenProgress});

  final VoidCallback onOpenProgress;

  @override
  State<AccountPage> createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage> {
  RunSession? _latestSession;
  DateTime? _recommendedResumeAt;
  bool _loading = true;
  bool _movingLegacyHistory = false;
  int _legacyHistoryCount = 0;

  @override
  void initState() {
    super.initState();
    _loadRecovery();
  }

  Future<void> reload() => _loadRecovery();

  Future<void> _loadRecovery() async {
    try {
      final List<RunSession> sessions = await RunHistoryRepository.instance.getAll(limit: 1);
      final int legacyCount = await RunHistoryRepository.instance.pendingSessionCount();
      if (!mounted) return;
      if (sessions.isEmpty) {
        setState(() {
          _latestSession = null;
          _recommendedResumeAt = null;
          _legacyHistoryCount = legacyCount;
          _loading = false;
        });
        return;
      }
      final RunSession session = sessions.first;
      final int hours = _suggestedRestHours(session);
      final DateTime activityEnd = (session.finishedAt ?? session.startedAt).toLocal();
      setState(() {
        _latestSession = session;
        _recommendedResumeAt = activityEnd.add(Duration(hours: hours));
        _legacyHistoryCount = legacyCount;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _suggestedRestHours(RunSession session) {
    final double jarakKm = session.distanceKm;
    final Duration durasiAktif = session.movingTime > Duration.zero
        ? session.movingTime
        : session.elapsed;
    final double durasiJam = durasiAktif.inMinutes / 60.0;
    final RunElevationStats dataElevasi = session.elevationStats;
    final double elevasiNaik =
        dataElevasi.hasAltitudeData ? dataElevasi.totalAscentMeters : 0;
    final double elevasiTurun =
        dataElevasi.hasAltitudeData ? dataElevasi.totalDescentMeters : 0;

    // Perkiraan memakai jarak, waktu bergerak, elevasi, dan latihan interval.
    // Tanpa denyut jantung, tidur, atau rasa lelah pengguna, hasilnya tetap
    // perkiraan umum dan bukan ukuran pemulihan tubuh yang pasti.
    double jamIstirahat;
    if (session.activityType == RunActivityType.walk) {
      jamIstirahat = 6 + (jarakKm * 0.55) + (durasiJam * 1.5);
    } else {
      jamIstirahat = 8 + (jarakKm * 0.9);
      jamIstirahat += math.max(0, durasiJam - 0.5) * 2.0;
      jamIstirahat += (elevasiNaik / 100) * 1.5;
      jamIstirahat += (elevasiTurun / 150) * 0.75;

      if (session.intervalPlan != null) jamIstirahat += 6;
      if (jarakKm >= 21.097) {
        jamIstirahat += 12;
      } else if (jarakKm >= 10) {
        jamIstirahat += 6;
      } else if (jarakKm >= 5) {
        jamIstirahat += 3;
      }

      if (jarakKm > 0) {
        final double paceMenitPerKm = durasiAktif.inSeconds / 60 / jarakKm;
        if (paceMenitPerKm < 5.25 && jarakKm >= 5) {
          jamIstirahat += 3;
        } else if (paceMenitPerKm < 6 && jarakKm >= 5) {
          jamIstirahat += 1.5;
        }
      }
    }

    return jamIstirahat.round().clamp(6, 72).toInt();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anda')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _accountCard(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onOpenProgress,
            icon: const Icon(Icons.show_chart_rounded),
            label: const Text('Kemajuan dan pencapaian'),
          ),
          const SizedBox(height: 12),
          _themeCard(),
          if (_legacyHistoryCount > 0) ...<Widget>[
            const SizedBox(height: 14),
            _legacyHistoryCard(),
          ],
          const SizedBox(height: 14),
          _RecoveryCountdownCard(
            recommendedResumeAt: _recommendedResumeAt,
            loading: _loading,
            hasActivity: _latestSession != null,
          ),
        ],
      ),
    );
  }

  Widget _themeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Tampilan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: voltThemeModeNotifier,
            builder: (BuildContext context, ThemeMode mode, Widget? child) {
              return DropdownButtonFormField<ThemeMode>(
                value: mode,
                decoration: const InputDecoration(labelText: 'Tema aplikasi'),
                items: const <DropdownMenuItem<ThemeMode>>[
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Text('Ikuti perangkat'),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Text('Terang'),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Text('Gelap'),
                  ),
                ],
                onChanged: (ThemeMode? pilihan) {
                  if (pilihan != null) {
                    unawaited(saveVoltThemeMode(pilihan));
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final User? pengguna = AccountService.akunAktif;
    final String nama = pengguna?.displayName?.trim().isNotEmpty == true
        ? pengguna!.displayName!.trim()
        : 'Pengguna';
    final String email = pengguna?.email ?? 'Email tidak tersedia';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AccountService.perubahanProfil,
      builder: (BuildContext context, AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        final Map<String, dynamic> profil =
            snapshot.data?.data() ?? <String, dynamic>{};
        final String fotoBase64 =
            profil['fotoProfilBase64'] as String? ?? '';
        final ImageProvider<Object>? foto = fotoBase64.isEmpty
            ? null
            : _fotoDariBase64(fotoBase64);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: VoltWarna.surface,
                    backgroundImage: foto,
                    child: foto == null
                        ? const Icon(Icons.person_outline, size: 34)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          nama,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: TextStyle(color: Theme.of(context).hintColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _memilihFotoProfil,
                      child: const Text('Ubah foto profil'),
                    ),
                  ),
                  if (fotoBase64.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _hapusFotoProfil,
                      child: const Text('Hapus'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _konfirmasiKeluar,
                child: const Text('Keluar dari akun'),
              ),
            ],
          ),
        );
      },
    );
  }

  ImageProvider<Object>? _fotoDariBase64(String nilai) {
    try {
      return MemoryImage(base64Decode(nilai));
    } catch (_) {
      return null;
    }
  }

  Future<void> _memilihFotoProfil() async {
    try {
      final PlatformFile? hasil = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (hasil == null) return;

      final Uint8List bytes = await hasil.readAsBytes();
      if (bytes.isEmpty) {
        _tampilkanPesan('Foto tidak dapat dibaca. Pilih gambar lain.');
        return;
      }

      img.Image? gambarAsli = img.decodeImage(bytes);
      if (gambarAsli == null) {
        _tampilkanPesan('File tersebut bukan gambar yang dapat dibuka.');
        return;
      }

      // Perkecil gambar berukuran sangat besar sebelum membuka alat potong,
      // agar penyuntingan tetap ringan di ponsel.
      final int sisiTerbesar = math.max(gambarAsli.width, gambarAsli.height);
      if (sisiTerbesar > 1200) {
        final double skala = 1200 / sisiTerbesar;
        gambarAsli = img.copyResize(
          gambarAsli,
          width: (gambarAsli.width * skala).round(),
          height: (gambarAsli.height * skala).round(),
        );
      }

      if (!mounted) return;
      final Uint8List? fotoTerpotong = await showDialog<Uint8List>(
        context: context,
        builder: (BuildContext dialogContext) =>
            _CropFotoDialog(gambarAsli: gambarAsli!),
      );
      if (fotoTerpotong == null) return;

      if (fotoTerpotong.length > 650 * 1024) {
        _tampilkanPesan('Ukuran foto terlalu besar. Pilih foto yang lebih kecil.');
        return;
      }

      await AccountService.perbaruiFotoProfil(base64Encode(fotoTerpotong));
      _tampilkanPesan('Foto profil diperbarui.');
    } catch (_) {
      _tampilkanPesan(
        'Foto profil belum berhasil diperbarui. Coba pilih foto lain.',
      );
    }
  }

  Future<void> _hapusFotoProfil() async {
    try {
      await AccountService.hapusFotoProfil();
      _tampilkanPesan('Foto profil dihapus.');
    } catch (_) {
      _tampilkanPesan('Foto profil belum berhasil dihapus.');
    }
  }

  void _tampilkanPesan(String pesan) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(pesan)),
    );
  }

  Widget _legacyHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Aktivitas belum tersinkron',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '$_legacyHistoryCount aktivitas masih perlu dikirim ke akun.',
            style: TextStyle(color: Theme.of(context).hintColor, height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _movingLegacyHistory ? null : _sinkronkanAktivitas,
            icon: _movingLegacyHistory
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: VoltWarna.latar,
                    ),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _movingLegacyHistory
                  ? 'Memindahkan aktivitas...'
                  : 'Sinkronkan aktivitas',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _konfirmasiKeluar() async {
    final bool? keluar = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Data yang sudah tersimpan di akun tetap ada. Kamu perlu masuk lagi untuk membukanya.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (keluar != true) return;

    try {
      await AccountService.keluarAkun();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum berhasil keluar. Coba lagi.')),
      );
    }
  }

  Future<void> _sinkronkanAktivitas() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sinkronkan aktivitas ke akun?'),
        content: Text(
          '$_legacyHistoryCount aktivitas yang belum tersinkron akan dikirim ke akun ini. Data di perangkat hanya dibersihkan setelah penyimpanan akun berhasil.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sinkronkan sekarang'),
          ),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;

    setState(() => _movingLegacyHistory = true);
    try {
      final int jumlah =
          await RunHistoryRepository.instance.syncPendingSessionsToAccount();
      await _loadRecovery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            jumlah > 0
                ? '$jumlah aktivitas berhasil dipindahkan atau disinkronkan.'
                : 'Tidak ada data yang perlu dipindahkan.',
          ),
        ),
      );
    } catch (error) {
      await _loadRecovery();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Sebagian aktivitas belum tersinkron'),
          content: SingleChildScrollView(
            child: Text(error.toString()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _movingLegacyHistory = false);
    }
  }


}

/// Pemotong foto sederhana: pengguna dapat menggeser area kotak sebelum disimpan.
class _CropFotoDialog extends StatefulWidget {
  const _CropFotoDialog({required this.gambarAsli});

  final img.Image gambarAsli;

  @override
  State<_CropFotoDialog> createState() => _CropFotoDialogState();
}

class _CropFotoDialogState extends State<_CropFotoDialog> {
  late final int _sisiPotong;
  late final int _maksKiri;
  late final int _maksAtas;
  late double _kiri;
  late double _atas;

  @override
  void initState() {
    super.initState();
    _sisiPotong = math.min(
      widget.gambarAsli.width,
      widget.gambarAsli.height,
    );
    _maksKiri = widget.gambarAsli.width - _sisiPotong;
    _maksAtas = widget.gambarAsli.height - _sisiPotong;
    _kiri = _maksKiri / 2;
    _atas = _maksAtas / 2;
  }

  Uint8List _hasilPotongan() {
    final img.Image potongan = img.copyCrop(
      widget.gambarAsli,
      x: _kiri.round().clamp(0, _maksKiri).toInt(),
      y: _atas.round().clamp(0, _maksAtas).toInt(),
      width: _sisiPotong,
      height: _sisiPotong,
    );
    final img.Image ukuranProfil = img.copyResize(
      potongan,
      width: 256,
      height: 256,
    );
    return Uint8List.fromList(img.encodeJpg(ukuranProfil, quality: 78));
  }

  @override
  Widget build(BuildContext context) {
    final Uint8List preview = _hasilPotongan();
    return AlertDialog(
      title: const Text('Potong foto profil'),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(128),
                  child: Image.memory(
                    preview,
                    width: 210,
                    height: 210,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_maksKiri > 0) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Geser area ke kiri atau kanan'),
                ),
                Slider(
                  value: _kiri.clamp(0, _maksKiri).toDouble(),
                  min: 0,
                  max: _maksKiri.toDouble(),
                  onChanged: (double value) => setState(() => _kiri = value),
                ),
              ],
              if (_maksAtas > 0) ...<Widget>[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Geser area ke atas atau bawah'),
                ),
                Slider(
                  value: _atas.clamp(0, _maksAtas).toDouble(),
                  min: 0,
                  max: _maksAtas.toDouble(),
                  onChanged: (double value) => setState(() => _atas = value),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hasilPotongan()),
          child: const Text('Gunakan foto'),
        ),
      ],
    );
  }
}

/// Countdown terpisah agar pembaruannya tidak membangun ulang seluruh halaman akun.
class _RecoveryCountdownCard extends StatefulWidget {
  const _RecoveryCountdownCard({
    required this.recommendedResumeAt,
    required this.loading,
    required this.hasActivity,
  });

  final DateTime? recommendedResumeAt;
  final bool loading;
  final bool hasActivity;

  @override
  State<_RecoveryCountdownCard> createState() =>
      _RecoveryCountdownCardState();
}

class _RecoveryCountdownCardState extends State<_RecoveryCountdownCard> {
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _jadwalkanPembaruanDetik();
  }

  void _jadwalkanPembaruanDetik() {
    // Sejajarkan pembaruan dengan pergantian detik pada jam, lalu lanjutkan
    // setiap satu detik. Waktu tetap dihitung dari jam perangkat, bukan
    // sekadar mengurangi angka satu sehingga tidak melenceng saat UI sibuk.
    final DateTime sekarang = DateTime.now();
    final int milidetikKeDetikBerikutnya = 1000 - sekarang.millisecond;
    _timer = Timer(Duration(milliseconds: milidetikKeDetikBerikutnya), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _now = DateTime.now());
      });
    });
  }

  @override
  void didUpdateWidget(covariant _RecoveryCountdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendedResumeAt != widget.recommendedResumeAt ||
        oldWidget.loading != widget.loading ||
        oldWidget.hasActivity != widget.hasActivity) {
      _now = DateTime.now();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _teksHitungMundur(Duration remaining) {
    final int seconds = remaining.inSeconds.clamp(0, 999999999).toInt();
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    if (hours >= 24) {
      final int days = hours ~/ 24;
      return '$days hari ${hours % 24} jam '
          '${minutes.toString().padLeft(2, '0')} menit '
          '${secs.toString().padLeft(2, '0')} detik';
    }
    return '$hours jam ${minutes.toString().padLeft(2, '0')} menit '
        '${secs.toString().padLeft(2, '0')} detik';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? batasPemulihan = widget.recommendedResumeAt;
    final Duration? remaining = batasPemulihan?.difference(_now);
    final bool sudahLewat = remaining != null && remaining.isNegative;

    final String status;
    if (widget.loading) {
      status = 'Menghitung waktu istirahat…';
    } else if (!widget.hasActivity || remaining == null) {
      status = 'Belum ada aktivitas.';
    } else if (sudahLewat) {
      status = 'Waktu istirahat yang disarankan sudah lewat.';
    } else {
      status = _teksHitungMundur(remaining);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Pemulihan',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Text(
            status,
            style: TextStyle(
              fontSize: remaining != null && !sudahLewat ? 22 : 13,
              fontWeight: FontWeight.w900,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ini hanya perkiraan saja, bukan penilaian medis. Jika masih merasa lelah, tunda latihan.',
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
