import 'package:flutter/material.dart';

import '../models/latihan.dart';
import '../theme/volt_theme.dart';

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
///   besar. AnimatedSize menganimasikan perubahan tinggi itu, sehingga
///   daftar tidak terasa "melompat". Kalau dipakai
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'OTOT & STRENGTH',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: VoltWarna.teksPutih,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Katalog latihan kekuatan untuk melengkapi program lari',
                    style: TextStyle(fontSize: 12, color: VoltWarna.teksAbu),
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
        title: Text('${kategori.ikon} ${kategori.nama}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // Deskripsi kategori.
          Text(
            kategori.deskripsi,
            style: const TextStyle(
              color: VoltWarna.teksAbu,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          // Header "Pilih gerakan".
          const Text(
            'PILIH GERAKAN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: VoltWarna.teksRedup,
              letterSpacing: 2,
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
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: terpilih ? VoltWarna.aksen : VoltWarna.border,
            width: terpilih ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
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
                        gerak.nama,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: VoltWarna.teksPutih,
                        ),
                      ),
                    ),
                    // Ikon berputar 180 derajat saat terbuka.
                    AnimatedRotation(
                      turns: terpilih ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.expand_more,
                        color: VoltWarna.aksen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${gerak.targetOtot}  |  ${gerak.levelTeks}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: VoltWarna.teksRedup,
                  ),
                ),
                const SizedBox(height: 12),

                // Chip repetisi dan set.
                Row(
                  children: <Widget>[
                    _ChipInfo(ikon: Icons.repeat, teks: gerak.repetisi),
                    const SizedBox(width: 8),
                    _ChipInfo(ikon: Icons.layers, teks: gerak.set),
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
        borderRadius: BorderRadius.circular(18),
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
                kategori.nama,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: VoltWarna.teksPutih,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${kategori.gerakan.length} gerakan',
                style: const TextStyle(
                  fontSize: 10,
                  color: VoltWarna.teksAbu,
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
        color: VoltWarna.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(ikon, size: 12, color: VoltWarna.aksen),
          const SizedBox(width: 5),
          Text(
            teks,
            style: const TextStyle(
              fontSize: 11,
              color: VoltWarna.teksAbu,
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
        color: VoltWarna.latar,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoltWarna.border),
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
                      color: VoltWarna.aksen.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      size: 36,
                      color: VoltWarna.aksen,
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
                      color: VoltWarna.latar.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      gerak.durasiTeks,
                      style: const TextStyle(
                        fontSize: 11,
                        color: VoltWarna.teksPutih,
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
                      color: VoltWarna.aksen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${gerak.set} x ${gerak.repetisi}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: VoltWarna.latar,
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
                const Row(
                  children: <Widget>[
                    Icon(Icons.info_outline,
                        size: 14, color: VoltWarna.aksen),
                    SizedBox(width: 6),
                    Text(
                      'Cara Eksekusi',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: VoltWarna.aksen,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  gerak.petunjuk,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VoltWarna.teksAbu,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 10),
                // Nama Latin sebagai referensi pencarian.
                Text(
                  'Referensi: ${gerak.namaInggris}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: VoltWarna.teksRedup,
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

/// Alias nama agar widget di halaman ini dapat memakai istilah yang lebih
/// mudah dibaca tanpa mengubah kelas data `GerakanLatihan`.
typedef GestureExercise = GerakanLatihan;
