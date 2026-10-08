import 'split_kilometer.dart';

/// ============================================================
/// MODEL: PROFIL PELARI
/// ============================================================
/// "Kartu identitas parietal" pelari setelah AI Coach Engine memproses
/// input mentah (umur, target jarak, pace target, pace 10KM terakhir).
///
/// Semua field bersifat final karena objek ini immutable:
///   1. Aman dipakai lintas widget tanpa perlu StatefulWidget,
///   2. Mudah di-cache (bisa dibungkus memoization di kemudian hari),
///   3. Cocok langsung dikirim ke endpoint AI online sebagai JSON.
class ProfilPelari {
  // --- Input mentah dari form ----------------------------------
  /// Umur pelari (tahun). Memengaruhi HR max dan kelonggaran adaptif.
  final int umur;

  /// Jarak target yang diinginkan pelari (KM). Contoh: 5, 10, 21, 42.
  final double targetJarakKm;

  /// Pace target yang diariesakan pelari (detik per KM).
  /// Ini ambisi, belum tentu realistis; AI akan menyesuaikan.
  final int targetPaceDetik;

  /// Pace 10KM terakhir sebagai data aktual (detik per KM).
  final int pace10kTerakhirDetik;

  // --- Hasil turunan dari AI Coach Engine ------------------------
  /// HR max estimasi memakai rumus Tanaka: 208 - (0.7 x umur).
  /// Rumus ini lebih akurat daripada 220 - umur karena biasnya
  /// lebih kecil pada rentang usia 18 sampai 70 tahun.
  final int hrMaxEstimasi;

  /// Zona detak jantung target untuk latihan tempo dan interval.
  final ZonaJantung zonaTempo;

  /// Skor kebugaran 0..100, diturunkan dari pace 10KM aktual.
  /// Dipakai online coach untuk menilai seberapa dekat pelari
  /// dengan targetnya.
  final double skorKebugaran;

  /// Target pace REALISTIS setelah disesuaikan AI.
  /// Inilah yang dipakai simulasi balapan, bukan ambisi mentah.
  final int targetPaceAdaptifDetik;

  /// Perkiraan durasi finish (detik) untuk [targetJarakKm]
  /// memakai [targetPaceAdaptifDetik].
  final int estimasiDurasiDetik;

  /// Selisih pace adaptif terhadap ambisi pelari (detik).
  /// Nilai positif berarti AI menahan ambisi pelari (lebih lambat).
  final int selisihVsTarget;

  /// Ringkasan saran dalam bahasa manusia, misalnya:
  /// "Prioritaskan 6 minggu di zona easy untuk memperbesar basis aerob."
  final String ringkasanSaran;

  /// Target pace per jenis latihan (easy, tempo, interval, long run).
  final PetaZonaLatihan petaZona;

  /// Daftar split yang sudah di-generate AI untuk balapan target.
  final List<SplitKilometer> rencanaSplit;

  ProfilPelari({
    required this.umur,
    required this.targetJarakKm,
    required this.targetPaceDetik,
    required this.pace10kTerakhirDetik,
    required this.hrMaxEstimasi,
    required this.zonaTempo,
    required this.skorKebugaran,
    required this.targetPaceAdaptifDetik,
    required this.estimasiDurasiDetik,
    required this.selisihVsTarget,
    required this.ringkasanSaran,
    required this.petaZona,
    required this.rencanaSplit,
  });
}

/// ============================================================
/// MODEL: ZONA DETAK JANTUNG
/// ============================================================
/// Satu zona detak jantung, misalnya "Tempo".
/// Rentang dalam BPM, dihitung dari HR max estimasi.
class ZonaJantung {
  /// Nama zona untuk ditampilkan, misalnya "Recovery" atau "Tempo".
  final String nama;

  /// Batas bawah zona (BPM), inklusif.
  final int bawah;

  /// Batas atas zona (BPM), eksklusif.
  final int atas;

  ZonaJantung({
    required this.nama,
    required this.bawah,
    required this.atas,
  });

  /// Mengecek apakah satu nilai BPM berada di dalam zona ini.
  bool mengandung(int bpm) => bpm >= bawah && bpm < atas;

  /// Rentang zona dalam format "140-160 BPM".
  String get rentangTeks => '$bawah-$atas BPM';
}

/// ============================================================
/// MODEL: PETA ZONA LATIHAN
/// ============================================================
/// Setiap jenis latihan punya target pace sendiri:
///   - Easy run    : lebih lambat dari race pace, sekitar 15-30 detik
///   - Tempo       : sedikit lebih cepat dari race pace, sekitar 10-15 detik
///   - Interval    : jauh lebih cepat untuk repetition 400-800 meter
///   - Long run    : mirip easy run, tapi dengan volume jauh lebih besar
///
/// Semua nilai disimpan dalam detik per kilometer.
class PetaZonaLatihan {
  /// Pace untuk lari ringan atau recovery (detik/km).
  final int paceEasy;

  /// Pace untuk tempo atau threshold (detik/km).
  final int paceTempo;

  /// Pace untuk interval pendek (detik/km, biasanya sangat cepat).
  final int paceInterval;

  /// Pace untuk long run (detik/km, mendekati easy run).
  final int paceLongRun;

  PetaZonaLatihan({
    required this.paceEasy,
    required this.paceTempo,
    required this.paceInterval,
    required this.paceLongRun,
  });

  /// Mengambil pace untuk sebuah label latihan.
  /// Fallback ke [paceEasy] bila label tidak dikenali.
  int paceUntuk(String labelLatihan) {
    switch (labelLatihan.toLowerCase()) {
      case 'easy':
      case 'ringan':
        return paceEasy;
      case 'tempo':
      case 'threshold':
        return paceTempo;
      case 'interval':
        return paceInterval;
      case 'long run':
        return paceLongRun;
      default:
        return paceEasy;
    }
  }

  /// Ringkasan semua pace untuk ditampilkan di UI.
  String get ringkasan {
    String fmt(int detik) {
      final int m = detik ~/ 60;
      final int s = detik % 60;
      return "$m'${s.toString().padLeft(2, '0')}\"";
    }

    return 'Easy ${fmt(paceEasy)} | Tempo ${fmt(paceTempo)} | '
        'Interval ${fmt(paceInterval)} | Long ${fmt(paceLongRun)}';
  }
}