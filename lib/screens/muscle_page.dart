import 'package:flutter/material.dart';

import '../models/latihan.dart';
import '../services/app_language_service.dart';


bool _isEnglish(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'en';

String _categoryName(String name, bool english) {
  if (!english) return name;
  switch (name) {
    case 'Lengan': return 'Arms';
    case 'Bahu': return 'Shoulders';
    case 'Dada': return 'Chest';
    case 'Core': return 'Core';
    case 'Paha': return 'Legs';
    default: return name;
  }
}

String _categoryDescription(KategoriOtot category, bool english) {
  if (!english) return category.deskripsi;
  switch (category.nama) {
    case 'Lengan': return 'Build and define the upper and lower arms.';
    case 'Bahu': return 'Build shoulder strength and joint stability for an upright posture.';
    case 'Dada': return 'Strengthen the chest for pushing power and an upright running posture.';
    case 'Core': return 'Build core stability to support efficient running form.';
    case 'Paha': return 'Build leg strength for propulsion and endurance.';
    default: return category.deskripsi;
  }
}

String _exerciseName(GerakanLatihan exercise, bool english) =>
    english ? exercise.namaInggris : exercise.nama;

String _targetMuscles(GerakanLatihan exercise, bool english) => english
    ? exercise.targetOtot.replaceAll(' dan ', ' and ')
    : exercise.targetOtot;

String _repText(GerakanLatihan exercise, bool english) {
  if (!english) return exercise.repetisi;
  return exercise.repetisi
      .replaceAll(' detik', ' seconds')
      .replaceAll('per kaki', 'per leg')
      .replaceAll('per sisi', 'per side')
      .replaceAll('x (', ' reps (')
      .replaceAll(RegExp(r'x$'), ' reps');
}

String _setText(GerakanLatihan exercise, bool english) =>
    english ? exercise.set.replaceAll('set', 'sets') : exercise.set;

String _levelText(GerakanLatihan exercise, bool english) {
  if (!english) return exercise.levelTeks;
  switch (exercise.level) {
    case 3: return 'Advanced';
    case 2: return 'Intermediate';
    default: return 'Beginner';
  }
}

String _exerciseInstruction(GerakanLatihan exercise, bool english) {
  if (!english) return exercise.petunjuk;
  switch (exercise.nama) {
    case 'Biceps Curl':
      return 'Stand with a dumbbell in each hand. Bend your elbows to lift the weights toward your chest without swinging your body.';
    case 'Triceps Pushdown':
      return 'Stand at a cable machine and press the bar down until your arms are straight. Control the bar as it returns.';
    case 'Hammer Curl':
      return 'Hold the dumbbells with a neutral grip. Bend your elbows while keeping them close to your sides.';
    case 'Shoulder Press':
      return 'Sit upright and press the dumbbells overhead until your arms are nearly straight. Avoid leaning backward.';
    case 'Lateral Raise':
      return 'Raise the dumbbells out to the sides to shoulder height with slightly bent elbows. Avoid swinging the weights.';
    case 'Face Pull':
      return 'Pull the cable rope toward your face with your elbows raised. Keep the movement controlled and your shoulders stable.';
    case 'Push Up':
      return 'Start in a plank with your hands about shoulder-width apart. Lower your chest while keeping your body in a straight line.';
    case 'Bench Press Dumbbell':
      return 'Lie on a bench, lower the dumbbells beside your chest, then press them up until your arms are straight.';
    case 'Fly Machine':
      return 'Bring the handles together in front of your chest with slightly bent elbows, then return slowly to the starting position.';
    case 'Plank':
      return 'Support yourself on your forearms and keep your body in a straight line from head to heels. Keep your hips level.';
    case 'Russian Twist':
      return 'Sit with your knees bent and rotate your torso from side to side in a controlled motion.';
    case 'Leg Raise':
      return 'Hang from a pull-up bar and lift your legs toward hip height without swinging your body.';
    case 'Squat':
      return 'Stand with feet about shoulder-width apart. Lower your hips, then push through your feet to stand up.';
    case 'Lunges':
      return 'Step forward and lower your back knee toward the floor. Push through the front foot to return to standing.';
    case 'Glute Bridge':
      return 'Lie on your back with your knees bent and feet flat. Lift your hips until your shoulders, hips, and knees form a line.';
    default:
      return exercise.petunjuk;
  }
}

/// ============================================================
/// MUSCLE PAGE: KATALOG LATIHAN KEKUATAN
/// ============================================================
/// Halaman katalog latihan otot dengan lima kategori: Lengan, Bahu,
/// Dada, Core, dan Paha.
///
/// Dua tingkat navigasi:
///   1. Grid kategori responsif. Jumlah kolom menyesuaikan lebar
///      layar lewat [LayoutBuilder], sehingga 2 kolom di ponsel dan
///      4 kolom di tablet tanpa menulis layout terpisah.
///   2. Daftar tiga gerakan per kategori, plus container placeholder
///      video yang dibuka dengan [AnimatedSize].
///
/// Kenapa [AnimatedSize]?
///   Karena membuka container video mengubah tinggi halaman secara
///   besar. AnimatedSize menganimasikan perubahan tinggi itu sehingga
///   sehingga daftar tidak terasa "melompat". Kalau dipakai
///   [AnimatedContainer] biasa, yang teranimasikan hanya properti
///   visual seperti warna, bukan ukuran.
class MusclePage extends StatefulWidget {
  const MusclePage({super.key});

  @override
  State<MusclePage> createState() => _MusclePageState();
}

class _MusclePageState extends State<MusclePage> {
  /// Kategori yang sedang dibuka, atau null kalau di layar katalog.
  ///
  /// Menyimpan nama, bukan objek, supaya tampilan bisa dibangun ulang
  /// dari katalog statis setiap kali build.
  String? _kategoriTerbuka;

  /// Gerakan yang sedang dipilih, atau null kalau belum ada pilihan.
  ///
  /// Ini yang menentukan video placeholder mana yang ditampilkan.
  GestureExercise? _gerakTerpilih;

  /// Membuka daftar gerakan sebuah kategori.
  void _bukaKategori(KategoriOtot kategori) {
    setState(() {
      _kategoriTerbuka = kategori.nama;
      // Reset pilihan gerakan supaya video tertutup saat pindah kategori.
      _gerakTerpilih = null;
    });
  }

  /// Kembali ke katalog kategori.
  void _kembaliKeKatalog() {
    setState(() {
      _kategoriTerbuka = null;
      _gerakTerpilih = null;
    });
  }

  /// Memilih gerakan dan membuka video placeholder-nya.
  void _pilihGerakan(GerakanLatihan gerak) {
    setState(() {
      // Toggle: menekan gerakan yang sama menutup video lagi.
      if (_gerakTerpilih?.nama == gerak.nama) {
        _gerakTerpilih = null;
      } else {
        _gerakTerpilih = gerak;
      }
    });
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    // Layar yang sedang aktif ditentukan oleh [_kategoriTerbuka].
    return _kategoriTerbuka == null
        ? _buildKatalog()
        : _buildDetailKategori();
  }

  /// Layar katalog: grid lima kategori.
  Widget _buildKatalog() {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _isEnglish(context) ? 'STRENGTH TRAINING' : 'LATIHAN KEKUATAN',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).colorScheme.onSurface,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLanguageService.text(context, 'Katalog latihan kekuatan untuk melengkapi program lari', 'A strength exercise library to complement your running plan.'),
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // Grid responsif. LayoutBuilder memberi lebar Constraints
            // area yang tersedia, lalu jumlah kolom dihitung dari lebar itu.
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  // Menentukan jumlah kolom dari lebar layar.
                  //   < 380  : 2 kolom (ponsel kecil)
                  //   < 600  : 3 kolom (ponsel besar)
                  //   < 900  : 4 kolom (tablet)
                  //   >= 900 : 5 kolom (tablet besar)
                  final int jumlahKolom = constraints.maxWidth >= 900
                      ? 5
                      : constraints.maxWidth >= 600
                          ? 4
                          : constraints.maxWidth >= 380
                              ? 3
                              : 2;

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    // Rasio lebar-tinggi kartu. Nilai 0,85 membuat kartu
                    // sedikit lebih tinggi dari lebar, yang cocok untuk
                    // susunan emoji di tengah dan teks di bawah.
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: jumlahKolom,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: katalogOtot.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _KartuKategori(
                        kategori: katalogOtot[index],
                        onTap: () => _bukaKategori(katalogOtot[index]),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Layar detail: daftar tiga gerakan untuk kategori yang dipilih.
  Widget _buildDetailKategori() {
    // Cari kategori yang dipilih dari katalog statis.
    final KategoriOtot kategori = katalogOtot.firstWhere(
      (KategoriOtot k) => k.nama == _kategoriTerbuka,
    // firstWhere melempar error kalau tidak ketemu.
      // orElse dipakai supaya tidak pernah crash walau nama kategori
      // berubah di katalog.
      orElse: () => katalogOtot.first,
    );

    return Scaffold(
      appBar: AppBar(
        // Tombol back dengan label custom yang lebih informatif.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _kembaliKeKatalog,
        ),
        title: Text('${kategori.ikon} ${_categoryName(kategori.nama, _isEnglish(context))}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Deskripsi kategori.
          Text(
            _categoryDescription(kategori, _isEnglish(context)),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Header "Pilih gerakan".
          Text(
            AppLanguageService.text(context, 'PILIH GERAKAN', 'CHOOSE AN EXERCISE'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Daftar tiga gerakan.
          ...kategori.gerakan.map(_buildKartuGerakan),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Kartu satu gerakan, dengan video placeholder yang bisa dibuka.
  Widget _buildKartuGerakan(GerakanLatihan gerak) {
    final bool terpilih = _gerakTerpilih?.nama == gerak.nama;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        // Border menyala biru neon ketika gerakan dipilih.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(
            color: terpilih ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
            width: terpilih ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: () => _pilihGerakan(gerak),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Baris atas: nama dan ikon panah.
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _exerciseName(gerak, _isEnglish(context)),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    // Ikon berputar 180 derajat saat terbuka.
                    AnimatedRotation(
                      turns: terpilih ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Icons.expand_more,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${_targetMuscles(gerak, _isEnglish(context))}  |  ${_levelText(gerak, _isEnglish(context))}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),

                // Chip repetisi dan set.
                Row(
                  children: <Widget>[
                    _ChipInfo(ikon: Icons.repeat, teks: _repText(gerak, _isEnglish(context))),
                    const SizedBox(width: 8),
                    _ChipInfo(ikon: Icons.layers, teks: _setText(gerak, _isEnglish(context))),
                  ],
                ),

                // --- VIDEO PLACEHOLDER ---
                // AnimatedSize membungkus seluruh blok video.
                // alignment: Alignment.topCenter menjaga video tetap di
                // atas saat kontainer menyusut, sehingga teks instruksi
                // di bawah tidak ikut bergeser halaman.
                //
                // memakai Column kosong agar tinggi yang terukur benar.
                // adalah Column kosong, supaya mengukur tinggi yang benar.
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  child: terpilih
                      ? _PlaceholderVideo(gerak: gerak)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// KARTU KATEGORI
/// ============================================================
/// Kartu di grid katalog: emoji besar, nama, dan jumlah gerakan.
class _KartuKategori extends StatelessWidget {
  final KategoriOtot kategori;
  final VoidCallback onTap;

  const _KartuKategori({required this.kategori, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      // Ketukan memakai InkWell dengan borderRadius yang sama supaya
      // efek riwayatnya mengikuti bentuk kartu.
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              // Emoji kategori, sized besar.
              Text(kategori.ikon, style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(
                _categoryName(kategori.nama, _isEnglish(context)),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${kategori.gerakan.length} ${AppLanguageService.text(context, 'gerakan', 'exercises')}',
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// CHIP INFO
/// ============================================================
/// Chip kecil berisi ikon dan teks, dipakai untuk repetisi dan set.
class _ChipInfo extends StatelessWidget {
  final IconData ikon;
  final String teks;

  const _ChipInfo({required this.ikon, required this.teks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.zero,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(ikon, size: 12, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 5),
          Text(
            teks,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// PLACEHOLDER VIDEO
/// ============================================================
/// Wadah video tutorial gerakan.
///
/// Ini masih placeholder, jadi tidak ada file video yang diputar.
///_structuranya sengaja dibuat seperti pemutar video sungguhan:
///   - area 16:9 dengan ikon play besar di tengah,
///   - durasi video di pojok kanan bawah, seperti tombol kontrol,
///   - tombol "Ganti-hereditar-video" di bawah untuk menandai bahwa
///     file video tinggal di-*integrate*.
///
/// Untuk integrasi video sungguhan, ganti isi [Icon] play dengan
/// `VideoPlayerController.network(...)` dan bungkus dengan
/// `AspectRatio(aspectRatio: 16 / 9)`.
class _PlaceholderVideo extends StatelessWidget {
  final GerakanLatihan gerak;

  const _PlaceholderVideo({required this.gerak});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Area video 16:9.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: <Widget>[
                // Latar dengan pola diagonal supaya terasa seperti
                // area video, bukan kotak kosong.
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.play_arrow,
                      size: 36,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                // Badge durasi di pojok kanan bawah, seperti pemutar video.
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gerak.durasiTeks,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                // Badge nama gerakan di pojok kiri atas.
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${_setText(gerak, _isEnglish(context))} x ${_repText(gerak, _isEnglish(context))}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Instruksi eksekusi di bawah video.
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 14, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 6),
                    Text(
                      AppLanguageService.text(context, 'Cara melakukan', 'How to perform'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _exerciseInstruction(gerak, _isEnglish(context)),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                // Nama Latin sebagai referensi pencarian.
                Text(
                  '${AppLanguageService.text(context, 'Referensi', 'Reference')}: ${gerak.namaInggris}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Alias typedef supaya nama model tidak berubah-ubah di file ini.
/// Dokumentasi typedef ini_city_of_massachusetts_makes Dartdoc lebih jelas
/// saat library ini dipakai dari luar.
typedef GestureExercise = GerakanLatihan;
