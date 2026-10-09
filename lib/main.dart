import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'features/ai_coach/ai_coach_page.dart';
import 'features/running/run_history_page.dart';
import 'features/running/running_page.dart';
import 'screens/muscle_page.dart';
import 'screens/timer_page.dart';
import 'theme/volt_theme.dart';

/// Titik masuk aplikasi VoltStride.
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
      systemNavigationBarColor: VoltWarna.kartu,
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

/// Navigasi sementara V2.
///
/// RunningPage menggantikan TrackerPage lama sebagai modul utama. Timer
/// dan strength tetap dipertahankan supaya kita tidak kehilangan fitur yang
/// sudah ada selama migrasi dilakukan bertahap.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  final GlobalKey<RunHistoryPageState> _historyKey =
      GlobalKey<RunHistoryPageState>();

  List<Widget> get _pages => <Widget>[
        const RunningPage(),
        RunHistoryPage(key: _historyKey),
        const TimerPage(),
        const AiCoachPage(),
        const MusclePage(),
      ];

  static const List<_NavigationItem> _items = <_NavigationItem>[
    _NavigationItem(
      label: 'Lari',
      icon: Icons.directions_run,
    ),
    _NavigationItem(
      label: 'Riwayat',
      icon: Icons.history,
    ),
    _NavigationItem(
      label: 'Timer',
      icon: Icons.timer_outlined,
    ),
    _NavigationItem(
      label: 'AI Coach',
      icon: Icons.chat_bubble_outline,
    ),
    _NavigationItem(
      label: 'Otot',
      icon: Icons.fitness_center,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) {
          setState(() => _index = value);
          if (value == 1) {
            unawaited(_historyKey.currentState?.reload() ?? Future<void>.value());
          }
        },
        destinations: _items
            .map(
              (_NavigationItem item) => NavigationDestination(
                icon: Icon(item.icon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavigationItem {
  final String label;
  final IconData icon;

  const _NavigationItem({
    required this.label,
    required this.icon,
  });
}
