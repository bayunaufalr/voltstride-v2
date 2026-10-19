import 'package:flutter/material.dart';

/// Warna utama VoltStride. Tampilan dibuat netral, hitam dan putih,
/// agar data latihan menjadi fokus dan mudah disesuaikan lagi.
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

ThemeData buildVoltTheme() {
  const Color hitam = Color(0xFF111111);
  const Color putih = Color(0xFFFFFFFF);
  const Color abu = Color(0xFF666666);
  const Color garis = Color(0xFFD8D8D8);

  final ColorScheme skema = ColorScheme.fromSeed(
    seedColor: hitam,
    brightness: Brightness.light,
  ).copyWith(
    primary: hitam,
    onPrimary: putih,
    secondary: hitam,
    onSecondary: putih,
    surface: putih,
    onSurface: hitam,
    error: hitam,
    onError: putih,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: skema,
    scaffoldBackgroundColor: putih,
    appBarTheme: const AppBarTheme(
      backgroundColor: putih,
      foregroundColor: hitam,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: hitam,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: const CardThemeData(
      color: putih,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: garis),
      ),
    ),
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: hitam,
      displayColor: hitam,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF7F7F7),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: TextStyle(color: abu),
      hintStyle: TextStyle(color: Color(0xFF888888)),
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
        borderSide: BorderSide(color: hitam, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: hitam),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: hitam,
        foregroundColor: putih,
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: hitam,
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: hitam),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: hitam),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: putih,
      indicatorColor: const Color(0xFFEAEAEA),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          fontSize: 10,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: states.contains(WidgetState.selected) ? hitam : abu,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? hitam : abu,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(color: garis, thickness: 1),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: hitam,
      contentTextStyle: TextStyle(color: putih),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: hitam),
  );
}
