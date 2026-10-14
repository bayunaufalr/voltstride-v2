import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/ai_coach/ai_coach_page.dart';
import 'features/home/home_dashboard_page.dart';
import 'features/progress/progress_page.dart';
import 'features/running/activity_setup_page.dart';
import 'features/running/run_history_page.dart';
import 'features/running/running_page.dart';
import 'screens/muscle_page.dart';
import 'screens/timer_page.dart';
import 'theme/volt_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
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
  runApp(const VoltStrideApp());
}

class VoltStrideApp extends StatelessWidget {
  const VoltStrideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoltStride',
      debugShowCheckedModeBanner: false,
      theme: buildVoltTheme(),
      home: const RootShell(),
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
    }
  }

  Future<void> _startActivity(ActivityStartConfig config) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => RunningPage(
          activityType: config.activityType,
          environment: config.environment,
          initialIntervalPlan: config.intervalPlan,
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

class MorePage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: <Widget>[
          const Text('Alat latihan', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Perlengkapan tambahan untuk rutinitasmu.', style: TextStyle(color: VoltWarna.teksAbu)),
          const SizedBox(height: 18),
          _moreItem(Icons.timer_outlined, 'Timer latihan', 'Atur ronde dan waktu pemulihan.', onOpenTimer),
          _moreItem(Icons.chat_bubble_outline_rounded, 'Coach', 'Evaluasi dan saran berdasarkan aktivitas tersimpan.', onOpenCoach),
          _moreItem(Icons.fitness_center_rounded, 'Latihan kekuatan', 'Referensi kelompok otot dan gerakan.', onOpenStrength),
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
