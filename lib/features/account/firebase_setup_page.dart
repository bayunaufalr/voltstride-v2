import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';

/// Petunjuk singkat jika aplikasi belum bisa terhubung ke Firebase.
class FirebaseSetupPage extends StatelessWidget {
  const FirebaseSetupPage({super.key, this.detailError});

  final String? detailError;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLanguageService.text(context, 'Firebase belum terhubung', 'Firebase is not connected'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            AppLanguageService.text(context, 'Periksa pengaturan berikut di Firebase dan GitHub.', 'Check the following settings in Firebase and GitHub.'),
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
          const SizedBox(height: 18),
          _langkah(
            context,
            '1',
            AppLanguageService.text(context, 'ID aplikasi Android', 'Android application ID'),
            AppLanguageService.text(context, 'Pastikan ID aplikasi adalah com.example.voltstride.', 'Make sure the application ID is com.example.voltstride.'),
          ),
          _langkah(
            context,
            '2',
            AppLanguageService.text(context, 'Login email', 'Email sign-in'),
            AppLanguageService.text(context, 'Di Firebase Console, buka Authentication → Sign-in method, lalu pastikan Email/Password aktif.', 'In Firebase Console, open Authentication → Sign-in method and enable Email/Password.'),
          ),
          _langkah(
            context,
            '3',
            'Database',
            AppLanguageService.text(context, 'Pastikan Cloud Firestore sudah dibuat dan aturan dari firestore.rules sudah diterbitkan.', 'Make sure Cloud Firestore is created and the rules in firestore.rules have been published.'),
          ),
          _langkah(
            context,
            '4',
            'GitHub Secrets',
            AppLanguageService.text(context, 'Periksa empat VOLTSTRIDE_FIREBASE_* secrets, lalu jalankan ulang workflow Build VoltStride APK di tab Actions.', 'Check the four VOLTSTRIDE_FIREBASE_* secrets, then rerun Build VoltStride APK in the Actions tab.'),
          ),
          const SizedBox(height: 14),
          Text(
            AppLanguageService.text(context, 'Setelah memperbaiki pengaturan, push perubahan dan unduh APK hasil build yang terbaru.', 'After fixing the settings, push your changes and download the latest APK build.'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.45),
          ),
          if (detailError != null && detailError!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(AppLanguageService.text(context, 'Detail error', 'Error details')),
              children: <Widget>[
                SelectableText(
                  detailError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

  Widget _langkah(BuildContext context, String nomor, String judul, String keterangan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
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
