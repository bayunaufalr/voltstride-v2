import '../models/split_kilometer.dart';

/// ============================================================
/// STRATEGI SPLIT PER KILOMETER
/// ============================================================
/// Menghasilkan rencana pace per kilometer untuk simulasi balapan.
///
/// Filosofi pacemaking yang dipakai di sini mengikuti prinsip yang
/// dipakai pelatih balapan profesional:Negative split adalah standar.
/// Balapan yang quickest dipecah sebagai berikut:
///
///   KM 1        : lebih lambat dari target,%\u2026 pemanasan
///   KM 2        : mulai stabil, mendekati target
///   KM tengah    : sedikit lebih cepat, menjaga zona kecepatan
///   3 KM terakhir : sprint, kick kuat menuju garis finis
///
/// Mengapa negative split (mulai pelan, finishing cepat) penting?
///   1. Sistem aerobik butuh waktu untuk mencapai detak jantung target.
///      Kalau mulai terlalu cepat, kilometer pertama akan dibayar
///      dengan kilometer terakhir yang terasa lebih berat.
///   2. Energi glycogen paling efficient di intensitas tempo, bukan di
///     KM 1 yang tergesa-gesa.
///   3. Secara psikologis, finishing dengan negative split memberi
///      kontrol ritme yang lebih baik di bagian akhir.
class SplitStrategi {
  SplitStrategi._(); // kelas utilitas, tidak perlu instance

  /// Pengali pace untuk kilometer 1 (pemanasan).
  ///
  /// 1,08 berarti 8 persen lebih lambat dari pace target. Angka ini
  /// cukup untuk memanaskan otot dan sistem kardiovaskular tanpa
  /// membuang banyak tenaga.
  static const double faktorPemanasan = 1.08;

  /// Pengali pace untuk kilometer 2 (stabilisasi).
  ///
  /// 1,01 berarti 1 persen lebih lambat, praktis sudah di target pace.
  static const double faktorStabilisasi = 1.01;

  /// Pengali pace untuk kilometer tengah (tempo).
  ///
  /// 0,97 berarti 3 persen lebih cepat dari target. Ini sweet spot
  /// untuk membangun lead tanpa menguras habis.
  static const double faktorTempo = 0.97;

  /// Pengali pace untuk tiga kilometer terakhir (sprint).
  ///
  /// 0,94 berarti 6 persen lebih cepat dari target. Added değil This
  /// adalah kick menuju garis finis, dan hanya diberikan bila pelari
  /// cukup kuat untuk^)speed.
  static const double faktorSprint = 0.94;

  /// Batas atas dan bawah pengali pace dalam persen.
  ///
  /// ### Kenapa ada batas ini?
  /// Tanpa batas, pelari dengan target pace yang sangat cepat bisa
  /// mendapat pengali yang membuat KM 1 menjadi lebih lambat dari
  /// 1,15 kali target, dan KM akhir menjadi lebih cepat dari 0,85 kali
  /// target. Kombinasi itu tidak realistis. Batas ±15 persen membuat
  /// kurva split masuk akal untuk semua tingkat kemampuan.
  static const double batasPengaliMinimum = 0.85;
  static const double batasPengaliMaksimum = 1.15;

  /// Menghasilkan rencana split lengkap untuk sebuah balapan.
  ///
  /// Parameter:
  ///   - [jarakKm]: jarak total balapan dalam kilometer.
  ///   - [targetPaceDetik]: pace target adaptif dalam detik per km.
  ///
  /// Mengembalikan daftar split per kilometer dengan waktu kumulatif.
  static List<SplitKilometer> buatRencanaSplit({
    required double jarakKm,
    required int targetPaceDetik,
  }) {
    // Jumlah kilometer bulat dibulatkan ke atas.
    // Contoh: jarak 10,2 KM menghasilkan 11 kilometer.
    final int jumlahKm = jarakKm.ceil();

    // Hasil akhir yang dikembalikan ke pemanggil.
    final List<SplitKilometer> hasil = <SplitKilometer>[];

    // Penanda waktu kumulatif. Semua split memakai ini, bukan
    // penjumlahan ulang per kilometer.
    int kumulatifDetik = 0;

    for (int km = 1; km <= jumlahKm; km++) {
      // Menentukan kilometer mana yang sedang aktif:
      //   - tiga terakhir : sprint menuju garis finis
      //   - sisanya       : tempo (diperlakukan sebagai else)
      //   - sisanya       : tempo (diperlakukan sebagaielse)
      final bool adalahSprint = km > jumlahKm - 3;

      // --- Memilih pengali pace sesuai fase balapan ---
      double pengali;
      String label;
      String catatan;

      if (km == 1) {
        // Kilometer 1: pemanasan.
        pengali = faktorPemanasan;
        label = 'PEMANASAN';
        catatan =
            'Mulai pelan untuk memanaskan sistem kardiovaskular. '
            'Jaga napas dalam dan ritme longgar.';
      } else if (km == 2) {
        // Kilometer 2: mulai stabil ke target.
        pengali = faktorStabilisasi;
        label = 'STABIL';
        catatan =
            'Masuk ke ritme balapan. Cari ritme napas yang bisa '
            'dijaga sampai kilometer 10.';
      } else if (adalahSprint) {
        // Tiga kilometer terakhir: sprint.
        pengali = faktorSprint;
        label = 'SPRINT';
        catatan =
            'Kick kuat menuju garis finis. Tempuh sebesar '
            'kemampuan, pertahankan postur tetap rileks.';
      } else {
        // Kilometer tengah: tempo.
        pengali = faktorTempo;
        label = 'TEMPO';
        catatan =
            'Sedikit lebih cepat dari target untuk menjaga zona '
            'kecepatan dan membangun lead.';
      }

      // --- Menerapkan batas pengali ---
      // Dijepit agar profil split tetap realistis untuk semua pelari.
      pengali = pengali.clamp(batasPengaliMinimum, batasPengaliMaksimum);

      // --- Menghitung pace kilometer ini ---
      final int paceKm = (targetPaceDetik * pengali).round();

      // --- Menghitung waktu kumulatif ---
      // Kumulatif dijumlahkan dari pace tiap kilometer, sehingga total
      // pada kilometer terakhir sama dengan jumlah seluruh pace.
      kumulatifDetik += paceKm;

      hasil.add(SplitKilometer(
        nomor: km,
        paceDetik: paceKm,
        waktuKumulatifDetik: kumulatifDetik,
        labelSegmen: label,
        catatanCoach: catatan,
      ));
    }

    return hasil;
  }

  /// Menghitung rata-rata pace yang benar-benar akan muncul dari rencana
  /// split di atas, dalam detik per kilometer.
  ///
  /// Ini bukan sama dengan pace target. Karena KM 1 pelan dan KM akhir
  /// cepat, rata-rata sebenarnya cenderung sedikit lebih cepat dari
  /// target. Fungsi ini dipakai untuk mengoreksi estimasi durasi finish.
  static double hitungPaceRataRataRencana(List<SplitKilometer> rencana) {
    if (rencana.isEmpty) return 0;

    int totalPaceDetik = 0;
    for (final SplitKilometer s in rencana) {
      totalPaceDetik += s.paceDetik;
    }

    return totalPaceDetik / rencana.length;
  }
}
