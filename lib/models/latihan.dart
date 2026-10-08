/// ============================================================
/// MODEL: KATEGORI OTOT DAN GERAKAN LATIHAN
/// ============================================================
/// Struktur data statis untuk halaman katalog otot (MusclePage).
///
/// Data latihan dipisah dari widget agar:
///   1. Halaman hanya memuat logika tampilan, data mudah diganti
///      lewat API di kemudian hari.
///   2. Bisa diuji tanpa perlu membuat widget sama sekali.
///   3. Struktur kategori lalu gerakan mudah dikembangkan: menambah
///      kategori "Punggung" cukup menambah satu entri di [katalogOtot].
///
/// Seluruh isi file ini adalah data murni, tanpa dependensi Flutter,
/// sehingga bisa dipakai juga oleh unit test murni.
class KategoriOtot {
  /// Nama kategori, misalnya "Lengan".
  final String nama;

  /// Emoji sebagai ikon visual pada grid.
  /// Emoji dipilih supaya tidak perlu bundling aset gambar dan tetap
  /// tajam di berbagai ukuran layar serta mode gelap.
  final String ikon;

  /// Deskripsi singkat grup otot yang dilatih, tampil di header halaman.
  final String deskripsi;

  /// Daftar gerakan latihan pada kategori ini.
  final List<GerakanLatihan> gerakan;

  KategoriOtot({
    required this.nama,
    required this.ikon,
    required this.deskripsi,
    required this.gerakan,
  });
}

/// ============================================================
/// MODEL: SATU GERAKAN LATIHAN
/// ============================================================
/// Satu gerakan latihan lengkap dengan petunjuk eksekusi dan
/// metadata untuk placeholder video tutorial.
class GerakanLatihan {
  /// Nama gerakan dalam bahasa Indonesia, misalnya "Biceps Curl".
  final String nama;

  /// Nama dalam bahasa Inggris untuk pencarian silang,
  /// misalnya "Dumbbell Curl".
  final String namaInggris;

  /// Grup otot utama yang menjadi target gerakan.
  final String targetOtot;

  /// Rekomendasi repetisi, misalnya "10-12x".
  final String repetisi;

  /// Rekomendasi jumlah set, misalnya "3 set".
  final String set;

  /// Petunjuk eksekusi singkat, ditampilkan sebagai caption di bawah
  /// container video placeholder.
  final String petunjuk;

  /// Level kesulitan dari 1 sampai 3:
  /// 1 Pemula, 2 Menengah, 3 Lanjut.
  final int level;

  /// Durasi video placeholder dalam detik.
  /// Belum ada video asli, jadi nilai ini hanya dipakai sebagai
  /// indikator durasi pada kartu (misalnya "0:45").
  final int durasiVideoDetik;

  GerakanLatihan({
    required this.nama,
    required this.namaInggris,
    required this.targetOtot,
    required this.repetisi,
    required this.set,
    required this.petunjuk,
    required this.level,
    required this.durasiVideoDetik,
  });

  /// Mengubah level angka menjadi label tekstual untuk ditampilkan.
  String get levelTeks {
    switch (level) {
      case 3:
        return 'Lanjut';
      case 2:
        return 'Menengah';
      default:
        return 'Pemula';
    }
  }

  /// Durasi video dalam format M:SS.
  String get durasiTeks {
    final int menit = durasiVideoDetik ~/ 60;
    final int detik = durasiVideoDetik % 60;
    return '$menit:${detik.toString().padLeft(2, '0')}';
  }
}

/// ============================================================
/// KATALOG STATIS KATEGORI OTOT
/// ============================================================
/// Daftar kategori yang dipakai MusclePage. Ini adalah satu-satunya
/// sumber kebenaran untuk konten katalog, sehingga menambah kategori
/// cukup dengan menambah satu entri ke list di bawah ini.
final List<KategoriOtot> katalogOtot = <KategoriOtot>[
  // ---------------- LENGAN ----------------
  KategoriOtot(
    nama: 'Lengan',
    ikon: '💪',
    deskripsi: 'Membangun dan mendefinisikan lengan atas serta lengan bawah.',
    gerakan: <GerakanLatihan>[
      GerakanLatihan(
        nama: 'Biceps Curl',
        namaInggris: 'Dumbbell Biceps Curl',
        targetOtot: 'Biceps brachii',
        repetisi: '10-12x',
        set: '3 set',
        petunjuk: 'Berdiri sambil memegang dumbbell di kedua tangan. Tekuk '
            'siku sampai beban mendokati dada, tanpa mengayunkan badan.',
        level: 1,
        durasiVideoDetik: 45,
      ),
      GerakanLatihan(
        nama: 'Triceps Pushdown',
        namaInggris: 'Cable Triceps Pushdown',
        targetOtot: 'Triceps brachii',
        repetisi: '12-15x',
        set: '3 set',
        petunjuk: 'Dekati mesin pulley, dorong batang ke bawah sampai lengan '
            'lurus, lalu kendalikan gerakan saat kembali ke posisi atas.',
        level: 2,
        durasiVideoDetik: 50,
      ),
      GerakanLatihan(
        nama: 'Hammer Curl',
        namaInggris: 'Hammer Curl',
        targetOtot: 'Brachialis dan Pronator',
        repetisi: '10-12x',
        set: '3 set',
        petunjuk: 'Pegang dumbbell dengan genggaman netral, lalu tekuk siku '
            'sambil menjaga siku tetap menempel di sisi tubuh.',
        level: 2,
        durasiVideoDetik: 40,
      ),
    ],
  ),

  // ---------------- BAHU ----------------
  KategoriOtot(
    nama: 'Bahu',
    ikon: '🏋️',
    deskripsi: 'Kekuatan dan kestabilan sendi bahu untuk postur tegak.',
    gerakan: <GerakanLatihan>[
      GerakanLatihan(
        nama: 'Shoulder Press',
        namaInggris: 'Overhead Shoulder Press',
        targetOtot: 'Deltoid',
        repetisi: '8-10x',
        set: '3 set',
        petunjuk: 'Duduk tegak lalu dorong dumbbell ke atas sampai lengan '
            'hampir lurus di atas kepala, tanpa bersandar ke belakang.',
        level: 2,
        durasiVideoDetik: 55,
      ),
      GerakanLatihan(
        nama: 'Lateral Raise',
        namaInggris: 'Lateral Dumbbell Raise',
        targetOtot: 'Deltoid lateral',
        repetisi: '12-15x',
        set: '3 set',
        petunjuk: 'Angkat dumbbell ke samping setinggi bahu dengan siku '
            'sedikit membengkok, jangan memakai ayunan momentum.',
        level: 1,
        durasiVideoDetik: 42,
      ),
      GerakanLatihan(
        nama: 'Face Pull',
        namaInggris: 'Cable Face Pull',
        targetOtot: 'Trapezius dan rotator cuff',
        repetisi: '15x',
        set: '3 set',
        petunjuk: 'Tarik tali ke arah wajah dengan siku tinggi, fokus pada '
            'kontrol gerakan dan kestabilan bahu.',
        level: 2,
        durasiVideoDetik: 48,
      ),
    ],
  ),

  // ---------------- DADA ----------------
  KategoriOtot(
    nama: 'Dada',
    ikon: '🫁',
    deskripsi: 'Pectoral untuk daya dorong dan menjaga postur lari '
        'tetap tegap.',
    gerakan: <GerakanLatihan>[
      GerakanLatihan(
        nama: 'Push Up',
        namaInggris: 'Push Up',
        targetOtot: 'Pectoralis major',
        repetisi: '15-20x',
        set: '3 set',
        petunjuk: 'Posisi plank dengan tangan selebar bahu. Turunkan dada '
            'mendekati lantai sambil menjaga tubuh tetap lurus.',
        level: 1,
        durasiVideoDetik: 38,
      ),
      GerakanLatihan(
        nama: 'Bench Press Dumbbell',
        namaInggris: 'Dumbbell Bench Press',
        targetOtot: 'Pectoralis major dan triceps',
        repetisi: '10-12x',
        set: '3 set',
        petunjuk: 'Tergeletak di bangku, turunkan dumbbell ke sisi dada lalu '
            'dorong ke atas hingga lengan lurus.',
        level: 2,
        durasiVideoDetik: 58,
      ),
      GerakanLatihan(
        nama: 'Fly Machine',
        namaInggris: 'Pec Deck Fly',
        targetOtot: 'Pectoralis',
        repetisi: '12-15x',
        set: '3 set',
        petunjuk: 'Rapatkan kedua handle di depan dada dengan siku sedikit '
            'membengkok, lalu rasakan regangan di area dada.',
        level: 1,
        durasiVideoDetik: 44,
      ),
    ],
  ),

  // ---------------- CORE ----------------
  KategoriOtot(
    nama: 'Core',
    ikon: '🧘',
    deskripsi: 'Stabilitas inti tubuh yang menopang teknik lari tetap baik.',
    gerakan: <GerakanLatihan>[
      GerakanLatihan(
        nama: 'Plank',
        namaInggris: 'Forearm Plank',
        targetOtot: 'Transverse abdominis',
        repetisi: '30-60 detik',
        set: '3 set',
        petunjuk: 'Berjongkok di atas siku dengan tubuh lurus dari kepala '
            'sampai tumit. Jaga pinggang tetap ratar dan tahan.',
        level: 1,
        durasiVideoDetik: 35,
      ),
      GerakanLatihan(
        nama: 'Russian Twist',
        namaInggris: 'Russian Twist',
        targetOtot: 'Oblique',
        repetisi: '20x (10 per sisi)',
        set: '3 set',
        petunjuk: 'Duduk dengan lutut ditekuk, lalu putar badan sambil '
            'mengayunkan bola ke arah sisi kiri dan kanan secara bergantian.',
        level: 2,
        durasiVideoDetik: 40,
      ),
      GerakanLatihan(
        nama: 'Leg Raise',
        namaInggris: 'Hanging Leg Raise',
        targetOtot: 'Lower abdominal',
        repetisi: '12-15x',
        set: '3 set',
        petunjuk: 'Gantung pada tiang pull up bar, naikkan kaki hingga '
            'sejajar lantai tanpa mengayunkan badan.',
        level: 3,
        durasiVideoDetik: 47,
      ),
    ],
  ),

  // ---------------- PAHA ----------------
  KategoriOtot(
    nama: 'Paha',
    ikon: '🦵',
    deskripsi: 'Kekuatan kaki untuk dorongan (propulsion) dan ketahanan.',
    gerakan: <GerakanLatihan>[
      GerakanLatihan(
        nama: 'Squat',
        namaInggris: 'Bodyweight Squat',
        targetOtot: 'Quadriceps dan glutes',
        repetisi: '15-20x',
        set: '3 set',
        petunjuk: 'Berdiri dengan kaki selebar bahu, turunkan paha hingga '
            'sejajar lantai, lalu dorong tumit ke depan.',
        level: 1,
        durasiVideoDetik: 52,
      ),
      GerakanLatihan(
        nama: 'Lunges',
        namaInggris: 'Walking Lunge',
        targetOtot: 'Quadriceps dan hamstrings',
        repetisi: '12 per kaki',
        set: '3 set',
        petunjuk: 'Maju satu langkah, turunkan lutut belakang mendekati '
            'lantai, lalu naikkan kembali dengan dorongan kaki depan.',
        level: 2,
        durasiVideoDetik: 46,
      ),
      GerakanLatihan(
        nama: 'Glute Bridge',
        namaInggris: 'Barbell Glute Bridge',
        targetOtot: 'Gluteus maximus',
        repetisi: '15-20x',
        set: '3 set',
        petunjuk: 'Tergeletak telungkup, letakkan bar di atas pinggul, lalu '
            'dorong pinggul ke atas sampai otot gluteus menguncup.',
        level: 1,
        durasiVideoDetik: 39,
      ),
    ],
  ),
];