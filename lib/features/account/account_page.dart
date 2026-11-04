// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
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
import '../progress/progress_page.dart';
import '../running/run_history_page.dart';
import '../reminders/training_reminders_page.dart';
import '../../services/app_language_service.dart';
import 'profile_training_summary.dart';
import 'account_service.dart';
import 'privacy_policy_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => AccountPageState();
}

class AccountPageState extends State<AccountPage>
    with SingleTickerProviderStateMixin {
  RunSession? _latestSession;
  DateTime? _recommendedResumeAt;
  bool _loading = true;
  bool _movingLegacyHistory = false;
  bool _showProfilePage = false;
  int _legacyHistoryCount = 0;
  bool _cloudStorageAvailable = false;
  bool _cloudSignedIn = false;
  int _cloudSessionCount = 0;
  int _cloudEstimatedBytes = 0;
  int _cloudLargestDocumentBytes = 0;
  int _cloudMaximumDocumentBytes = 1024 * 1024;
  late final TabController _sectionController;
  final GlobalKey<ProgressPageState> _progressKey =
      GlobalKey<ProgressPageState>();
  final GlobalKey<RunHistoryPageState> _historyKey =
      GlobalKey<RunHistoryPageState>();
  final GlobalKey<TrainingRemindersPageState> _remindersKey =
      GlobalKey<TrainingRemindersPageState>();

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  void initState() {
    super.initState();
    _sectionController = TabController(length: 3, vsync: this);
    _loadRecovery();
  }

  void openSection(int index) {
    if (index == 3) {
      setState(() => _showProfilePage = true);
      return;
    }
    if (index < 0 || index >= _sectionController.length) return;
    setState(() => _showProfilePage = false);
    _sectionController.animateTo(index);
  }

  Future<void> reload() async {
    await _loadRecovery();
    final ProgressPageState? progress = _progressKey.currentState;
    final RunHistoryPageState? history = _historyKey.currentState;
    final TrainingRemindersPageState? reminders = _remindersKey.currentState;
    if (progress != null) await progress.reload();
    if (history != null) await history.reload();
    if (reminders != null) await reminders.reload();
  }

  @override
  void dispose() {
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _loadRecovery() async {
    try {
      final RunHistoryRepository repository = RunHistoryRepository.instance;
      final List<dynamic> loaded = await Future.wait<dynamic>(<Future<dynamic>>[
        repository.getAll(limit: 200),
        repository.pendingSessionCount(),
        repository.cloudStorageSummary(),
      ]);
      final List<RunSession> sessions = loaded[0] as List<RunSession>;
      final int pendingCount = loaded[1] as int;
      final Map<String, Object?> cloud =
          loaded[2] as Map<String, Object?>;
      if (!mounted) return;

      final RunSession? session = sessions.isEmpty ? null : sessions.first;
      final DateTime? resumeAt = session == null
          ? null
          : (session.finishedAt ?? session.startedAt)
              .toLocal()
              .add(Duration(hours: _suggestedRestHours(session)));
      setState(() {
        _latestSession = session;
        _recommendedResumeAt = resumeAt;
        _legacyHistoryCount = pendingCount;
        _cloudSignedIn = cloud['signedIn'] == true;
        _cloudStorageAvailable = cloud['available'] == true;
        _cloudSessionCount = (cloud['sessionCount'] as num?)?.toInt() ?? 0;
        _cloudEstimatedBytes = (cloud['estimatedBytes'] as num?)?.toInt() ?? 0;
        _cloudLargestDocumentBytes =
            (cloud['largestDocumentBytes'] as num?)?.toInt() ?? 0;
        _cloudMaximumDocumentBytes =
            (cloud['maximumDocumentBytes'] as num?)?.toInt() ?? 1024 * 1024;
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
    final List<Tab> tabs = <Tab>[
      Tab(
        icon: const Icon(Icons.bar_chart_rounded),
        child: Text(
          AppLanguageService.text(context, 'Kemajuan', 'Progress'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Tab(
        icon: const Icon(Icons.history_rounded),
        child: Text(
          AppLanguageService.text(context, 'Aktivitas', 'Activities'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Tab(
        icon: const Icon(Icons.event_note_rounded),
        child: Text(
          AppLanguageService.text(context, 'Rencanakan latihan', 'Training plan'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ];

    final User? signedInUser = AccountService.akunAktif;
    final String profileTitle = signedInUser?.displayName?.trim().isNotEmpty == true
        ? signedInUser!.displayName!.trim()
        : _text('Profil saya', 'My profile');

    if (_showProfilePage) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop && mounted) setState(() => _showProfilePage = false);
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: _text('Kembali', 'Back'),
              onPressed: () => setState(() => _showProfilePage = false),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: Text(_text('Profil', 'Profile')),
          ),
          body: _profileTab(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(profileTitle),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: _text('Buka profil', 'Open profile'),
              onPressed: () => setState(() => _showProfilePage = true),
              icon: CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                backgroundImage: signedInUser?.photoURL?.isNotEmpty == true
                    ? NetworkImage(signedInUser!.photoURL!)
                    : null,
                child: signedInUser?.photoURL?.isNotEmpty == true
                    ? null
                    : Icon(
                        Icons.person_outline_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: TabBar(
            controller: _sectionController,
            isScrollable: false,
            tabAlignment: TabAlignment.fill,
            tabs: tabs,
          ),
        ),
      ),
      body: TabBarView(
        controller: _sectionController,
        children: <Widget>[
          ProgressPage(
            key: _progressKey,
            embedded: true,
            belowWeeklyChart: _recoveryCard(),
          ),
          RunHistoryPage(key: _historyKey, embedded: true),
          TrainingRemindersPage(key: _remindersKey, embedded: true),
        ],
      ),
    );
  }

  Widget _recoveryCard() => _RecoveryCountdownCard(
        recommendedResumeAt: _recommendedResumeAt,
        loading: _loading,
        hasActivity: _latestSession != null,
      );

  Widget _profileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _accountCard(),
        const SizedBox(height: 12),
        _cloudSyncStorageCard(),
        const SizedBox(height: 12),
        const ProfileTrainingSummary(),
        const SizedBox(height: 12),
        _themeCard(),
        const SizedBox(height: 12),
        const AppLanguageSettingCard(),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(_text('Kebijakan Privasi', 'Privacy Policy')),
            subtitle: Text(_text(
              'Cara VoltStride memproses dan menyimpan data.',
              'How VoltStride processes and stores data.',
            )),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => const PrivacyPolicyPage(),
                ),
              );
            },
          ),
        ),
        if (_legacyHistoryCount > 0) ...<Widget>[
          const SizedBox(height: 14),
          _legacyHistoryCard(),
        ],
      ],
    );
  }

  Widget _cloudSyncStorageCard() {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String status;
    final String detail;
    if (!_cloudSignedIn) {
      status = _text('Belum masuk akun', 'Not signed in');
      detail = _text(
        'Aktivitas hanya tersimpan di perangkat sampai Anda masuk dan menyinkronkannya.',
        'Activities remain on this device until you sign in and sync them.',
      );
    } else if (!_cloudStorageAvailable) {
      status = _text('Status cloud belum tersedia', 'Cloud status unavailable');
      detail = _text(
        'Periksa koneksi. Salinan lokal tetap digunakan dan tidak dihapus saat sinkronisasi gagal.',
        'Check your connection. Local copies remain available and are not deleted when sync fails.',
      );
    } else if (_legacyHistoryCount > 0) {
      status = _text('Menunggu sinkronisasi', 'Sync pending');
      detail = _text(
        '$_legacyHistoryCount aktivitas belum terkonfirmasi tersimpan di akun.',
        '$_legacyHistoryCount activities are not yet confirmed in your account.',
      );
    } else {
      status = _text('Tersinkron', 'Synced');
      detail = _text(
        'Aktivitas baru langsung dicoba sinkron saat disimpan. Aktivitas tertunda dicoba lagi saat riwayat dibuka atau ketika Anda menekan Sinkronkan sekarang.',
        'New activities are sent to your account when saved. Pending activities are retried when history is opened or when you select Sync now.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_sync_outlined, color: colors.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _text('Penyimpanan dan sinkronisasi', 'Storage and sync'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(status, style: TextStyle(fontWeight: FontWeight.w800, color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(detail, style: TextStyle(color: colors.onSurfaceVariant, height: 1.35)),
          if (_cloudSignedIn) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _text(
                'Salinan yang sudah tersimpan di akun tidak terhapus saat aplikasi dihapus atau data lokal dibersihkan. Aktivitas yang belum tersinkron masih hanya ada di perangkat.',
                'Activities already saved to your account remain there if the app is uninstalled or local app data is cleared. Unsynced activities still exist only on this device.',
              ),
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ],
          if (_cloudSignedIn && _cloudStorageAvailable) ...<Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: _storageValue(_text('Aktivitas di akun', 'Account activities'), '$_cloudSessionCount')),
                Expanded(child: _storageValue(_text('Perkiraan data cloud', 'Estimated cloud data'), _formatBytes(_cloudEstimatedBytes))),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _text(
                'Batas satu dokumen Firestore: ${_formatBytes(_cloudMaximumDocumentBytes)}. Pemakaian total proyek mengikuti kuota Firebase, bukan batas per akun.',
                'Firestore limit per document: ${_formatBytes(_cloudMaximumDocumentBytes)}. Total project usage follows Firebase quotas, not a per-account limit.',
              ),
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, height: 1.35),
            ),
            if (_cloudLargestDocumentBytes > 0)
              Text(
                _text(
                  'Aktivitas terbesar: ${_formatBytes(_cloudLargestDocumentBytes)}',
                  'Largest activity: ${_formatBytes(_cloudLargestDocumentBytes)}',
                ),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            _text(
              'Menghapus aplikasi tidak menghapus data yang sudah tersimpan di akun. Data yang belum tersinkron hanya ada di perangkat.',
              'Uninstalling the app does not delete data already stored in your account. Unsynced data exists only on this device.',
            ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11, height: 1.35),
          ),
          if (_cloudSignedIn && _legacyHistoryCount > 0) ...<Widget>[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _movingLegacyHistory ? null : _sinkronkanAktivitas,
              icon: const Icon(Icons.sync_rounded),
              label: Text(_text('Sinkronkan sekarang', 'Sync now')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _storageValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
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
          Text(
            AppLanguageService.text(context, 'Tampilan', 'Appearance'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: voltThemeModeNotifier,
            builder: (BuildContext context, ThemeMode mode, Widget? child) {
              return DropdownButtonFormField<ThemeMode>(
                initialValue: mode,
                decoration: InputDecoration(
                  labelText: AppLanguageService.text(
                    context,
                    'Tema aplikasi',
                    'App theme',
                  ),
                ),
                items: <DropdownMenuItem<ThemeMode>>[
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.system,
                    child: Text(AppLanguageService.text(
                      context,
                      'Ikuti perangkat',
                      'Follow device',
                    )),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.light,
                    child: Text(AppLanguageService.text(context, 'Terang', 'Light')),
                  ),
                  DropdownMenuItem<ThemeMode>(
                    value: ThemeMode.dark,
                    child: Text(AppLanguageService.text(context, 'Gelap', 'Dark')),
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
        : AppLanguageService.text(context, 'Pengguna', 'User');
    final String email = pengguna?.email ??
        AppLanguageService.text(context, 'Email tidak tersedia', 'Email unavailable');

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
                      child: Text(AppLanguageService.text(context, 'Ubah foto profil', 'Change profile photo')),
                    ),
                  ),
                  if (fotoBase64.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _hapusFotoProfil,
                      child: Text(AppLanguageService.text(context, 'Hapus', 'Remove')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _konfirmasiKeluar,
                child: Text(AppLanguageService.text(context, 'Keluar dari akun', 'Sign out')),
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
        _tampilkanPesan(_text('Foto tidak dapat dibaca. Pilih gambar lain.', 'The photo could not be read. Choose another image.'));
        return;
      }

      img.Image? gambarAsli = img.decodeImage(bytes);
      if (gambarAsli == null) {
        _tampilkanPesan(_text('File tersebut bukan gambar yang dapat dibuka.', 'This file is not a supported image.'));
        return;
      }
      // Ikuti arah asli foto dari kamera sebelum proses potong dibuka.
      gambarAsli = img.bakeOrientation(gambarAsli);

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
        _tampilkanPesan(_text('Ukuran foto terlalu besar. Pilih foto yang lebih kecil.', 'The photo is too large. Choose a smaller image.'));
        return;
      }

      await AccountService.perbaruiFotoProfil(base64Encode(fotoTerpotong));
      _tampilkanPesan(_text('Foto profil diperbarui.', 'Profile photo updated.'));
    } catch (_) {
      _tampilkanPesan(
        _text('Foto profil belum berhasil diperbarui. Coba pilih foto lain.', 'Could not update the profile photo. Try another image.'),
      );
    }
  }

  Future<void> _hapusFotoProfil() async {
    try {
      await AccountService.hapusFotoProfil();
      _tampilkanPesan(_text('Foto profil dihapus.', 'Profile photo removed.'));
    } catch (_) {
      _tampilkanPesan(_text('Foto profil belum berhasil dihapus.', 'Could not remove the profile photo.'));
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
          Text(
            _text('Aktivitas belum tersinkron', 'Unsynced activities'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            _text(
              '$_legacyHistoryCount aktivitas masih perlu dikirim ke akun.',
              '$_legacyHistoryCount activities still need to be uploaded to your account.',
            ),
            style: TextStyle(color: Theme.of(context).hintColor, height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _movingLegacyHistory ? null : _sinkronkanAktivitas,
            icon: _movingLegacyHistory
                ? SizedBox(
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
                  ? _text('Memindahkan aktivitas...', 'Moving activities...')
                  : _text('Sinkronkan aktivitas', 'Sync activities'),
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
        title: Text(_text('Keluar dari akun?', 'Sign out?')),
        content: Text(
          _text(
            'Data yang sudah tersimpan di akun tetap ada. Kamu perlu masuk lagi untuk membukanya.',
            'Data already saved to your account will remain there. You will need to sign in again to access it.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_text('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_text('Keluar', 'Sign out')),
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
        SnackBar(
          content: Text(_text('Belum berhasil keluar. Coba lagi.', 'Could not sign out. Please try again.')),
        ),
      );
    }
  }

  Future<void> _sinkronkanAktivitas() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_text('Sinkronkan aktivitas ke akun?', 'Sync activities to your account?')),
        content: Text(
          _text(
            '$_legacyHistoryCount aktivitas yang belum tersinkron akan dikirim ke akun ini. Data di perangkat hanya dibersihkan setelah penyimpanan akun berhasil.',
            '$_legacyHistoryCount unsynced activities will be uploaded to this account. Data on this device will only be cleared after the account save succeeds.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLanguageService.text(context, 'Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_text('Sinkronkan sekarang', 'Sync now')),
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
                ? _text(
                    '$jumlah aktivitas berhasil dipindahkan atau disinkronkan.',
                    '$jumlah activities were moved or synced successfully.',
                  )
                : _text(
                    'Tidak ada data yang perlu dipindahkan.',
                    'There is no data to move.',
                  ),
          ),
        ),
      );
    } catch (error) {
      await _loadRecovery();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_text('Sebagian aktivitas belum tersinkron', 'Some activities are still unsynced')),
          content: SingleChildScrollView(
            child: Text(error.toString()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text('Mengerti', 'Got it')),
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
  late final int _sisiDasar;
  late int _sisiPotong;
  late double _kiri;
  late double _atas;
  double _zoom = 1;
  double _zoomSaatMulai = 1;

  int get _maksKiri => widget.gambarAsli.width - _sisiPotong;
  int get _maksAtas => widget.gambarAsli.height - _sisiPotong;

  @override
  void initState() {
    super.initState();
    _sisiDasar = math.min(
      widget.gambarAsli.width,
      widget.gambarAsli.height,
    );
    _sisiPotong = _sisiDasar;
    _kiri = _maksKiri / 2;
    _atas = _maksAtas / 2;
  }

  void _mulaiGestur(ScaleStartDetails details) {
    _zoomSaatMulai = _zoom;
  }

  void _perbaruiGestur(ScaleUpdateDetails details) {
    final double zoomBaru =
        (_zoomSaatMulai * details.scale).clamp(1.0, 2.5).toDouble();
    final int sisiBaru =
        (_sisiDasar / zoomBaru).round().clamp(1, _sisiDasar).toInt();
    final double tengahX = _kiri + (_sisiPotong / 2);
    final double tengahY = _atas + (_sisiPotong / 2);
    final double skalaGeser = sisiBaru / 210;
    final double kiriBaru =
        (tengahX - sisiBaru / 2 - details.focalPointDelta.dx * skalaGeser)
            .clamp(0, widget.gambarAsli.width - sisiBaru)
            .toDouble();
    final double atasBaru =
        (tengahY - sisiBaru / 2 - details.focalPointDelta.dy * skalaGeser)
            .clamp(0, widget.gambarAsli.height - sisiBaru)
            .toDouble();

    setState(() {
      _zoom = zoomBaru;
      _sisiPotong = sisiBaru;
      _kiri = kiriBaru;
      _atas = atasBaru;
    });
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
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: Text(AppLanguageService.text(context, 'Potong foto profil', 'Crop profile photo')),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              GestureDetector(
                onScaleStart: _mulaiGestur,
                onScaleUpdate: _perbaruiGestur,
                child: Center(
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
              ),
              const SizedBox(height: 10),
              Text(
                AppLanguageService.text(
                  context,
                  'Cubit untuk memperbesar atau memperkecil, lalu geser foto untuk mengatur posisi.',
                  'Pinch to zoom in or out, then drag the photo to reposition it.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(color: teksSekunder, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppLanguageService.text(context, 'Batal', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hasilPotongan()),
          child: Text(AppLanguageService.text(context, 'Gunakan foto', 'Use photo')),
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
      return AppLanguageService.text(
        context,
        '$days hari ${hours % 24} jam '
            '${minutes.toString().padLeft(2, '0')} menit '
            '${secs.toString().padLeft(2, '0')} detik',
        '$days days ${hours % 24} hours '
            '${minutes.toString().padLeft(2, '0')} minutes '
            '${secs.toString().padLeft(2, '0')} seconds',
      );
    }
    return AppLanguageService.text(
      context,
      '$hours jam ${minutes.toString().padLeft(2, '0')} menit '
          '${secs.toString().padLeft(2, '0')} detik',
      '$hours hours ${minutes.toString().padLeft(2, '0')} minutes '
          '${secs.toString().padLeft(2, '0')} seconds',
    );
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? batasPemulihan = widget.recommendedResumeAt;
    final Duration? remaining = batasPemulihan?.difference(_now);
    final bool sudahLewat = remaining != null && remaining.isNegative;

    final String status;
    if (widget.loading) {
      status = AppLanguageService.text(context, 'Menghitung waktu istirahat…', 'Calculating recovery time…');
    } else if (!widget.hasActivity || remaining == null) {
      status = AppLanguageService.text(context, 'Belum ada aktivitas.', 'No activity yet.');
    } else if (sudahLewat) {
      status = AppLanguageService.text(context, 'Anda siap berolahraga.', 'You are ready to exercise.');
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
          Text(
            AppLanguageService.text(context, 'Pemulihan', 'Recovery'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
            AppLanguageService.text(
              context,
              'Ini hanya perkiraan saja, bukan penilaian medis. Jika masih merasa lelah, tunda latihan.',
              'This is only an estimate, not a medical assessment. If you still feel tired, postpone your workout.',
            ),
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