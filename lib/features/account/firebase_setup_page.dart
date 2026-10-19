import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';

/// Ditampilkan sampai konfigurasi proyek Firebase dibuat.
class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key, this.detailError});

  final String? detailError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: VoltWarna.aksen.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.cloud_off_rounded,
                      color: VoltWarna.aksen,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Hubungkan VoltStride ke Firebase',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Fitur akun belum aktif karena proyek Firebase milikmu belum '
                    'dimasukkan ke aplikasi. Ikuti langkah berikut satu kali.',
                    style: TextStyle(
                      color: VoltWarna.teksAbu,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const _LangkahKonfigurasi(
                    nomor: '1',
                    judul: 'Buat proyek Firebase',
                    keterangan:
                        'Buka console.firebase.google.com, buat proyek baru, '
                        'lalu tambahkan aplikasi Android dengan ID '
                        'com.example.voltstride.',
                  ),
                  const _LangkahKonfigurasi(
                    nomor: '2',
                    judul: 'Aktifkan login email',
                    keterangan:
                        'Di Authentication, buka Sign-in method dan aktifkan '
                        'Email/Password.',
                  ),
                  const _LangkahKonfigurasi(
                    nomor: '3',
                    judul: 'Buat database cloud',
                    keterangan:
                        'Buat Cloud Firestore dalam mode produksi. Setelah itu, '
                        'terapkan file firestore.rules dari folder proyek.',
                  ),
                  const _LangkahKonfigurasi(
                    nomor: '4',
                    judul: 'Jalankan perintah di terminal proyek',
                    keterangan:
                        'Pasang Firebase CLI dan FlutterFire CLI, lalu jalankan '
                        'perintah di bawah ini dari folder voltstride-v2.',
                  ),
                  const SizedBox(height: 10),
                  _KotakPerintah(
                    perintah: 'npm install -g firebase-tools\n'
                        'firebase login\n'
                        'dart pub global activate flutterfire_cli\n'
                        'flutterfire configure',
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Setelah konfigurasi selesai, jalankan flutter pub get lalu '
                    'build ulang APK. Berkas firebase_options.dart akan dibuat '
                    'otomatis oleh perintah konfigurasi.',
                    style: TextStyle(color: VoltWarna.teksAbu, height: 1.5),
                  ),
                  if (detailError != null && detailError!.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(height: 18),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Detail teknis'),
                      children: <Widget>[
                        SelectableText(
                          detailError!,
                          style: const TextStyle(
                            color: VoltWarna.teksAbu,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LangkahKonfigurasi extends StatelessWidget {
  const _LangkahKonfigurasi({
    required this.nomor,
    required this.judul,
    required this.keterangan,
  });

  final String nomor;
  final String judul;
  final String keterangan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: VoltWarna.surface,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              nomor,
              style: const TextStyle(
                color: VoltWarna.aksen,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(judul, style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  keterangan,
                  style: const TextStyle(
                    color: VoltWarna.teksAbu,
                    height: 1.45,
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

class _KotakPerintah extends StatelessWidget {
  const _KotakPerintah({required this.perintah});

  final String perintah;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VoltWarna.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: VoltWarna.border),
      ),
      child: SelectableText(
        perintah,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.7,
        ),
      ),
    );
  }
}
