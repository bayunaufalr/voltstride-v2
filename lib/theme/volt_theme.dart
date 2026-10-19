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

  static const Color latar = Color(0xFFFFFFFF);
  static const Color kartu = Color(0xFFFFFFFF);
  static const Color surface = Color(0xFFF5F5F5);
  static const Color border = Color(0xFFD8D8D8);

  static const Color aksen = Color(0xFF111111);
  static const Color aksenGelap = Color(0xFF333333);
  static const Color hijau = Color(0xFF555555);
  static const Color kuning = Color(0xFF777777);
  static const Color merah = Color(0xFF111111);
  static const Color violet = Color(0xFF666666);

  static const Color teksPutih = Color(0xFF111111);
  static const Color teksAbu = Color(0xFF666666);
  static const Color teksRedup = Color(0xFF888888);
}

ThemeData buildVoltTheme({Brightness brightness = Brightness.light}) {
  final bool gelap = brightness == Brightness.dark;
  final Color latar = gelap ? const Color(0xFF111111) : Colors.white;
  final Color permukaan = gelap ? const Color(0xFF1B1B1B) : Colors.white;
  final Color permukaanLembut =
      gelap ? const Color(0xFF252525) : const Color(0xFFF5F5F5);
  final Color teks = gelap ? const Color(0xFFF5F5F5) : const Color(0xFF111111);
  final Color teksSekunder =
      gelap ? const Color(0xFFBBBBBB) : const Color(0xFF666666);
  final Color garis = gelap ? const Color(0xFF444444) : const Color(0xFFD8D8D8);

  final ColorScheme skema = ColorScheme.fromSeed(
    seedColor: teks,
    brightness: brightness,
  ).copyWith(
    primary: teks,
    onPrimary: latar,
    secondary: teksSekunder,
    onSecondary: latar,
    surface: permukaan,
    onSurface: teks,
    error: gelap ? const Color(0xFFE0E0E0) : const Color(0xFF111111),
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
      backgroundColor: gelap ? const Color(0xFFF5F5F5) : const Color(0xFF111111),
      contentTextStyle: TextStyle(
        color: gelap ? const Color(0xFF111111) : Colors.white,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: teks),
  );
}
