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
  // Penjadwalan pengingat tidak dijalankan sebelum tampilan pertama muncul.
  // Pada perangkat tertentu, membaca zona waktu dan memulihkan banyak jadwal
  // dapat membuat aplikasi terasa macet saat baru dibuka.
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
          onRecord: () => _selectTab(2),
          onHistory: () => _openAccountSection(1),
        ),
        RoutePlannerPage(active: _index == 1),
        ActivitySetupPage(
          key: _activityKey,
          onStart: _startActivity,
        ),
        MorePage(
          key: _moreKey,
          onOpenTimer: () => _openPage(const TimerPage()),
          onOpenCoach: () => _openPage(const AiCoachPage()),
          onOpenStrength: () => _openPage(const MusclePage()),
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

  Future<void> _startActivity(ActivityStartConfig config) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => RunningPage(
          activityType: config.activityType,
          environment: config.environment,
          initialIntervalPlan: config.intervalPlan,
          targetDistanceKm: config.targetDistanceKm,
          targetPaceSecondsPerKm: config.targetPaceSecondsPerKm,
          paceNotificationsEnabled: config.paceNotificationsEnabled,
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

