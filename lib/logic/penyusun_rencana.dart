import '../models/profil_pelari.dart';
import '../models/rencana_latihan.dart';

/// ============================================================
/// PENYUSUN RENCANA LATIHAN
/// ============================================================
/// Mengubah [ProfilPelari] menjadi program latihan multi-minggu.
///
/// Ini adalah "pelatih program" lokal di aplikasi. Fungsinya
/// menghasilkan kerangka yang benar secara fisiologis, lalu online
/// coach boleh memperkaya atau menyesuaikan hasil ini dengan konteks
/// tambahan seperti riwayat cedera, jadwal, atau kondisi lapangan.
///
/// Prinsip periodisasi yang dipakai:
///   1. FASE BUILD  : volume dan intensitas naik bertahap.
///   2. FASE PEAK   : volume mulai turun, intensitas tetap tinggi.
///   3. FASE TAPER  : volume turun drastis, latihan tetap quality.
///   4. FASE EVALUASI : balapan uji coba sebagai tes.
///
/// Aturan besi yang tidak boleh dilanggar:
///   - Penambahan volume maksimal 10 persen per minggu.
///   - Ada minimal satu hari istirahat penuh setiap minggu.
///   - Sesi quality (interval dan tempo) maksimal dua kali per minggu.
///   - Long run maksimal satu kali per minggu.
class PenyusunRencana {
  PenyusunRencana._(); // kelas utilitas, tidak perlu instance

  /// Batas maksimum penambahan volume mingguan, dalam persen.
  ///
  /// Aturan 10 persen ini berasal dari fisiologi jaringan otot dan
  /// sistem kardiovaskular yang butuh waktu adaptasi. Melewatinya
  /// adalah penyebab cedera paling umum pada pelari rekreasi.
  static const double maksVolumePerMinggu = 0.10;

  /// Pengali volume dasar terhadap jarak target, per jarak balapan.
  ///
  /// Pelari marathon butuh volume dasar lebih kecil dari pelari 5K
  /// karena intensitas yang jauh lebih tinggi sudah memberi beban
  /// aerob yang cukup. Pelari 5K justru butuh volume lebih besar
  /// supaya bisa menahan intensitas tinggi itu.
  static double _pengaliVolumeDasar(double jarakTargetKm) {
    if (jarakTargetKm <= 5.0) return 1.60;
    if (jarakTargetKm <= 10.0) return 1.50;
    if (jarakTargetKm <= 21.1) return 1.25;
    return 1.05;
  }

  /// Menentukan jumlah minggu program dari jarak target pelari.
  ///
  /// Alasan: jarak target yang lebih panjang butuh waktu adaptasi
  /// aerob yang jauh lebih panjang. Marathon butuh 16 sampai 20 minggu,
  /// sedangkan 5K bisa cukup 6 sampai 8 minggu.
  static int tentukanJumlahMinggu(double jarakTargetKm) {
    if (jarakTargetKm <= 5.0) return 8;
    if (jarakTargetKm <= 10.0) return 10;
    if (jarakTargetKm <= 21.1) return 14;
    return 18;
  }

  /// Membangun program latihan lengkap dari [ProfilPelari].
  static RencanaLatihan susun(ProfilPelari profil) {
    final int jumlahMinggu = tentukanJumlahMinggu(profil.targetJarakKm);

    // Volume dasar dihitung sekali, lalu dinaikkan bertahap per minggu.
    final double volumeDasar =
        profil.targetJarakKm * _pengaliVolumeDasar(profil.targetJarakKm);

    // Panjang fase build: 60 persen dari total minggu.
    // Dua minggu pertama dipegang sebagai fase build, tiga minggu
    // terakhir sebagai taper dan evaluasi.
    final int mingguBuild = (jumlahMinggu * 0.6).round();
    final int mingguTaper = 3;

    final List<MingguLatihan> daftarMinggu = <MingguLatihan>[];

    // Volume berjalan, dipantau ulang setiap minggu.
    double volumeMingguIni = volumeDasar;

    for (int m = 1; m <= jumlahMinggu; m++) {
      // Menentukan fase minggu ini dari posisinya dalam program.
      String fase;
      String tema;

      if (m == jumlahMinggu) {
        // Minggu terakhir adalah hari balapan.
        fase = 'evaluasi';
        tema = 'Hari Balapan';
      } else if (m > jumlahMinggu - mingguTaper) {
        // Tiga minggu terakhir: volume turun drastis.
        fase = 'taper';
        tema = 'Taper';
        // Volume dikurangi 40 persen terhadap volume puncak.
        volumeMingguIni *= 0.60;
      } else if (m > mingguBuild) {
        // Setelah fase build: volume mulai turun, intensitas naik.
        fase = 'peak';
        tema = 'Peak';
        volumeMingguIni *= 0.88;
      } else {
        // Fase build: volume naik maksimal 10 persen per minggu.
        fase = 'build';
        tema = 'Build';
        // Minggu 1 memakai volume dasar apa adanya.
        if (m > 1) {
          volumeMingguIni *= (1.0 + maksVolumePerMinggu);
        }
      }

      // Jadwal sesi dibuat ulang tiap minggu karena volume dan fase berubah.
      final List<SesiLatihan> sesi = _susunSesiMinggu(
        fase: fase,
        volumeKm: volumeMingguIni,
        profil: profil,
      );

      daftarMinggu.add(MingguLatihan(
        nomor: m,
        tema: tema,
        fase: fase,
        sesi: sesi,
      ));
    }

    // Ringkasan satu kalimat untuk header UI.
    final String jarakTeks = profil.targetJarakKm.toStringAsFixed(0);
    final String puncakTeks = (volumeDasar * 1.35).toStringAsFixed(0);
    final String ringkasan = '$jumlahMinggu minggu menuju target '
        '$jarakTeks KM. Volume puncak $puncakTeks KM per minggu.';

    return RencanaLatihan(
      tujuan: 'Target ${profil.targetJarakKm.toStringAsFixed(0)} KM '
          'dengan pace ${_formatPace(profil.targetPaceAdaptifDetik)} per km',
      jumlahMinggu: jumlahMinggu,
      minggu: daftarMinggu,
      ringkasan: ringkasan,
    );
  }

  /// Menyusun daftar sesi untuk satu minggu.
  ///
  /// Komposisi hari tetap, hanya volume dan intensitas yang berubah
  /// mengikuti fase program. Susunan hari:
  ///
  ///   Senin    : Easy run + strength ringan
  ///   Selasa   : Interval (sesi quality 1)
  ///   Rabu     : Easy run
  ///   Kamis    : Tempo (sesi quality 2)
  ///   Jumat    : Rest / strength
  ///   Sabtu    : Long run
  ///   Minggu   : Recovery easy
  static List<SesiLatihan> _susunSesiMinggu({
    required String fase,
    required double volumeKm,
    required ProfilPelari profil,
  }) {
    // Pada fase taper, jumlah sesi quality dikurangi agar tubuh benar-benar
    // pulih sebelum balapan.
    final bool adaInterval = fase != 'taper';
    final bool adaTempo = fase != 'taper';

    // Pembagian volume ke sesi easy.
    // Distribusi 25 persen, 15 persen, 40 persen sudah lazim dalam
    // periodisasi: volume long run paling besar, volume quality paling kecil.
    final double kmEasy1 = volumeKm * 0.25;
    final double kmEasy2 = volumeKm * 0.15;
    final double kmRecovery = volumeKm * 0.20;
    final double kmLong = fase == 'taper' ? volumeKm * 0.45 : volumeKm * 0.40;

    final List<SesiLatihan> sesi = <SesiLatihan>[];

    // --- Senin: easy run + strength ---
    sesi.add(SesiLatihan(
      nama: 'Easy Run',
      hari: 1,
      jarakKm: kmEasy1,
      durasiMenit: (kmEasy1 * profil.petaZona.paceEasy) / 60.0,
      paceDetik: profil.petaZona.paceEasy,
      zonaJantung: 'Recovery',
      instruksi: 'Lari santai dengan napas longgar. Tutup dengan latihan '
          'strength ringan (plank, leg raise, core) selama 20 menit.',
    ));

    // --- Selasa: interval ---
    if (adaInterval) {
      // Struktur interval: 400 meter cepat, 200 meter pemulihan.
      // Total repeat dihitung dari porsi waktu yang dialokasikan.
      final double porsiMenit = 35.0;
      final int jumlahRepetisi = fase == 'peak' ? 8 : 6;
      sesi.add(SesiLatihan(
        nama: 'Interval $jumlahRepetisi x 400m',
        hari: 2,
        jarakKm: null, // sesi berbasis durasi, bukan jarak
        durasiMenit: porsiMenit,
        paceDetik: profil.petaZona.paceInterval,
        zonaJantung: 'VO2 Max',
        instruksi: 'Pemanasan 10 menit, lalu $jumlahRepetisi x 400 meter '
            'pada pace ${_formatPace(profil.petaZona.paceInterval)} dengan '
            'istirahat 200 meter recovery jog, tutup pendinginan 10 menit.',
      ));
    } else {
      // Pada taper, interval diganti easy agar tidak ada beban tinggi.
      sesi.add(SesiLatihan(
        nama: 'Easy Run',
        hari: 2,
        jarakKm: volumeKm * 0.15,
        durasiMenit: 25,
        paceDetik: profil.petaZona.paceEasy,
        zonaJantung: 'Recovery',
        instruksi: 'Minggu taper: ganti interval dengan lari easy 25 menit '
            'agar sistem saraf punya waktu memulih.',
      ));
    }

    // --- Rabu: easy run ---
    sesi.add(SesiLatihan(
      nama: 'Easy Run',
      hari: 3,
      jarakKm: kmEasy2,
      durasiMenit: (kmEasy2 * profil.petaZona.paceEasy) / 60.0,
      paceDetik: profil.petaZona.paceEasy,
      zonaJantung: 'Recovery',
      instruksi: 'Lari ringan. Fokus pada pemulihan dan jaga napas.',
    ));

    // --- Kamis: tempo ---
    if (adaTempo) {
      sesi.add(SesiLatihan(
        nama: 'Tempo Run',
        hari: 4,
        jarakKm: null,
        durasiMenit: fase == 'peak' ? 50 : 40,
        paceDetik: profil.petaZona.paceTempo,
        zonaJantung: 'Tempo',
        instruksi: 'Lari kontinu di pace '
            '${_formatPace(profil.petaZona.paceTempo)} selama '
            '${fase == 'peak' ? 50 : 40} menit. Jaga detak jantung di '
            'zona ${profil.zonaTempo.rentangTeks} dan jaga napas.',
      ));
    } else {
      sesi.add(SesiLatihan(
        nama: 'Recovery Run',
        hari: 4,
        jarakKm: volumeKm * 0.15,
        durasiMenit: 20,
        paceDetik: profil.petaZona.paceEasy,
        zonaJantung: 'Recovery',
        instruksi: 'Lari sangat santai 20 menit, atau jalan cepat jika kaki '
            'masih pegang.',
      ));
    }

    // --- Jumat: rest / strength ---
    sesi.add(SesiLatihan(
      nama: 'Rest + Strength',
      hari: 5,
      jarakKm: null,
      durasiMenit: 30,
      instruksi: 'Hari tanpa lari. Latihan strength kaki dan core 30 menit. '
          'Tidur minimal 7 jam adalah bagian dari program ini.',
    ));

    // --- Sabtu: long run ---
    sesi.add(SesiLatihan(
      nama: 'Long Run',
      hari: 6,
      jarakKm: kmLong,
      durasiMenit: (kmLong * profil.petaZona.paceLongRun) / 60.0,
      paceDetik: profil.petaZona.paceLongRun,
      zonaJantung: 'Aerobic',
      instruksi: 'Sesi kunci minggu ini. Lari ${kmLong.toStringAsFixed(1)} KM '
          'dengan pace ${_formatPace(profil.petaZona.paceLongRun)}. Bawa '
          'air dan makanan ringan. Latih power kedua kaki setelah lari.',
    ));

    // --- Minggu: recovery easy ---
    sesi.add(SesiLatihan(
      nama: 'Recovery Run',
      hari: 7,
      jarakKm: kmRecovery,
      durasiMenit: (kmRecovery * profil.petaZona.paceEasy) / 60.0,
      paceDetik: profil.petaZona.paceEasy,
      zonaJantung: 'Recovery',
      instruksi: 'Lari santai ${kmRecovery.toStringAsFixed(1)} KM. Aktivitas '
          'ringan, biarkan tubuh menyerap beban latihan minggu ini.',
    ));

    return sesi;
  }

  /// Format detik menjadi "M'SS" untuk ditampilkan di instruksi.
  static String _formatPace(int detik) {
    final int menit = detik ~/ 60;
    final int sisa = detik % 60;
    return "$menit'${sisa.toString().padLeft(2, '0')}\"";
  }
}
