/// Struktur data untuk program latihan beberapa minggu.
///
/// Satu rencana berisi tujuan, ringkasan, dan daftar minggu latihan. Setiap
/// minggu menyimpan fase program serta sesi yang dijadwalkan. File ini hanya
/// mendefinisikan bentuk datanya; aturan penyusunan jadwal berada di modul
/// perencana latihan.
class RencanaLatihan {
  /// Tujuan akhir program, ditulis bebas misalnya "10 KM di bawah 55 menit".
  final String tujuan;

  /// Total minggu program, termasuk Minggu Evaluasi.
  final int jumlahMinggu;

  /// Daftar isi program, diurut dari minggu 1 sampai minggu terakhir.
  final List<MingguLatihan> minggu;

  /// Ringkasan satu kalimat yang ditampilkan pada bagian atas program.
  final String ringkasan;

  RencanaLatihan({
    required this.tujuan,
    required this.jumlahMinggu,
    required this.minggu,
    required this.ringkasan,
  });
}

/// Data jadwal latihan untuk satu minggu dalam program.
class MingguLatihan {
  /// Nomor minggu, mulai dari 1.
  final int nomor;

  /// Tema minggu, misalnya "Build", "Peak", atau "Taper".
  /// Tema ini menentukan komposisi sesi lewat [fase].
  final String tema;

  /// Fase program, yang dipakai untuk menentukan jenis sesi.
  ///
  /// Nilai yang dipakai:
  ///   - 'build'   : volume dan intensitas naik bertahap
  ///   - 'peak'    : volume turun, intensitas tetap tinggi
  ///   - 'taper'   : volume dikurangi menjelang target
  ///   - 'evaluasi': sesi uji untuk menilai perkembangan
  final String fase;

  /// Jadwal sesi pada minggu ini, sudah terurut dari hari Senin.
  final List<SesiLatihan> sesi;

  MingguLatihan({
    required this.nomor,
    required this.tema,
    required this.fase,
    required this.sesi,
  });

  /// Total jarak mingguan dalam kilometer.
  ///
  /// Dijumlahkan dari jarak setiap sesi. Sesi tanpa target jarak dianggap nol.
  double get totalJarakKm {
    double total = 0;
    for (final SesiLatihan s in sesi) {
      // Sesi berbasis durasi (misalnya strength) tidak punya jarak,
      // jadi null dianggap nol agar penjumlahan tidak error.
      total += s.jarakKm ?? 0;
    }
    return total;
  }

  /// Total durasi latihan dalam menit.
  double get totalMenit {
    double total = 0;
    for (final SesiLatihan s in sesi) {
      total += s.durasiMenit;
    }
    return total;
  }
}

/// Data satu sesi latihan beserta target dan instruksinya.
class SesiLatihan {
  /// Nama sesi, misalnya "Easy Run", "Interval 6x800m", "Long Run".
  final String nama;

  /// Hari dalam seminggu (1 = Senin sampai 7 = Minggu).
  final int hari;

  /// Target jarak sesi dalam kilometer. Null berarti sesi berbasis
  /// durasi saja, misalnya latihan strength.
  final double? jarakKm;

  /// Target durasi sesi dalam menit.
  final double durasiMenit;

  /// Target pace untuk sesi ini, dalam detik per kilometer.
  /// Null untuk sesi tanpa target pace, misalnya strength.
  final int? paceDetik;

  /// Zona detak jantung yang dituju, kalau sesi berbasis HR.
  final String? zonaJantung;

  /// Instruksi lengkap yang ditulis dalam bahasa manusia.
  /// Ini yang ditampilkan ke pengguna, jadi gaya bahasanya santai
  /// tapi tetap teknis.
  final String instruksi;

  /// Keterangan sumber: 'AI' untuk hasil engine lokal,
  /// 'COACH' untuk hasil online coach.
  final String sumber;

  SesiLatihan({
    required this.nama,
    required this.hari,
    required this.durasiMenit,
    this.jarakKm,
    this.paceDetik,
    this.zonaJantung,
    required this.instruksi,
    this.sumber = 'AI',
  });

  /// Path untuk sesi berbasis jarak: durasi = jarak x pace.
  ///
  /// Mengembalikan null kalau sesi tidak punya target pace atau jarak.
  double? get durasiEstimasiMenit {
    if (jarakKm == null || paceDetik == null) return durasiMenit;
    return (jarakKm! * paceDetik!) / 60.0;
  }

  /// Teks ringkas untuk chip di UI, misalnya "Easy 6.0 km".
  String get ringkasan {
    final String jarak = jarakKm == null
        ? '${durasiMenit.toStringAsFixed(0)} mnt'
        : '${jarakKm!.toStringAsFixed(1)} km';
    return '$nama $jarak';
  }
}