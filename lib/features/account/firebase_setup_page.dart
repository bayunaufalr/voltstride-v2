import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';

/// Petunjuk singkat jika aplikasi belum bisa terhubung ke Firebase.
class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key, this.detailError});

  final String? detailError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase belum terhubung')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Text(
            'Periksa pengaturan berikut di Firebase dan GitHub.',
            style: TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 18),
          _langkah(
            context,
            '1',
            'ID aplikasi Android',
            'Pastikan ID aplikasi adalah com.example.voltstride.',
          ),
          _langkah(
            context,
            '2',
            'Login email',
            'Di Firebase Console, buka Authentication → Sign-in method, lalu pastikan Email/Password aktif.',
          ),
          _langkah(
            context,
            '3',
            'Database',
            'Pastikan Cloud Firestore sudah dibuat dan aturan dari firestore.rules sudah diterbitkan.',
          ),
          _langkah(
            context,
            '4',
            'GitHub Secrets',
            'Periksa empat VOLTSTRIDE_FIREBASE_* secrets, lalu jalankan ulang workflow Build VoltStride APK di tab Actions.',
          ),
          const SizedBox(height: 14),
          Text(
            'Setelah memperbaiki pengaturan, push perubahan dan unduh APK hasil build yang terbaru.',
            style: TextStyle(color: VoltWarna.teksAbu, height: 1.45),
          ),
          if (detailError != null && detailError!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Detail error'),
              children: <Widget>[
                SelectableText(
                  detailError!,
                  style: TextStyle(
                    color: VoltWarna.teksAbu,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _langkah(
    BuildContext context,
    String nomor,
    String judul,
    String keterangan,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: VoltWarna.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            nomor,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(judul, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(keterangan, style: const TextStyle(height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
