import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'features/account/account_service.dart';
import 'features/account/firebase_setup_page.dart';
import 'features/account/login_page.dart';
import 'features/account/account_page.dart';
import 'features/more/more_page.dart';
import 'features/route_planner/route_planner_page.dart';
import 'features/ai_coach/ai_coach_page.dart';
import 'features/home/home_dashboard_page.dart';
import 'features/progress/progress_page.dart';
import 'features/running/activity_setup_page.dart';
import 'features/running/run_history_page.dart';
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
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: VoltWarna.latar,
      systemNavigationBarIconBrightness: Brightness.dark,
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
  final GlobalKey<AccountPageState> _accountKey = GlobalKey<AccountPageState>();
  final GlobalKey<MorePageState> _moreKey = GlobalKey<MorePageState>();

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
        AccountPage(key: _accountKey),
        MorePage(
          key: _moreKey,
          onOpenTimer: () => _openPage(const TimerPage()),
          onOpenCoach: () => _openPage(const AiCoachPage()),
          onOpenStrength: () => _openPage(const MusclePage()),
          onOpenRoutePlanner: () => _openPage(const RoutePlannerPage()),
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
      icon: Icon(Icons.add_rounded),
      selectedIcon: Icon(Icons.add_rounded),
      label: 'Rekam',
    ),
    NavigationDestination(
      icon: Icon(Icons.history_rounded),
      selectedIcon: Icon(Icons.history_rounded),
      label: 'Riwayat',
    ),
    NavigationDestination(
      icon: Icon(Icons.bar_chart_rounded),
      selectedIcon: Icon(Icons.bar_chart_rounded),
      label: 'Kemajuan',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Anda',
    ),
    NavigationDestination(
      icon: Icon(Icons.more_horiz_rounded),
      selectedIcon: Icon(Icons.more_horiz_rounded),
      label: 'Lainnya',
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
        unawaited(_accountKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 5:
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

