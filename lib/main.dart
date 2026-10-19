import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'features/account/account_service.dart';
import 'features/account/firebase_setup_page.dart';
import 'features/account/login_page.dart';
import 'features/ai_coach/ai_coach_page.dart';
import 'features/home/home_dashboard_page.dart';
import 'features/progress/progress_page.dart';
import 'features/running/activity_setup_page.dart';
import 'features/running/run_history_page.dart';
import 'features/running/models/run_session.dart';
import 'features/running/services/run_history_repository.dart';
import 'features/running/running_page.dart';
import 'screens/muscle_page.dart';
import 'screens/timer_page.dart';
import 'theme/volt_theme.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: VoltWarna.latar,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: VoltWarna.latar,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  String? firebaseSetupError;
  try {
    // Berkas ini dibuat oleh perintah `flutterfire configure`.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (error) {
    // Aplikasi tetap bisa menampilkan panduan konfigurasi, bukan layar kosong.
    firebaseSetupError = error.toString();
  }

  runApp(
    VoltStrideApp(
      firebaseReady: Firebase.apps.isNotEmpty,
      firebaseSetupError: firebaseSetupError,
    ),
  );
}

class VoltStrideApp extends StatelessWidget {
  const VoltStrideApp({
    super.key,
    required this.firebaseReady,
    this.firebaseSetupError,
  });

  final bool firebaseReady;
  final String? firebaseSetupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltStride',
      debugShowCheckedModeBanner: false,
      theme: buildVoltTheme(),
      home: firebaseReady
          ? const AccountGate()
          : FirebaseSetupPage(detailError: firebaseSetupError),
    );
  }
}

/// Memilih halaman login atau halaman utama berdasarkan sesi akun Firebase.
class AccountGate extends StatefulWidget {
  const AccountGate({super.key});

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  late final Stream<User?> _perubahanAkun = AccountService.perubahanAkun;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _perubahanAkun,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const LoginPage();
        }

        final User? pengguna = snapshot.data;
        if (pengguna == null) return const LoginPage();

        return RootShell(key: ValueKey<String>(pengguna.uid));
      },
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final GlobalKey<HomeDashboardPageState> _homeKey =
      GlobalKey<HomeDashboardPageState>();
  final GlobalKey<ActivitySetupPageState> _activityKey =
      GlobalKey<ActivitySetupPageState>();
  final GlobalKey<RunHistoryPageState> _historyKey =
      GlobalKey<RunHistoryPageState>();
  final GlobalKey<ProgressPageState> _progressKey =
      GlobalKey<ProgressPageState>();
  final GlobalKey<_MorePageState> _moreKey = GlobalKey<_MorePageState>();

  List<Widget> get _pages => <Widget>[
        HomeDashboardPage(
          key: _homeKey,
          onRecord: () => _selectTab(1),
          onHistory: () => _selectTab(2),
          onProgress: () => _selectTab(3),
        ),
        ActivitySetupPage(
          key: _activityKey,
          onStart: _startActivity,
        ),
        RunHistoryPage(key: _historyKey),
        ProgressPage(key: _progressKey),
        MorePage(
          key: _moreKey,
          onOpenTimer: () => _openPage(const TimerPage()),
          onOpenCoach: () => _openPage(const AiCoachPage()),
          onOpenStrength: () => _openPage(const MusclePage()),
        ),
      ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Beranda',
    ),
    NavigationDestination(
      icon: Icon(Icons.radio_button_unchecked_rounded),
      selectedIcon: Icon(Icons.radio_button_checked_rounded),
      label: 'Rekam',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'Riwayat',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights_rounded),
      label: 'Kemajuan',
    ),
    NavigationDestination(
      icon: Icon(Icons.grid_view_rounded),
      selectedIcon: Icon(Icons.grid_view_rounded),
      label: 'Akun',
    ),
  ];

  void _selectTab(int value) {
    setState(() => _index = value);
    switch (value) {
      case 0:
        unawaited(_homeKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 1:
        unawaited(_activityKey.currentState?.loadLocation() ?? Future<void>.value());
        break;
      case 2:
        unawaited(_historyKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 3:
        unawaited(_progressKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 4:
        unawaited(_moreKey.currentState?.reload() ?? Future<void>.value());
        break;
    }
  }

  Future<void> _startActivity(ActivityStartConfig config) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => RunningPage(
          activityType: config.activityType,
          environment: config.environment,
          initialIntervalPlan: config.intervalPlan,
          targetDistanceKm: config.targetDistanceKm,
          targetPaceSecondsPerKm: config.targetPaceSecondsPerKm,
          autoStart: true,
          onExit: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _index = 0);
    unawaited(_homeKey.currentState?.reload() ?? Future<void>.value());
    unawaited(_historyKey.currentState?.reload() ?? Future<void>.value());
    unawaited(_progressKey.currentState?.reload() ?? Future<void>.value());
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _selectTab,
        destinations: _destinations,
      ),
    );
  }
}

class MorePage extends StatefulWidget {
  const MorePage({
    super.key,
    required this.onOpenTimer,
    required this.onOpenCoach,
    required this.onOpenStrength,
  });

  final VoidCallback onOpenTimer;
  final VoidCallback onOpenCoach;
  final VoidCallback onOpenStrength;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  RunSession? _latestSession;
  DateTime? _recommendedResumeAt;
  bool _loading = true;
  bool _movingLegacyHistory = false;
  int _legacyHistoryCount = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadRecovery();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> reload() => _loadRecovery();

  Future<void> _loadRecovery() async {
    try {
      final List<RunSession> sessions = await RunHistoryRepository.instance.getAll(limit: 1);
      final int legacyCount = await RunHistoryRepository.instance.legacySessionCount();
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

  String _countdownText(Duration remaining) {
    final int seconds = remaining.inSeconds.clamp(0, 999999999).toInt();
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int secs = seconds % 60;
    if (hours >= 24) {
      final int days = hours ~/ 24;
      return '$days hari ${hours % 24} jam ${minutes.toString().padLeft(2, '0')} menit';
    }
    return '$hours jam ${minutes.toString().padLeft(2, '0')} menit ${secs.toString().padLeft(2, '0')} detik';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? until = _recommendedResumeAt;
    final Duration? remaining = until?.difference(DateTime.now());
    final bool restWindowPassed = remaining != null && remaining.isNegative;
    return Scaffold(
      appBar: AppBar(title: const Text('Akun')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          _accountCard(),
          if (_legacyHistoryCount > 0) ...<Widget>[
            const SizedBox(height: 14),
            _legacyHistoryCard(),
          ],
          const SizedBox(height: 14),
          _recoveryCard(remaining, restWindowPassed),
          const SizedBox(height: 24),
          const Text('Alat latihan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Timer dan alat pendukung untuk rutinitasmu.', style: TextStyle(color: VoltWarna.teksAbu)),
          const SizedBox(height: 14),
          _moreItem(Icons.timer_outlined, 'Timer latihan', 'Atur ronde dan waktu pemulihan.', widget.onOpenTimer),
          _moreItem(Icons.chat_bubble_outline_rounded, 'Coach lokal', 'Saran berdasarkan aktivitas yang tersimpan.', widget.onOpenCoach),
          _moreItem(Icons.fitness_center_rounded, 'Latihan kekuatan', 'Referensi kelompok otot dan gerakan.', widget.onOpenStrength),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _loadRecovery,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Perbarui data pemulihan'),
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    final User? pengguna = AccountService.akunAktif;
    final String nama = pengguna?.displayName?.trim().isNotEmpty == true
        ? pengguna!.displayName!.trim()
        : 'Pelari VoltStride';
    final String email = pengguna?.email ?? 'Email tidak tersedia';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: VoltWarna.aksen.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.person_outline_rounded,
                  color: VoltWarna.aksen,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      nama,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: const TextStyle(
                        color: VoltWarna.teksAbu,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Riwayat lari tersimpan di akun dan perangkat ini.',
                      style: TextStyle(
                        color: VoltWarna.teksAbu,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _konfirmasiKeluar,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ),
    );
  }

  Widget _legacyHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VoltWarna.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Riwayat lama ditemukan',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Ada $_legacyHistoryCount aktivitas lama yang masih tersimpan di perangkat dan belum terhubung ke akun. Pindahkan hanya jika data itu memang milikmu.',
            style: const TextStyle(color: VoltWarna.teksAbu, height: 1.45),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _movingLegacyHistory ? null : _pindahkanRiwayatLama,
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
                  ? 'Memindahkan riwayat...'
                  : 'Pindahkan ke akun ini',
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

  Future<void> _pindahkanRiwayatLama() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Pindahkan riwayat lama?'),
        content: Text(
          'Sebanyak $_legacyHistoryCount aktivitas beserta titik rute GPS akan disalin ke akun ini. Lakukan hanya jika aktivitas tersebut memang milikmu. Data akun lain tidak akan digabungkan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Pindahkan'),
          ),
        ],
      ),
    );
    if (lanjut != true || !mounted) return;

    setState(() => _movingLegacyHistory = true);
    try {
      final int jumlah =
          await RunHistoryRepository.instance.importLegacyHistoryToAccount();
      await _loadRecovery();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$jumlah aktivitas berhasil dipindahkan ke akun.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _movingLegacyHistory = false);
    }
  }

  Widget _recoveryCard(Duration? remaining, bool restWindowPassed) {
    final RunSession? session = _latestSession;
    final int restHours = session == null ? 0 : _suggestedRestHours(session);
    final String title;
    final String status;
    if (_loading) {
      title = 'MENGHITUNG JEDA';
      status = 'Membaca aktivitas terakhir…';
    } else if (session == null || remaining == null) {
      title = 'WAKTU PEMULIHAN';
      status = 'Selesaikan satu aktivitas untuk mendapatkan perkiraan jeda berikutnya.';
    } else if (restWindowPassed) {
      title = 'JEDA YANG DISARANKAN TERCAPAI';
      status = 'Perkiraan jeda ${restHours} jam sudah lewat. Cek kondisi tubuh dan mulai ringan; countdown bukan jaminan tubuh sudah pulih.';
    } else {
      title = 'PERKIRAAN SAMPAI SESI BERIKUTNYA';
      status = _countdownText(remaining);
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: restWindowPassed ? const Color(0xFF173B31) : VoltWarna.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: restWindowPassed ? VoltWarna.hijau.withValues(alpha: 0.5) : VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.hourglass_bottom_rounded, color: VoltWarna.aksen),
              SizedBox(width: 9),
              Text('PEMULIHAN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 11, color: VoltWarna.teksAbu, fontWeight: FontWeight.w900, letterSpacing: 0.7)),
          const SizedBox(height: 4),
          Text(status, style: TextStyle(fontSize: remaining != null && !restWindowPassed ? 22 : 13, fontWeight: FontWeight.w900, height: 1.3)),
          if (session != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Sesi terakhir: ${session.distanceKm.toStringAsFixed(2)} km • ${session.displayLabel.toLowerCase()} • perkiraan jeda ${restHours} jam.', style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11, height: 1.4)),
          ],
          const SizedBox(height: 8),
          const Text('Ini hanya aturan penjadwalan sederhana, bukan penilaian medis. Jika masih sangat lelah, nyeri, atau merasa tidak sehat, tunda latihan.', style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11, height: 1.4)),
        ],
      ),
    );
  }

  Widget _moreItem(IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: VoltWarna.surface, borderRadius: BorderRadius.circular(14)),
          child: Icon(icon, color: VoltWarna.aksen),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
