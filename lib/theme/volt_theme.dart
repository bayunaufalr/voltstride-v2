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

  static const Color latar = Color(0xFFF3F1EC);
  static const Color kartu = Color(0xFFFCFBF8);
  static const Color surface = Color(0xFFEAE8E2);
  static const Color border = Color(0xFFD6D3CC);

  static const Color aksen = Color(0xFF202124);
  static const Color aksenGelap = Color(0xFF3A3B3D);
  // Nama lama dipertahankan agar berkas lain tetap kompatibel; nilainya
  // sengaja tetap netral, tanpa aksen hijau, kuning, merah, atau ungu.
  static const Color hijau = Color(0xFF656568);
  static const Color kuning = Color(0xFF85847F);
  static const Color merah = Color(0xFF202124);
  static const Color violet = Color(0xFF747478);

  static const Color teksPutih = Color(0xFF202124);
  static const Color teksAbu = Color(0xFF626264);
  static const Color teksRedup = Color(0xFF85847F);
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
    secondary: teksSekunder,
    onSecondary: latar,
    tertiary: teksSekunder,
    onTertiary: latar,
    surface: permukaan,
    onSurface: teks,
    surfaceContainerHighest: permukaanLembut,
    onSurfaceVariant: teksSekunder,
    outline: garis,
    outlineVariant: garis,
    surfaceTint: Colors.transparent,
    error: gelap ? const Color(0xFFE0E0E0) : const Color(0xFF202124),
    onError: gelap ? const Color(0xFF111111) : Colors.white,
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
