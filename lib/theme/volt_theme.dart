import 'package:flutter/material.dart';

/// Palet warna dan tema global VoltStride.
///
/// Warna dasar, aksen, status, dan teks didefinisikan di satu tempat supaya
/// tampilan antarhalaman tetap konsisten dan perubahan desain lebih mudah.
class VoltWarna {
  VoltWarna._(); // constructor privat: kelas ini kumpulan konstanta saja

  // --- Warna dasar / latar -------------------------------------
  /// Latar aplikasi paling belakang (di balik Scaffold).
  static const Color latar = Color(0xFF0F172A);

  /// Warna isi Card, sedikit lebih terang dari [latar] supaya
  /// tidak perlu border tegas untuk memisahkan lapisan UI.
  static const Color kartu = Color(0xFF1E293B);

  /// Warna lapisan ketiga: input field, chip, container dalam kartu.
  static const Color surface = Color(0xFF283548);

  /// Garis pemisah tipis antar kartu.
  static const Color border = Color(0xFF334155);

  // --- Aksen utama ---------------------------------------------
  /// Biru neon: warna aksen aplikasi.
  static const Color aksen = Color(0xFF38BDF8);

  /// Versi lebih gelap dari [aksen], untuk gradient dan pressed state.
  static const Color aksenGelap = Color(0xFF0EA5E9);

  // --- Warna status --------------------------------------------
  static const Color hijau = Color(0xFF22C55E);
  static const Color kuning = Color(0xFFEAB308);
  static const Color merah = Color(0xFFEF4444);
  static const Color violet = Color(0xFFA855F7);

  // --- Warna teks ----------------------------------------------
  static const Color teksPutih = Color(0xFFF8FAFC);
  static const Color teksAbu = Color(0xFF94A3B8);
  static const Color teksRedup = Color(0xFF64748B);
}

/// Membangun [ThemeData] gelap VoltStride untuk aplikasi.
///
/// Dipanggil sekali di `MaterialApp(theme: ...)`, bukan di setiap widget,
/// supaya tidak ada alokasi objek berulang saat hot reload.
ThemeData buildVoltTheme() {
  // ColorScheme menentukan warna default komponen Material
  // (AppBar, dialog, snackbar, dan lain-lain).
  final ColorScheme skema = const ColorScheme.dark().copyWith(
    primary: VoltWarna.aksen,
    onPrimary: VoltWarna.latar,
    secondary: VoltWarna.violet,
    surface: VoltWarna.kartu,
    onSurface: VoltWarna.teksPutih,
    error: VoltWarna.merah,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: skema,
    scaffoldBackgroundColor: VoltWarna.latar, // latar slate-dark

    appBarTheme: const AppBarTheme(
      backgroundColor: VoltWarna.latar, // menyatu dengan latar, kesan modern
      surfaceTintColor: Colors.transparent, // hilangkan tint elevation M3
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: VoltWarna.teksPutih,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
      ),
    ),

    // Gaya Card global supaya semua kartu seragam tanpa menulis ulang
    // di tiap file halaman.
    cardTheme: CardThemeData(
      color: VoltWarna.kartu,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: VoltWarna.border),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VoltWarna.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      // Label mengambang (M3): menempel di atas input saat diisi.
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelStyle: const TextStyle(color: VoltWarna.teksAbu),
      hintStyle: const TextStyle(color: VoltWarna.teksRedup),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VoltWarna.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VoltWarna.border),
      ),
      // Border biru neon saat input aktif: feedback visual bahwa kolom
      // ini sedang dipakai AI Coach.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VoltWarna.aksen, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: VoltWarna.merah),
      ),
    ),

    // Gaya tombol utama, dipakai untuk aksi penting seperti
    // "Mulai Lari" dan "Rancang Latihan AI".
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VoltWarna.aksen,
        foregroundColor: VoltWarna.latar,
        minimumSize: const Size.fromHeight(52), // tinggi sentuh >= 48dp
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VoltWarna.aksen,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: VoltWarna.aksen),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VoltWarna.kartu,
      indicatorColor: VoltWarna.aksen.withOpacity(0.18),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w800
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? VoltWarna.aksen
              : VoltWarna.teksAbu,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 24,
          color: states.contains(WidgetState.selected)
              ? VoltWarna.aksen
              : VoltWarna.teksAbu,
        ),
      ),
    ),

    dividerTheme: const DividerThemeData(color: VoltWarna.border, thickness: 1),
  );
}