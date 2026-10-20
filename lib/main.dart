import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'features/account/account_service.dart';
import 'features/account/firebase_setup_page.dart';
import 'features/account/login_page.dart';
import 'features/account/account_page.dart';
import 'features/more/more_page.dart';
import 'features/reminders/reminder_service.dart';
import 'features/route_planner/route_planner_page.dart';
import 'features/ai_coach/ai_coach_page.dart';
import 'features/home/home_dashboard_page.dart';
import 'features/running/activity_setup_page.dart';
import 'features/running/running_page.dart';
import 'screens/muscle_page.dart';
import 'screens/timer_page.dart';
import 'theme/volt_theme.dart';
import 'services/app_language_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadVoltThemeMode();
  await AppLanguageService.load();
  try {
    await ReminderService.initialize();
    await ReminderService.restoreSavedSchedules();
  } catch (_) {
    // Kegagalan pengingat tidak boleh menghalangi aplikasi dibuka.
  }
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
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLanguageService.localeNotifier,
      builder: (BuildContext context, Locale locale, Widget? child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: voltThemeModeNotifier,
          builder: (BuildContext context, ThemeMode mode, Widget? child) {
            return MaterialApp(
              title: 'VoltStride',
              debugShowCheckedModeBanner: false,
              locale: locale,
              supportedLocales: const <Locale>[
                Locale('id'),
                Locale('en'),
              ],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: buildVoltTheme(),
              darkTheme: buildVoltTheme(brightness: Brightness.dark),
              themeMode: mode,
              builder: (BuildContext context, Widget? child) {
                final Brightness brightness = Theme.of(context).brightness;
                SystemChrome.setSystemUIOverlayStyle(
                  SystemUiOverlayStyle(
                    statusBarColor: Theme.of(context).scaffoldBackgroundColor,
                    statusBarIconBrightness: brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
                    systemNavigationBarColor:
                        Theme.of(context).scaffoldBackgroundColor,
                    systemNavigationBarIconBrightness:
                        brightness == Brightness.dark
                            ? Brightness.light
                            : Brightness.dark,
                  ),
                );
                return child ?? const SizedBox.shrink();
              },
              home: firebaseReady
                  ? const AccountGate()
                  : FirebaseSetupPage(detailError: firebaseSetupError),
            );
          },
        );
      },
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
  final GlobalKey<AccountPageState> _accountKey = GlobalKey<AccountPageState>();
  final GlobalKey<MorePageState> _moreKey = GlobalKey<MorePageState>();

  List<Widget> get _pages => <Widget>[
        HomeDashboardPage(
          key: _homeKey,
          onRecord: () => _selectTab(1),
          onHistory: () => _openAccountSection(1),
        ),
        ActivitySetupPage(
          key: _activityKey,
          onStart: _startActivity,
        ),
        RoutePlannerPage(active: _index == 2),
        AccountPage(key: _accountKey),
        MorePage(
          key: _moreKey,
          onOpenTimer: () => _openPage(const TimerPage()),
          onOpenCoach: () => _openPage(const AiCoachPage()),
          onOpenStrength: () => _openPage(const MusclePage()),
        ),
      ];

  List<NavigationDestination> _destinations(BuildContext context) {
    String text(String id, String en) =>
        AppLanguageService.text(context, id, en);
    return <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: text('Beranda', 'Home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.add_rounded),
        selectedIcon: const Icon(Icons.add_rounded),
        label: text('Rekam', 'Record'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.route_outlined),
        selectedIcon: const Icon(Icons.route_rounded),
        label: text('Rute', 'Routes'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: text('Anda', 'You'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.more_horiz_rounded),
        selectedIcon: const Icon(Icons.more_horiz_rounded),
        label: text('Lainnya', 'More'),
      ),
    ];
  }

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
        // Perencana rute meminta lokasi ketika tab ini dibuka.
        break;
      case 3:
        unawaited(_accountKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 4:
        unawaited(_moreKey.currentState?.reload() ?? Future<void>.value());
        break;
    }
  }

  void _openAccountSection(int section) {
    _selectTab(3);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _accountKey.currentState?.openSection(section);
    });
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
    unawaited(_accountKey.currentState?.reload() ?? Future<void>.value());
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
        destinations: _destinations(context),
      ),
    );
  }
}

