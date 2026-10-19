import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  const AccountPage({super.key});

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
    if (session.activityType == RunActivityType.walk) return 12;
    if (session.intervalPlan != null || session.distanceKm >= 10) return 36;
    if (session.distanceKm >= 5) return 24;
    return 18;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anda')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _accountCard(),
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
            color: VoltWarna.kartu,
            borderRadius: BorderRadius.zero,
            border: Border.all(color: VoltWarna.border),
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
                          style: const TextStyle(color: VoltWarna.teksAbu),
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
      // file_picker versi 12 mengembalikan satu PlatformFile secara langsung.
      // Jika pengguna membatalkan pemilihan, hasilnya bernilai null.
      final PlatformFile? hasil = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (hasil == null) return;

      // Baca isi gambar setelah pengguna memilih berkas.
      final Uint8List bytes = await hasil.readAsBytes();
      if (bytes.isEmpty) {
        _tampilkanPesan('Foto tidak dapat dibaca. Coba pilih gambar lain.');
        return;
      }

      final img.Image? gambarAsli = img.decodeImage(bytes);
      if (gambarAsli == null) {
        _tampilkanPesan('File tersebut bukan gambar yang dapat dibuka.');
        return;
      }

      final img.Image fotoKecil = img.copyResizeCropSquare(
        gambarAsli,
        size: 256,
      );
      final List<int> fotoJpg = img.encodeJpg(fotoKecil, quality: 70);
      if (fotoJpg.length > 650 * 1024) {
        _tampilkanPesan('Ukuran foto masih terlalu besar. Pilih foto lain.');
        return;
      }

      await AccountService.perbaruiFotoProfil(base64Encode(fotoJpg));
      _tampilkanPesan('Foto profil diperbarui.');
    } catch (_) {
      _tampilkanPesan('Foto profil belum berhasil diperbarui. Periksa koneksi.');
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
        color: VoltWarna.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: VoltWarna.border),
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
            style: const TextStyle(color: VoltWarna.teksAbu, height: 1.45),
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
        color: VoltWarna.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: VoltWarna.border),
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
          const Text(
            'Ini hanya perkiraan, bukan penilaian medis. Jika masih merasa lelah, tunda latihan.',
            style: TextStyle(
              color: VoltWarna.teksAbu,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
