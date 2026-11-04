// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
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
import 'features/home/home_dashboard_page.dart';
import 'features/running/activity_setup_page.dart';
import 'features/running/models/run_session.dart';
import 'features/running/running_page.dart';
import 'features/splash/animated_splash_gate.dart';
import 'screens/timer_page.dart';
import 'theme/volt_theme.dart';
import 'services/app_language_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadVoltThemeMode();
  await AppLanguageService.load();
  // Penjadwalan pengingat tidak dijalankan sebelum tampilan pertama muncul.
  // Pada perangkat tertentu, membaca zona waktu dan memulihkan banyak jadwal
  // dapat membuat aplikasi terasa macet saat baru dibuka.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
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

  // Beri Android kesempatan menampilkan layar lebih dahulu. Setelah itu,
  // pengingat dipulihkan di belakang layar tanpa menahan pembukaan aplikasi.
  WidgetsBinding.instance.addPostFrameCallback((Duration _) {
    unawaited(_restoreRemindersAfterStartup());
  });
}

Future<void> _restoreRemindersAfterStartup() async {
  // Jeda singkat memastikan bingkai pertama sempat ditampilkan di HP.
  await Future<void>.delayed(const Duration(milliseconds: 700));
  try {
    await ReminderService.initialize().timeout(
      const Duration(seconds: 12),
    );
    await ReminderService.restoreSavedSchedules().timeout(
      const Duration(seconds: 20),
    );
  } on TimeoutException catch (error) {
    // Aplikasi tetap dapat dipakai walaupun pemulihan alarm tertunda.
    debugPrint('Pemulihan pengingat melewati batas waktu: $error');
  } catch (error, stackTrace) {
    // Kegagalan alarm tidak boleh membuat seluruh aplikasi macet.
    debugPrint('Pengingat belum dapat dipulihkan: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class VoltStrideApp extends StatelessWidget {
  VoltStrideApp({
    super.key,
    required this.firebaseReady,
    this.firebaseSetupError,
  }) : _splashGateKey = GlobalKey<AnimatedSplashGateState>();

  final GlobalKey<AnimatedSplashGateState> _splashGateKey;
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
              home: AnimatedSplashGate(
                key: _splashGateKey,
                waitForChildReady: firebaseReady,
                child: firebaseReady
                    ? AccountGate(
                        onReady: () =>
                            _splashGateKey.currentState?.markChildReady(),
                      )
                    : FirebaseSetupPage(detailError: firebaseSetupError),
              ),
            );
          },
        );
      },
    );
  }

}

/// Memilih halaman login atau halaman utama berdasarkan sesi akun Firebase.
class AccountGate extends StatefulWidget {
  const AccountGate({super.key, this.onReady});

  final VoidCallback? onReady;

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  late final Stream<User?> _perubahanAkun = AccountService.perubahanAkun;
  bool _readyAlreadyReported = false;

  void _reportReadyWhenResolved(AsyncSnapshot<User?> snapshot) {
    if (_readyAlreadyReported ||
        (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasError)) {
      return;
    }
    _readyAlreadyReported = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) widget.onReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _perubahanAkun,
      builder: (BuildContext context, AsyncSnapshot<User?> snapshot) {
        _reportReadyWhenResolved(snapshot);
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
  List<RunPoint> _plannedRoute = <RunPoint>[];
  ActivityStartConfig? _activeRunConfig;
  bool _showRunningPage = false;
  bool _runningSessionActive = false;
  bool _exitDialogOpen = false;
  int _runPageGeneration = 0;

  final GlobalKey<HomeDashboardPageState> _homeKey =
      GlobalKey<HomeDashboardPageState>();
  final GlobalKey<ActivitySetupPageState> _activityKey =
      GlobalKey<ActivitySetupPageState>();
  final GlobalKey<AccountPageState> _accountKey = GlobalKey<AccountPageState>();
  final GlobalKey<MorePageState> _moreKey = GlobalKey<MorePageState>();

  List<Widget> get _pages => <Widget>[
        HomeDashboardPage(
          key: _homeKey,
          onRecord: () => _selectTab(2),
          onHistory: () => _openAccountSection(1),
        ),
        RoutePlannerPage(
          active: _index == 1,
          onUseRoute: (List<RunPoint> route) {
            _plannedRoute = List<RunPoint>.unmodifiable(route);
            _selectTab(2);
          },
        ),
        ActivitySetupPage(
          key: _activityKey,
          sessionAlreadyActive: _runningSessionActive,
          onStart: _startActivity,
        ),
        MorePage(
          key: _moreKey,
          onOpenTimer: () => _openPage(const TimerPage()),
        ),
        AccountPage(key: _accountKey),
      ];

  List<NavigationDestination> _destinations(BuildContext context) {
    String text(String id, String en) =>
        AppLanguageService.text(context, id, en);
    final Color accent = Theme.of(context).colorScheme.primary;
    final Color onAccent = Theme.of(context).colorScheme.onPrimary;
    return <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: text('Beranda', 'Home'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.map_outlined),
        selectedIcon: const Icon(Icons.map_rounded),
        label: text('Rute', 'Routes'),
      ),
      NavigationDestination(
        icon: Container(
          width: 42,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.add_rounded, color: onAccent, size: 27),
        ),
        selectedIcon: Container(
          width: 44,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(Icons.add_rounded, color: onAccent, size: 29),
        ),
        label: text('Rekam', 'Record'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.more_horiz_rounded),
        selectedIcon: const Icon(Icons.more_horiz_rounded),
        label: text('Lainnya', 'More'),
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: text('Saya', 'Me'),
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
        // Perencana rute meminta lokasi ketika tab ini dibuka.
        break;
      case 2:
        unawaited(_activityKey.currentState?.loadLocation() ?? Future<void>.value());
        break;
      case 3:
        unawaited(_moreKey.currentState?.reload() ?? Future<void>.value());
        break;
      case 4:
        unawaited(_accountKey.currentState?.reload() ?? Future<void>.value());
        break;
    }
  }

  void _openAccountSection(int section) {
    _selectTab(4);
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _accountKey.currentState?.openSection(section);
    });
  }

  void _startActivity(ActivityStartConfig config) {
    if (_runningSessionActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLanguageService.text(
            context,
            'Sesi sebelumnya masih merekam. Selesaikan sesi itu sebelum memulai aktivitas baru.',
            'The current session is still recording. Finish it before starting another activity.',
          )),
        ),
      );
      return;
    }

    setState(() {
      _activeRunConfig = config;
      _runPageGeneration++;
      _showRunningPage = true;
      _index = 2;
    });
  }

  void _onRunningSessionActiveChanged(bool active) {
    if (!mounted || _runningSessionActive == active) return;
    setState(() => _runningSessionActive = active);
  }

  void _minimizeRunningPage() {
    if (!mounted) return;
    setState(() {
      _showRunningPage = false;
      _index = 0;
    });
  }

  void _exitRunningPage() {
    if (!mounted) return;
    setState(() {
      _activeRunConfig = null;
      _showRunningPage = false;
      _runningSessionActive = false;
      _index = 0;
    });
    unawaited(_homeKey.currentState?.reload() ?? Future<void>.value());
    unawaited(_accountKey.currentState?.reload() ?? Future<void>.value());
  }

  Widget _activeSessionBanner(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final ActivityStartConfig? config = _activeRunConfig;
    final String activity = config?.activityType == RunActivityType.walk
        ? AppLanguageService.text(context, 'Jalan', 'Walk')
        : config?.activityType == RunActivityType.cycle
            ? AppLanguageService.text(context, 'Sepeda', 'Cycling')
            : config?.activityType == RunActivityType.hiit
                ? 'HIIT'
                : AppLanguageService.text(context, 'Lari', 'Run');
    return Material(
      color: colors.surface,
      elevation: 5,
      child: Container(
        constraints: const BoxConstraints(minHeight: 54, maxHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: colors.outline)),
        child: Row(
          children: <Widget>[
            Icon(Icons.gps_fixed_rounded, color: colors.onSurface, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLanguageService.text(
                  context,
                  '$activity masih merekam',
                  '$activity is still recording',
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => setState(() => _showRunningPage = true),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
              ),
              child: Text(AppLanguageService.text(context, 'Kembali', 'Resume')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => page),
    );
  }

  Future<void> _confirmExitApplication() async {
    if (!mounted || _exitDialogOpen) return;
    _exitDialogOpen = true;
    try {
      final bool? shouldExit = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(AppLanguageService.text(
            context,
            'Apakah Anda ingin keluar dari VoltStride?',
            'Do you want to exit VoltStride?',
          )),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
          actions: <Widget>[
            SizedBox(
              width: 108,
              child: TextButton(
                style: TextButton.styleFrom(alignment: Alignment.center),
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLanguageService.text(context, 'Batal', 'Cancel')),
              ),
            ),
            SizedBox(
              width: 108,
              child: FilledButton(
                style: FilledButton.styleFrom(alignment: Alignment.center),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppLanguageService.text(context, 'Keluar', 'Exit')),
              ),
            ),
          ],
        ),
      );
      if (shouldExit == true && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _exitDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ActivityStartConfig? config = _activeRunConfig;
    return PopScope<Object?>(
      canPop: _showRunningPage,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || _showRunningPage) return;
        unawaited(_confirmExitApplication());
      },
      child: Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Offstage(
            offstage: _showRunningPage,
            child: TickerMode(
              enabled: !_showRunningPage,
              child: IndexedStack(index: _index, children: _pages),
            ),
          ),
          if (config != null)
            Offstage(
              offstage: !_showRunningPage,
              child: TickerMode(
                enabled: _showRunningPage,
                child: RunningPage(
                  key: ValueKey<int>(_runPageGeneration),
                  activityType: config.activityType,
                  environment: config.environment,
                  initialIntervalPlan: config.intervalPlan,
                  activityDetails: config.activityDetails,
                  targetDistanceKm: config.targetDistanceKm,
                  targetPaceSecondsPerKm: config.targetPaceSecondsPerKm,
                  plannedRoute: _plannedRoute,
                  paceNotificationsEnabled: config.paceNotificationsEnabled,
                  autoStart: true,
                  onExit: _exitRunningPage,
                  onMinimize: _minimizeRunningPage,
                  onSessionActiveChanged: _onRunningSessionActiveChanged,
                  isVisible: _showRunningPage,
                ),
              ),
            ),
          if (!_showRunningPage && _runningSessionActive)
            Positioned(
              left: 12,
              right: 12,
              bottom: 10,
              child: _activeSessionBanner(context),
            ),
        ],
      ),
      bottomNavigationBar: _showRunningPage
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _selectTab,
              destinations: _destinations(context),
            ),
      ),
    );
  }
}

