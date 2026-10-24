// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan tema disimpan di perangkat sehingga tetap diingat saat aplikasi dibuka lagi.
final ValueNotifier<ThemeMode> voltThemeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> loadVoltThemeMode() async {
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? saved = preferences.getString('voltstride_theme_mode');
    voltThemeModeNotifier.value = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {
    voltThemeModeNotifier.value = ThemeMode.system;
  }
}

Future<void> saveVoltThemeMode(ThemeMode mode) async {
  voltThemeModeNotifier.value = mode;
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await preferences.setString('voltstride_theme_mode', value);
  } catch (_) {
    // Tema tetap berubah untuk sesi ini meskipun penyimpanan perangkat gagal.
  }
}

/// Warna netral untuk bagian aplikasi yang belum membutuhkan warna khusus.
class VoltWarna {
  VoltWarna._();

  static bool get _gelap {
    final ThemeMode mode = voltThemeModeNotifier.value;
    if (mode == ThemeMode.dark) return true;
    if (mode == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
  }

  // Palet netral adaptif. Getter dipakai karena banyak widget lama mengakses
  // VoltWarna secara langsung; warna sekarang ikut mode tema tanpa warna
  // teks statis yang menghilang pada latar gelap.
  static Color get latar => _gelap
      ? const Color(0xFF141516)
      : const Color(0xFFF4F2ED);
  static Color get kartu => _gelap
      ? const Color(0xFF202123)
      : const Color(0xFFFCFBF8);
  static Color get surface => _gelap
      ? const Color(0xFF2B2C2E)
      : const Color(0xFFE9E7E1);
  static Color get border => _gelap
      ? const Color(0xFF4A4B4D)
      : const Color(0xFFD0CEC8);

  // Aksen hitam-putih dibalik agar tetap kontras pada kedua tema.
  static Color get aksen => _gelap
      ? const Color(0xFFF3F2EE)
      : const Color(0xFF202124);
  static Color get aksenGelap => _gelap
      ? const Color(0xFF2C2D2F)
      : const Color(0xFF3A3B3D);
  static Color get hijau => _gelap
      ? const Color(0xFFD2D2CF)
      : const Color(0xFF555659);
  static Color get kuning => _gelap
      ? const Color(0xFFC0C0BD)
      : const Color(0xFF6A6B6E);
  static Color get merah => _gelap
      ? const Color(0xFFF0EFEB)
      : const Color(0xFF292A2C);
  static Color get violet => _gelap
      ? const Color(0xFFCACAC7)
      : const Color(0xFF5B5C60);

  static Color get teksPutih => _gelap
      ? const Color(0xFFF4F2ED)
      : const Color(0xFF202124);
  static Color get teksAbu => _gelap
      ? const Color(0xFFC4C3BF)
      : const Color(0xFF5E5F62);
  static Color get teksRedup => _gelap
      ? const Color(0xFFA9A9A5)
      : const Color(0xFF707175);
}

ThemeData buildVoltTheme({Brightness brightness = Brightness.light}) {
  final bool gelap = brightness == Brightness.dark;
  // Palet ivory, milk-white, grey, black, dan charcoal.
  final Color latar = gelap
      ? const Color(0xFF141516)
      : const Color(0xFFF3F1EC);
  final Color permukaan = gelap
      ? const Color(0xFF202123)
      : const Color(0xFFFCFBF8);
  final Color permukaanLembut = gelap
      ? const Color(0xFF292A2C)
      : const Color(0xFFEAE8E2);
  final Color teks = gelap
      ? const Color(0xFFF2F1ED)
      : const Color(0xFF202124);
  final Color teksSekunder = gelap
      ? const Color(0xFFB7B6B1)
      : const Color(0xFF626264);
  final Color garis = gelap
      ? const Color(0xFF414245)
      : const Color(0xFFD6D3CC);

  final ColorScheme skema = ColorScheme.fromSeed(
    seedColor: teks,
    brightness: brightness,
  ).copyWith(
    primary: teks,
    onPrimary: latar,
    primaryContainer: permukaanLembut,
    onPrimaryContainer: teks,
    secondary: teksSekunder,
    onSecondary: permukaan,
    secondaryContainer: permukaanLembut,
    onSecondaryContainer: teks,
    tertiary: teksSekunder,
    onTertiary: permukaan,
    tertiaryContainer: permukaanLembut,
    onTertiaryContainer: teks,
    surface: permukaan,
    onSurface: teks,
    surfaceDim: latar,
    surfaceBright: permukaan,
    surfaceContainerLowest: gelap
        ? const Color(0xFF101112)
        : const Color(0xFFFFFFFF),
    surfaceContainerLow: gelap
        ? const Color(0xFF1A1B1D)
        : const Color(0xFFF8F7F3),
    surfaceContainer: permukaan,
    surfaceContainerHigh: gelap
        ? const Color(0xFF252628)
        : const Color(0xFFF0EEE8),
    surfaceContainerHighest: permukaanLembut,
    onSurfaceVariant: teksSekunder,
    outline: garis,
    outlineVariant: garis,
    surfaceTint: Colors.transparent,
    error: gelap ? const Color(0xFFE0E0E0) : const Color(0xFF202124),
    onError: gelap ? const Color(0xFF111111) : Colors.white,
    errorContainer: gelap
        ? const Color(0xFF303032)
        : const Color(0xFFE7E5DF),
    onErrorContainer: teks,
    inverseSurface: gelap
        ? const Color(0xFFF3F1EC)
        : const Color(0xFF202124),
    onInverseSurface: gelap
        ? const Color(0xFF202124)
        : const Color(0xFFF3F1EC),
    inversePrimary: teksSekunder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: skema,
    scaffoldBackgroundColor: latar,
    appBarTheme: AppBarTheme(
      backgroundColor: latar,
      foregroundColor: teks,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: teks,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: permukaan,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: teks,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(color: teks, fontSize: 14, height: 1.4),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: teks,
      unselectedLabelColor: teksSekunder,
      indicatorColor: teks,
      dividerColor: garis,
      labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: permukaan,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: teks),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: permukaan,
      modalBackgroundColor: permukaan,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    listTileTheme: ListTileThemeData(
      textColor: teks,
      iconColor: teksSekunder,
      tileColor: permukaan,
      selectedTileColor: permukaanLembut,
      subtitleTextStyle: TextStyle(color: teksSekunder),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: teks,
      foregroundColor: latar,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? teks : Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(latar),
      side: BorderSide(color: garis),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? teks : teksSekunder;
      }),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected) ? latar : teksSekunder;
      }),
      trackColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
        return states.contains(WidgetState.selected)
            ? teks
            : permukaanLembut;
      }),
      trackOutlineColor: WidgetStatePropertyAll<Color>(garis),
    ),
    cardTheme: CardThemeData(
      color: permukaan,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: garis),
      ),
    ),
    textTheme: (gelap ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
      bodyColor: teks,
      displayColor: teks,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: permukaanLembut,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: TextStyle(color: teksSekunder),
      hintStyle: TextStyle(color: teksSekunder),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: garis),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: teks, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: teks),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teks,
        foregroundColor: latar,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: teks,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: teks),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: teks),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: latar,
      indicatorColor: permukaanLembut,
      indicatorShape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontSize: 10,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? teks : teksSekunder,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? teks : teksSekunder,
        );
      }),
    ),
    dividerTheme: DividerThemeData(color: garis, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: gelap
          ? const Color(0xFFEAE8E2)
          : const Color(0xFF202124),
      contentTextStyle: TextStyle(
        color: gelap ? const Color(0xFF202124) : const Color(0xFFFCFBF8),
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: teks),
  );
}
