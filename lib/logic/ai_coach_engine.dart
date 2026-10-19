import '../models/profil_pelari.dart';
import '../models/split_kilometer.dart';
import 'split_strategi.dart';

/// Mesin perhitungan lokal untuk profil dan target latihan pelari.
///
/// Inputnya meliputi umur, jarak target, target pace, dan pace 10 km terakhir.
/// Hasilnya mencakup pace adaptif, zona latihan, skor perkiraan, dan rencana
/// split. Nama "AI Coach" di sini merujuk pada aturan/perhitungan yang ditulis
/// di kode, bukan model bahasa generatif yang belajar atau menjawab bebas.
///
/// Fungsi-fungsinya tidak menyimpan state sesi dan tidak meminta data internet,
/// sehingga masukan yang sama menghasilkan keluaran yang sama.
class AICoachEngine {
  AICoachEngine._(); // kelas utilitas, tidak perlu diinstansiasi

  // ----------------------------------------------------------
  // BATAS KEAMANAN PROGRAM LATIHAN
  // ----------------------------------------------------------

  /// Batas perubahan pace yang diizinkan oleh perhitungan lokal, dalam persen.
  ///
  /// Angka ini adalah parameter heuristik di aplikasi, bukan prediksi pasti
  /// tentang perubahan kebugaran seseorang atau jaminan bebas cedera.
  static const double maksPersenPerMinggu = 0.03;

  /// Selisih minimum yang dipakai saat membandingkan pace target dengan
  /// hasil perhitungan adaptif. Satuan nilai ini adalah detik per kilometer.
  static const int minimumSelisihDetik = 10;

  /// Batas pace tercepat yang diterima perhitungan, yaitu 150 detik/km
  /// atau 2:30 per km. Nilai di bawah batas ini akan disesuaikan.
  static const int paceMinimalDetik = 150;

  /// Batas pace terlambat yang dipakai perhitungan, yaitu 420 detik/km
  /// atau 7:00 per km. Nilai di atas batas ini akan disesuaikan.
  static const int paceMaksimalDetik = 420;

  // ----------------------------------------------------------
  // ENTRY POINT
  // ----------------------------------------------------------
  /// Menghitung [ProfilPelari] lengkap dari empat input mentah pelari.
  ///
  /// Alur delapan langkah di bawah ini dibaca berurutan karena setiap
  /// langkah memakai hasil langkah sebelumnya.
  static ProfilPelari hitungProfil({
    required int umur,
    required double targetJarakKm,
    required int targetPaceDetik,
    required int pace10kTerakhirDetik,
  }) {
    // LANGKAH 1: Normalisasi input.
    // Semua nilai dijepit ke rentang aman. Tujuannya mencegah pembagian
    // dengan nilai negatif atau nol yang akan menghasilkan rasio pace absurd.
    final int umurAman = umur.clamp(10, 90);
    final int targetPace =
        targetPaceDetik.clamp(paceMinimalDetik, paceMaksimalDetik);
    final int paceAktual =
        pace10kTerakhirDetik.clamp(paceMinimalDetik, paceMaksimalDetik);
    final double jarak = targetJarakKm <= 0 ? 5.0 : targetJarakKm;

    // LANGKAH 2: HR max dan zona tempo.
    final int hrMax = _hitungHrMax(umurAman);
    final ZonaJantung zonaTempo = _zonaTempo(hrMax);

    // LANGKAH 3: Skor kebugaran dari pace 10KM aktual.
    final double skor = _hitungSkorKebugaran(paceAktual, umurAman);

    // LANGKAH 4: Hitung pace target berdasarkan target pengguna dan
    // perkiraan kemampuan dari pace 10 km terakhir.
    final int paceAdaptif = _hitungTargetPaceAdaptif(
      targetPace: targetPace,
      paceAktual: paceAktual,
      jarakKm: jarak,
    );

    // LANGKAH 5: Estimasi durasi finish dari jarak dan pace adaptif.
    final int durasi = _hitungEstimasiDurasi(jarak, paceAdaptif);

    // LANGKAH 6: Peta pace untuk tiap jenis latihan.
    final PetaZonaLatihan petaZona = _buatPetaZona(paceAdaptif);

    // LANGKAH 7: Rencana split per kilometer untuk balapan target.
    // Array ini sama yang ditampilkan di layar strategi split dan
    // dikirim sebagai field "splits" ke Strava.
    final List<SplitKilometer> split = SplitStrategi.buatRencanaSplit(
      jarakKm: jarak,
      targetPaceDetik: paceAdaptif,
    );

    // LANGKAH 8: Ringkasan saran dalam bahasa manusia untuk ditampilkan
    // di kartu hasil AI Coach.
    final String saran = _buatRingkasanSaran(
      selisih: paceAdaptif - targetPace,
      skor: skor,
      jarak: jarak,
    );

    return ProfilPelari(
      umur: umurAman,
      targetJarakKm: jarak,
      targetPaceDetik: targetPace,
      pace10kTerakhirDetik: paceAktual,
      hrMaxEstimasi: hrMax,
      zonaTempo: zonaTempo,
      skorKebugaran: skor,
      targetPaceAdaptifDetik: paceAdaptif,
      estimasiDurasiDetik: durasi,
      selisihVsTarget: paceAdaptif - targetPace,
      ringkasanSaran: saran,
      petaZona: petaZona,
      rencanaSplit: split,
    );
  }

  // ----------------------------------------------------------
  // AKSES PUBLIK RENCANA SPLIT
  // ----------------------------------------------------------
  /// Menghasilkan rencana split per kilometer dari sebuah [ProfilPelari]
  /// yang sudah dihitung.
  ///
  /// Fungsi ini adalah jembatan antara [hitungProfil] dan modul lain
  /// seperti [SimulatorBalapan] yang hanya membutuhkan daftar split,
  /// bukan profil lengkap.
  static List<SplitKilometer> buatRencanaSplitUntukProfil(ProfilPelari profil) {
    return SplitStrategi.buatRencanaSplit(
      jarakKm: profil.targetJarakKm,
      targetPaceDetik: profil.targetPaceAdaptifDetik,
    );
  }

  // ----------------------------------------------------------
  // HR MAX: RUMUS TANAKA
  // ----------------------------------------------------------
  /// Menghitung HR max estimasi dengan rumus Tanaka:
  ///
  ///   HRmax = 208 - (0.7 x umur)
  ///
  /// Rumus ini menghasilkan perkiraan, bukan pengukuran langsung.
  /// Nilai sebenarnya dapat berbeda antarindividu.
  static int _hitungHrMax(int umur) {
    return (208 - (0.7 * umur)).round();
  }

  // ----------------------------------------------------------
  // ZONA TEMPO
  // ----------------------------------------------------------
  /// Menentukan zona detak jantung tempo dari HR max.
  ///
  /// Rentang persentase ini merupakan aturan sederhana yang dipakai aplikasi
  /// untuk memberi label zona. Nilainya tidak menjamin latihan aman untuk
  /// setiap orang, terutama karena HR max di sini hanya perkiraan.
  static ZonaJantung _zonaTempo(int hrMax) {
    final int bawah = (hrMax * 0.80).round();
    final int plafon = (hrMax * 0.92).round();
    final int atas = (hrMax * 0.85).round().clamp(bawah + 1, plafon);
    return ZonaJantung(nama: 'Tempo', bawah: bawah, atas: atas);
  }

  // ----------------------------------------------------------
  // SKOR KEBUGARAN
  // ----------------------------------------------------------
  /// Menghitung skor kebugaran 0 sampai 100 dari pace 10KM aktual.
  ///
  /// Metodologi:
  ///   1. Pace 300 detik per km (5:00/km) menjadi baseline skor 70.
  ///   2. Setiap blok 5 detik lebih cepat menambah 2 poin.
  ///   3. Setiap blok 5 detik lebih lambat mengurangi 2 poin.
  ///   4. Koreksi umur di atas 30 tahun sebesar 0,3 poin per tahun,
  ///      karena VO2max menurun natural seiring usia meskipun latihan
  ///      bisa memperlambat penurunan itu.
  ///
  /// Hasil dijepit ke rentang 5 sampai 100 supaya tidak ekstrem.
  static double _hitungSkorKebugaran(int pace10k, int umur) {
    const int baselinePace = 300;
    const double baselineSkor = 70.0;

    // Selisih dalam unit blok 5 detik, bisa negatif kalau lebih lambat.
    final double blokSelisih = (baselinePace - pace10k) / 5.0;
    double skor = baselineSkor + (blokSelisih * 2.0);

    if (umur > 30) {
      skor -= (umur - 30) * 0.3;
    }

    return skor.clamp(5.0, 100.0);
  }

  // ----------------------------------------------------------
  // TARGET PACE ADAPTIF
  // ----------------------------------------------------------
  /// Menghitung target pace yang realistis dan bisa dicapai bertahap.
  ///
  /// Alur:
  ///   1. Ubah pace 10KM aktual menjadi "pace balapan natural" untuk
  ///      jarak target memakai race effort factor.
  ///   2. Bandingkan dengan ambisi pelari.
  ///   3. Tahan ambisi yang terlalu cepat, maksimal [maksPersenPerMinggu]
  ///      per minggu lebih cepat dari kemampuan saat ini.
  ///   4. Dorong sedikit lebih cepat dari ambisi kalau ambisi justru
  ///      terlalu lambat untuk kemampuan sekarang.
  static int _hitungTargetPaceAdaptif({
    required int targetPace,
    required int paceAktual,
    required double jarakKm,
  }) {
    // LANGKAH A: Konversi ke pace balapan natural.
    //
    // Faktor 0,94 dan faktor jarak di bawah adalah pendekatan sederhana
    // untuk memperkirakan pace balapan. Hasilnya bukan prediksi lomba yang
    // teruji untuk setiap pelari.
    //
    // Contoh dengan pace 10KM 5:00 (300 detik):
    //   10KM -> 300 x 0.94 x 0.96 = 271 detik (4:31)
    //   21KM -> 300 x 0.94 x 1.06 = 299 detik (4:59)
    //    5KM -> 300 x 0.94 x 0.92 = 259 detik (4:19)
    final double faktorJarak = _faktorJarak(jarakKm);
    final int paceBalapanNatural = (paceAktual * 0.94 * faktorJarak).round();

    // LANGKAH B: Hitung selisih ambisi terhadap kemampuan natural.
    // Nilai positif berarti target pengguna lebih lambat daripada estimasi.
    // Nilai negatif berarti target pengguna lebih cepat daripada estimasi.
    final int selisihAmbisi = targetPace - paceBalapanNatural;

    // LANGKAH C: Batas bawah perbaikan mingguan. Ini inti perhitungan.
    // Batasi seberapa jauh pace target boleh dipercepat oleh perhitungan.
    // Ini pagar logika aplikasi, bukan penilaian medis tentang risiko cedera.
    final double batasPerbaikan = paceBalapanNatural * maksPersenPerMinggu;
    final int batasBawah = (paceBalapanNatural - batasPerbaikan).round();

    // Mulai dari ambisi user, lalu koreksi ke atas bila terlalu cepat.
    int paceAdaptif = targetPace;
    if (paceAdaptif < batasBawah) {
      paceAdaptif = batasBawah;
    }

    // Kalau ambisi jauh lebih lambat dari kemampuan sekarang, beri
    // dorongan gentle:aksimal 5 persen lebih cepat dari pace natural.
    if (selisihAmbisi > 0) {
      final int batasDorong = (paceBalapanNatural * 1.05).round();
      paceAdaptif = paceAdaptif.clamp(batasDorong, paceMaksimalDetik);
    }

    // Pastikan selalu ada ruang progress minimal 10 detik per km.
    if (paceBalapanNatural - paceAdaptif < minimumSelisihDetik) {
      paceAdaptif = paceBalapanNatural - minimumSelisihDetik;
    }

    return paceAdaptif.clamp(paceMinimalDetik, paceMaksimalDetik);
  }

  // ----------------------------------------------------------
  // FAKTOR JARAK
  // ----------------------------------------------------------
  /// Faktor penyesuaian pace berdasarkan jarak balapan.
  ///
  /// Nilai di bawah 1,0 berarti pace harus lebih cepat dari pace 10KM
  /// (jarak pendek, effort lebih besar). Nilai di atas 1,0 berarti pace
  /// boleh lebih lambat (jarak panjang, share effort lebih rendah).
  ///
  /// Angka ini diturunkan dari tabel split standar dan race prediction
  /// Jack Daniels.
  static double _faktorJarak(double jarakKm) {
    if (jarakKm <= 5.0) return 0.92;
    if (jarakKm <= 10.0) return 0.96;
    if (jarakKm <= 21.1) return 1.06;
    if (jarakKm <= 42.2) return 1.12;
    return 1.15;
  }

  // ----------------------------------------------------------
  // ESTIMASI DURASI
  // ----------------------------------------------------------
  /// Estimasi durasi finish dalam detik.
  ///
  /// Rumus: durasi = jarak (km) x pace (detik per km).
  /// Karena satuan pace sudah detik per kilometer, hasilnya langsung detik.
  static int _hitungEstimasiDurasi(double jarakKm, int paceDetik) {
    return (jarakKm * paceDetik).round();
  }

  // ----------------------------------------------------------
  // PETA ZONA LATIHAN
  // ----------------------------------------------------------
  /// Membangun peta pace tiap jenis latihan dari race pace adaptif.
  ///
  /// Offset standar terhadap race pace (detik per km):
  ///   - Easy run    : race pace + 45 detik (lebih lambat)
  ///   - Tempo       : race pace - 12 detik (sedikit lebih cepat)
  ///   - Interval    : race pace - 45 detik (jauh lebih cepat)
  ///   - Long run    : race pace + 35 detik (mirip easy, volume besar)
  ///
  /// Struktur ini dipakai online coach untuk menyusun rencana mingguan,
  /// sehingga tidak ada sesi yang tanpa target pace.
  static PetaZonaLatihan _buatPetaZona(int racePaceDetik) {
    return PetaZonaLatihan(
      paceEasy: racePaceDetik + 45,
      paceTempo: (racePaceDetik - 12)
          .clamp(paceMinimalDetik, paceMaksimalDetik),
      paceInterval: (racePaceDetik - 45)
          .clamp(paceMinimalDetik, paceMaksimalDetik),
      paceLongRun: racePaceDetik + 35,
    );
  }

  // ----------------------------------------------------------
  // RINGKASAN SARAN
  // ----------------------------------------------------------
  /// Menyusun ringkasan saran bahasa manusia dari hasil perhitungan.
  ///
  /// Empat kondisi yang mungkin terjadi, dipilih berurutan dari yang paling
  /// menentukan (skor kebugaran rendah) sampai yang paling ringan.
  static String _buatRingkasanSaran({
    required int selisih,
    required double skor,
    required double jarak,
  }) {
    final int besaran = selisih.abs();

    if (skor < 40) {
      return 'Skor kebugaran ${skor.toStringAsFixed(0)} menunjukkan basis '
          'aerob belum kuat. Fokuskan 4 sampai 6 minggu pada volume ringan '
          'dengan sebagian besar lari di zona easy, sebelum menambah '
          'intensitas.';
    }

    if (besaran < 20) {
      return 'Target $jarak KM kamu realistis. Kuncinya konsistensi: jangan '
          'skip sesi easy, dan naikkan volume maksimal 10 persen per minggu '
          'agar aman dari cedera.';
    }

    if (besaran < 60) {
      return 'Target kamu menantang tapi masih mungkin. AI menahan target '
          'sebesar $besaran detik per km dari ambisi awal. Bangun aerob '
          'lewat interval ringan dan long run satu kali per minggu.';
    }

    return 'Selisih target cukup jauh dari kemampuan saat ini, sekitar '
        '$besaran detik per km. Rekomendasi: pilih satu target antara yang '
        'lebih realistis sebagai target utama, dan jadikan $jarak KM sebagai '
        'target jangka panjang yang didekati bertahap.';
  }
}