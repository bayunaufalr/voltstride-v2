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
import '../reminders/reminder_service.dart';
import '../../services/app_language_service.dart';
import 'profile_training_summary.dart';
import 'account_service.dart';

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
  bool _showProfile = false;
  bool _movingLegacyHistory = false;
  int _legacyHistoryCount = 0;
  late final TabController _sectionController;
  final GlobalKey<ProgressPageState> _progressKey =
      GlobalKey<ProgressPageState>();
  final GlobalKey<RunHistoryPageState> _historyKey =
      GlobalKey<RunHistoryPageState>();
  final GlobalKey<TrainingRemindersPageState> _remindersKey =
      GlobalKey<TrainingRemindersPageState>();

  @override
  void initState() {
    super.initState();
    _sectionController = TabController(length: 3, vsync: this);
    _loadRecovery();
  }

  void openSection(int index) {
    if (index < 0 || index >= _sectionController.length) return;
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
      final List<RunSession> sessions =
          await RunHistoryRepository.instance.getAll(limit: 200);
      final int legacyCount =
          await RunHistoryRepository.instance.pendingSessionCount();
      if (sessions.isNotEmpty) {
        await _markScheduledActivityCompleted(sessions.first);
      }
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

  Future<void> _markScheduledActivityCompleted(RunSession session) async {
    if (session.finishedAt == null || session.distanceKm <= 0) return;

    final DateTime start = session.startedAt.toLocal();
    final String dateKey = '${start.year.toString().padLeft(4, '0')}-'
        '${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    final List<TrainingReminder> reminders = await ReminderService.getAll();
    for (final TrainingReminder reminder in reminders) {
      if (!reminder.weekdays.contains(start.weekday) ||
          reminder.completedDates.contains(dateKey)) {
        continue;
      }

      final String planned = reminder.activity.toLowerCase();
      final bool isWalk = session.activityType == RunActivityType.walk;
      final bool matchesActivity = planned.contains('jalan')
          ? isWalk
          : planned.contains('interval')
              ? !isWalk && session.intervalPlan != null
              : planned.contains('lari') && !isWalk;
      if (!matchesActivity) continue;

      final DateTime plannedStart = DateTime(
        start.year,
        start.month,
        start.day,
        reminder.hour,
        reminder.minute,
      );
      if (start.difference(plannedStart).abs() <= const Duration(hours: 2)) {
        await ReminderService.setOccurrenceCompleted(
          reminderId: reminder.id,
          dateKey: dateKey,
          completed: true,
        );
      }
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

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  String _displayName() {
    final User? user = AccountService.akunAktif;
    final String? name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final String? email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return _text('Pengguna', 'User');
  }

  Widget _profileAvatarAction() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AccountService.perubahanProfil,
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        final String encoded =
            snapshot.data?.data()?['fotoProfilBase64'] as String? ?? '';
        final ImageProvider<Object>? photo =
            encoded.isEmpty ? null : _fotoDariBase64(encoded);
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            tooltip: _text('Buka profil', 'Open profile'),
            onPressed: () => setState(() => _showProfile = true),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              backgroundImage: photo,
              child: photo == null
                  ? const Icon(Icons.person_outline_rounded, size: 20)
                  : null,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Tab> tabs = <Tab>[
      Tab(
        icon: const Icon(Icons.bar_chart_rounded),
        text: _text('Kemajuan', 'Progress'),
      ),
      Tab(
        icon: const Icon(Icons.history_rounded),
        text: _text('Aktivitas', 'Activities'),
      ),
      Tab(
        icon: const Icon(Icons.event_note_rounded),
        text: _text('Rencanakan latihan', 'Training plan'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: _showProfile
            ? IconButton(
                tooltip: _text('Kembali ke aktivitas', 'Back to activity'),
                onPressed: () => setState(() => _showProfile = false),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : null,
        title: Text(_displayName()),
        actions: _showProfile ? null : <Widget>[_profileAvatarAction()],
        bottom: _showProfile
            ? null
            : TabBar(
                controller: _sectionController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: tabs,
              ),
      ),
      body: _showProfile
          ? _profileTab()
          : TabBarView(
              controller: _sectionController,
              children: <Widget>[
                ProgressPage(
                  key: _progressKey,
                  embedded: true,
                  belowWeeklyChart: _RecoveryCountdownCard(
                    recommendedResumeAt: _recommendedResumeAt,
                    loading: _loading,
                    hasActivity: _latestSession != null,
                  ),
                ),
                RunHistoryPage(key: _historyKey, embedded: true),
                TrainingRemindersPage(key: _remindersKey, embedded: true),
              ],
            ),
    );
  }

  Widget _profileTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _accountCard(),
        const SizedBox(height: 12),
        const ProfileTrainingSummary(),
        const SizedBox(height: 12),
        _themeCard(),
        const SizedBox(height: 12),
        const AppLanguageSettingCard(),
        if (_legacyHistoryCount > 0) ...<Widget>[
          const SizedBox(height: 14),
          _legacyHistoryCard(),
        ],
      ],
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
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
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
        _text('Foto profil belum berhasil diperbarui. Coba pilih foto lain.', 'The profile photo could not be updated. Try another image.'),
      );
    }
  }

  Future<void> _hapusFotoProfil() async {
    try {
      await AccountService.hapusFotoProfil();
      _tampilkanPesan(_text('Foto profil dihapus.', 'Profile photo removed.'));
    } catch (_) {
      _tampilkanPesan(_text('Foto profil belum berhasil dihapus.', 'The profile photo could not be removed.'));
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
            _text('$_legacyHistoryCount aktivitas masih perlu dikirim ke akun.', '$_legacyHistoryCount activities still need to be uploaded to your account.'),
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
                  ? _text('Memindahkan aktivitas...', 'Uploading activities...')
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
          _text('Data yang sudah tersimpan di akun tetap ada. Kamu perlu masuk lagi untuk membukanya.', 'Data already saved to your account will remain there. You will need to sign in again to access it.'),
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
        SnackBar(content: Text(_text('Belum berhasil keluar. Coba lagi.', 'Could not sign out. Try again.'))),
      );
    }
  }

  Future<void> _sinkronkanAktivitas() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_text('Sinkronkan aktivitas ke akun?', 'Sync activities to your account?')),
        content: Text(
          _text('$_legacyHistoryCount aktivitas yang belum tersinkron akan dikirim ke akun ini. Data di perangkat hanya dibersihkan setelah penyimpanan akun berhasil.', '$_legacyHistoryCount unsynced activities will be uploaded to this account. Device data is removed only after the account upload succeeds.'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_text('Batal', 'Cancel')),
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
                ? _text('$jumlah aktivitas berhasil dipindahkan atau disinkronkan.', '$jumlah activities were migrated or synced.')
                : _text('Tidak ada data yang perlu dipindahkan.', 'No data needs to be migrated.'),
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

/// Editor foto profil dengan gestur cubit untuk zoom dan satu jari untuk menggeser.
class _CropFotoDialog extends StatefulWidget {
  const _CropFotoDialog({required this.gambarAsli});

  final img.Image gambarAsli;

  @override
  State<_CropFotoDialog> createState() => _CropFotoDialogState();
}

class _CropFotoDialogState extends State<_CropFotoDialog> {
  static const double _pratinjauSisi = 240;
  late final int _sisiDasar;
  late final Uint8List _bytesPratinjau;
  late int _sisiPotong;
  late double _kiri;
  late double _atas;
  double _zoom = 1;
  double _zoomAwalGestur = 1;

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
    _kiri = (widget.gambarAsli.width - _sisiPotong) / 2;
    _atas = (widget.gambarAsli.height - _sisiPotong) / 2;
    // Encode sekali saja. Meng-encode ulang pada setiap gerakan membuat crop
    // tersendat terutama pada ponsel dengan RAM dan CPU terbatas.
    _bytesPratinjau = Uint8List.fromList(
      img.encodeJpg(widget.gambarAsli, quality: 88),
    );
  }

  void _mulaiGestur(ScaleStartDetails details) {
    _zoomAwalGestur = _zoom;
  }

  void _perbaruiGestur(ScaleUpdateDetails details) {
    final double zoomBaru =
        (_zoomAwalGestur * details.scale).clamp(1.0, 2.5).toDouble();
    final int sisiBaru =
        (_sisiDasar / zoomBaru).round().clamp(1, _sisiDasar).toInt();
    final double rasioSumberPerPixel = _sisiPotong / _pratinjauSisi;
    final double tengahX = _kiri + _sisiPotong / 2 -
        details.focalPointDelta.dx * rasioSumberPerPixel;
    final double tengahY = _atas + _sisiPotong / 2 -
        details.focalPointDelta.dy * rasioSumberPerPixel;
    final double kiriMaks = widget.gambarAsli.width - sisiBaru;
    final double atasMaks = widget.gambarAsli.height - sisiBaru;

    setState(() {
      _zoom = zoomBaru;
      _sisiPotong = sisiBaru;
      _kiri = (tengahX - sisiBaru / 2).clamp(0.0, kiriMaks).toDouble();
      _atas = (tengahY - sisiBaru / 2).clamp(0.0, atasMaks).toDouble();
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
    final double skala = _pratinjauSisi / _sisiPotong;
    final double lebar = widget.gambarAsli.width * skala;
    final double tinggi = widget.gambarAsli.height * skala;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    final bool english = Localizations.localeOf(context).languageCode == 'en';

    return AlertDialog(
      title: Text(english ? 'Adjust profile photo' : 'Atur foto profil'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _mulaiGestur,
              onScaleUpdate: _perbaruiGestur,
              child: ClipOval(
                child: SizedBox(
                  width: _pratinjauSisi,
                  height: _pratinjauSisi,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      Positioned(
                        left: -_kiri * skala,
                        top: -_atas * skala,
                        width: lebar,
                        height: tinggi,
                        child: Image.memory(
                          _bytesPratinjau,
                          width: lebar,
                          height: tinggi,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              english
                  ? 'Pinch to zoom in or out. Drag the photo to reposition it.'
                  : 'Cubit untuk memperbesar atau memperkecil. Geser foto untuk mengatur posisinya.',
              textAlign: TextAlign.center,
              style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(english ? 'Cancel' : 'Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_hasilPotongan()),
          child: Text(english ? 'Use photo' : 'Gunakan foto'),
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
      final bool english = Localizations.localeOf(context).languageCode == 'en';
      return english
          ? '$days d ${hours % 24} h ${minutes.toString().padLeft(2, '0')} m ${secs.toString().padLeft(2, '0')} s'
          : '$days hari ${hours % 24} jam ${minutes.toString().padLeft(2, '0')} menit ${secs.toString().padLeft(2, '0')} detik';
    }
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    return english
        ? '$hours h ${minutes.toString().padLeft(2, '0')} m ${secs.toString().padLeft(2, '0')} s'
        : '$hours jam ${minutes.toString().padLeft(2, '0')} menit ${secs.toString().padLeft(2, '0')} detik';
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
      status = AppLanguageService.text(context, 'Belum ada aktivitas.', 'No activities yet.');
    } else if (sudahLewat) {
      status = AppLanguageService.text(context, 'Anda siap berolahraga.', 'You may be ready for your next session.');
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
            AppLanguageService.text(context, 'Ini hanya perkiraan, bukan penilaian medis. Jika masih merasa lelah, tunda latihan.', 'This is only an estimate, not a medical assessment. Delay your workout if you still feel tired.'),
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
