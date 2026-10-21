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

/// Warna bersama untuk komponen yang masih memakai palet langsung.
class VoltWarna {
  VoltWarna._();

  static const Color latar = Color(0xFFF3F6F3);
  static const Color kartu = Color(0xFFFCFDFC);
  static const Color surface = Color(0xFFE8EEE9);
  static const Color border = Color(0xFFD5DED7);

  static const Color aksen = Color(0xFF356B54);
  static const Color aksenGelap = Color(0xFF244A39);
  static const Color hijau = Color(0xFF446B52);
  static const Color kuning = Color(0xFF80602B);
  static const Color merah = Color(0xFF924F4B);
  static const Color violet = Color(0xFF665781);

  static const Color teksPutih = Color(0xFFFFFFFF);
  static const Color teksAbu = Color(0xFF66776B);
  static const Color teksRedup = Color(0xFF87958B);
}

ThemeData buildVoltTheme({Brightness brightness = Brightness.light}) {
  final bool gelap = brightness == Brightness.dark;
  // Hijau-abu yang lembut mengurangi silau tanpa membuat teks kehilangan kontras.
  final Color latar = gelap ? const Color(0xFF121B16) : const Color(0xFFF3F6F3);
  final Color permukaan = gelap ? const Color(0xFF1B2720) : const Color(0xFFFCFDFC);
  final Color permukaanLembut =
      gelap ? const Color(0xFF26342B) : const Color(0xFFE8EEE9);
  final Color teks = gelap ? const Color(0xFFE7EFE8) : const Color(0xFF23362B);
  final Color teksSekunder =
      gelap ? const Color(0xFFB1C0B5) : const Color(0xFF66776B);
  final Color garis = gelap ? const Color(0xFF3A4B40) : const Color(0xFFD5DED7);
  final Color primer = gelap ? const Color(0xFF9AC8AC) : const Color(0xFF356B54);
  final Color teksDiPrimer = gelap ? const Color(0xFF17251C) : Colors.white;
  final Color permukaanTinggi =
      gelap ? const Color(0xFF2C3B31) : const Color(0xFFE5ECE6);

  final ColorScheme skema = ColorScheme.fromSeed(
    seedColor: primer,
    brightness: brightness,
  ).copyWith(
    primary: primer,
    onPrimary: teksDiPrimer,
    secondary: gelap ? const Color(0xFFB5C9BA) : const Color(0xFF607E6B),
    onSecondary: gelap ? const Color(0xFF18251C) : Colors.white,
    surface: permukaan,
    onSurface: teks,
    surfaceContainerHighest: permukaanTinggi,
    outline: garis,
    outlineVariant: garis,
    error: gelap ? const Color(0xFFFFB4AB) : const Color(0xFFAA4845),
    onError: gelap ? const Color(0xFF3A0908) : Colors.white,
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
    cardTheme: CardThemeData(
      color: permukaan,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: garis),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: garis),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primer, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: skema.error),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primer,
        foregroundColor: teksDiPrimer,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primer,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: garis),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: primer),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: latar,
      indicatorColor: gelap ? const Color(0xFF2B4033) : const Color(0xFFDCE9DF),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontSize: 10,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? primer : teksSekunder,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? primer : teksSekunder,
        );
      }),
    ),
    dividerTheme: DividerThemeData(color: garis, thickness: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: gelap ? const Color(0xFFE7EFE8) : const Color(0xFF244A39),
      contentTextStyle: TextStyle(
        color: gelap ? const Color(0xFF20352A) : Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primer),
  );
}
