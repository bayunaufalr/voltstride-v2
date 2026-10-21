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

  static const Color latar = Color(0xFFF5F5F1);
  static const Color kartu = Color(0xFFFFFEFC);
  static const Color surface = Color(0xFFEBEEE9);
  static const Color border = Color(0xFFD9DED8);

  static const Color aksen = Color(0xFF477561);
  static const Color aksenGelap = Color(0xFF315444);
  static const Color hijau = Color(0xFF587B63);
  static const Color kuning = Color(0xFF806A3D);
  static const Color merah = Color(0xFF99564F);
  static const Color violet = Color(0xFF716681);

  static const Color teksPutih = Color(0xFFFFFFFF);
  static const Color teksAbu = Color(0xFF69746D);
  static const Color teksRedup = Color(0xFF8C968F);
}

ThemeData buildVoltTheme({Brightness brightness = Brightness.light}) {
  final bool gelap = brightness == Brightness.dark;
  // Hijau-abu yang lembut mengurangi silau tanpa membuat teks kehilangan kontras.
  final Color latar = gelap ? const Color(0xFF171B19) : const Color(0xFFF5F5F1);
  final Color permukaan = gelap ? const Color(0xFF202622) : const Color(0xFFFFFEFC);
  final Color permukaanLembut =
      gelap ? const Color(0xFF29312C) : const Color(0xFFEBEEE9);
  final Color teks = gelap ? const Color(0xFFE9EDE9) : const Color(0xFF29342D);
  final Color teksSekunder =
      gelap ? const Color(0xFFB3BDB6) : const Color(0xFF69746D);
  final Color garis = gelap ? const Color(0xFF3C4640) : const Color(0xFFD9DED8);
  final Color primer = gelap ? const Color(0xFFA5C7B2) : const Color(0xFF477561);
  final Color teksDiPrimer = gelap ? const Color(0xFF202A23) : Colors.white;
  final Color permukaanTinggi =
      gelap ? const Color(0xFF303833) : const Color(0xFFE5ECE6);

  final ColorScheme skema = ColorScheme.fromSeed(
    seedColor: primer,
    brightness: brightness,
  ).copyWith(
    primary: primer,
    onPrimary: teksDiPrimer,
    secondary: gelap ? const Color(0xFFB5C9BA) : const Color(0xFF647E6C),
    onSecondary: gelap ? const Color(0xFF222B25) : Colors.white,
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
      indicatorColor: gelap ? const Color(0xFF2B4033) : const Color(0xFFE0E8E0),
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
      backgroundColor: gelap ? const Color(0xFFE9EDE9) : const Color(0xFF315444),
      contentTextStyle: TextStyle(
        color: gelap ? const Color(0xFF27362D) : Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primer),
  );
}
