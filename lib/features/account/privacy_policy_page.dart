// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';

/// Kebijakan privasi VoltStride yang dapat dibaca dari layar masuk dan profil.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  String _text(BuildContext context, String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<(String, String)> sections = <(String, String)>[
      (
        _text(context, '1. Data yang diproses', '1. Information we process'),
        _text(
          context,
          'VoltStride memproses informasi akun seperti nama dan email. Jika diisi, profil juga dapat memuat tanggal lahir, jenis kelamin, bio, dan foto profil. Saat Anda merekam aktivitas, aplikasi dapat menyimpan waktu, durasi, jarak, pace, lintasan GPS, elevasi, split, serta data denyut jantung atau cadence jika tersedia dari perangkat atau sensor yang digunakan. Preferensi tema, bahasa, pengingat, dan rute yang direncanakan juga dapat disimpan.',
          'VoltStride processes account details such as your name and email. If provided, your profile can also contain date of birth, gender, bio, and profile photo. Recorded activities may include time, duration, distance, pace, GPS route, elevation, splits, and heart-rate or cadence data when available from the device or sensor in use. Theme, language, reminder preferences, and planned routes may also be stored.',
        ),
      ),
      (
        _text(context, '2. Cara data digunakan', '2. How data is used'),
        _text(
          context,
          'Data digunakan untuk menampilkan riwayat dan statistik latihan, menghitung metrik seperti pace dan estimasi kebugaran, merencanakan rute atau latihan, memberikan pengingat, serta menyinkronkan data ke akun Anda. Izin lokasi digunakan saat fitur yang memerlukannya, seperti perencanaan rute dan rekaman GPS, sedang digunakan.',
          'Data is used to display activity history and statistics, calculate metrics such as pace and fitness estimates, plan routes or workouts, send reminders, and sync information to your account. Location permission is used when features that require it, such as route planning and GPS recording, are in use.',
        ),
      ),
      (
        _text(context, '3. Penyimpanan dan sinkronisasi', '3. Storage and syncing'),
        _text(
          context,
          'Riwayat aktivitas disimpan secara lokal pada perangkat. Ketika Anda masuk ke akun, data aktivitas dan profil yang dipilih untuk sinkronisasi dapat dikirim ke Firebase Authentication dan Cloud Firestore pada akun pengguna Anda. Keluar dari akun tidak menghapus salinan data cloud. Data lokal dapat ikut terhapus jika data aplikasi dihapus atau aplikasi dicopot, sesuai perilaku sistem perangkat.',
          'Activity history is stored locally on your device. When you sign in, activity and profile data selected for synchronization may be sent to Firebase Authentication and Cloud Firestore under your user account. Signing out does not delete cloud copies. Local data may be removed when app data is cleared or the app is uninstalled, depending on device behavior.',
        ),
      ),
      (
        _text(context, '4. Izin perangkat', '4. Device permissions'),
        _text(
          context,
          'Lokasi diperlukan untuk rekaman dan perencanaan rute; notifikasi digunakan untuk pengingat dan pembaruan pacer; pengenalan aktivitas atau Bluetooth dapat diminta untuk fitur perangkat terkait. Anda dapat mengubah atau mencabut izin melalui Pengaturan Android. Menonaktifkan izin dapat membuat fitur yang bergantung padanya tidak tersedia.',
          'Location is needed for GPS recording and route planning; notifications are used for reminders and pacer updates; activity recognition or Bluetooth may be requested for related device features. You can change or revoke permissions in Android Settings. Disabling a permission may make dependent features unavailable.',
        ),
      ),
      (
        _text(context, '5. Layanan pihak ketiga', '5. Third-party services'),
        _text(
          context,
          'Firebase digunakan untuk autentikasi akun dan sinkronisasi cloud. Peta menggunakan data peta OpenStreetMap atau penyedia tile yang dikonfigurasi aplikasi; permintaan peta dapat mengungkapkan informasi teknis seperti alamat IP kepada penyedia tersebut. Layanan pihak ketiga mengikuti kebijakan privasi masing-masing.',
          'Firebase is used for account authentication and cloud synchronization. Maps use OpenStreetMap data or the configured map-tile provider; map requests may reveal technical information such as your IP address to that provider. Third-party services are governed by their own privacy policies.',
        ),
      ),
      (
        _text(context, '6. Ekspor dan berbagi', '6. Exporting and sharing'),
        _text(
          context,
          'Ketika Anda meminta ekspor, VoltStride dapat menyimpan file aktivitas TCX atau gambar aktivitas di folder Downloads perangkat. Aplikasi tidak mengirim file tersebut ke pihak lain secara otomatis. Jika Anda sendiri mengunggah atau membagikannya ke layanan lain, pemrosesan selanjutnya mengikuti kebijakan layanan tujuan.',
          'When you request an export, VoltStride may save a TCX activity file or activity image to your device’s Downloads folder. The app does not automatically send those files to another service. If you upload or share them yourself, further processing is governed by the destination service’s policy.',
        ),
      ),
      (
        _text(context, '7. Pengamanan dan pilihan Anda', '7. Security and your choices'),
        _text(
          context,
          'Jangan bagikan kata sandi atau informasi login. Gunakan kontrol akun, pengaturan izin Android, dan fitur penghapusan aktivitas yang tersedia untuk mengelola data. Penghapusan aplikasi atau keluar dari akun tidak otomatis menghapus data yang sudah tersimpan di Firestore. Untuk meminta penghapusan data cloud atau menanyakan privasi, hubungi pengembang melalui kanal distribusi VoltStride yang Anda gunakan; jangan pernah mengirimkan kata sandi.',
          'Do not share your password or login credentials. Use account controls, Android permission settings, and available activity-deletion features to manage your data. Uninstalling the app or signing out does not automatically delete data already stored in Firestore. To request cloud-data deletion or ask a privacy question, contact the developer through the VoltStride distribution channel you used; never send your password.',
        ),
      ),
      (
        _text(context, '8. Perubahan kebijakan', '8. Policy updates'),
        _text(
          context,
          'Kebijakan ini dapat diperbarui saat fitur atau cara pemrosesan data berubah. Versi terbaru akan ditampilkan pada halaman ini.',
          'This policy may be updated when app features or data-processing practices change. The latest version will be displayed on this page.',
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_text(context, 'Kebijakan Privasi', 'Privacy Policy')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Text(
            'VoltStride',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colors.onSurface,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _text(
              context,
              'Terakhir diperbarui: 25 Oktober 2026',
              'Last updated: 25 October 2026',
            ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Text(
            _text(
              context,
              'Kebijakan ini menjelaskan data yang diproses ketika Anda menggunakan VoltStride.',
              'This policy explains the data processed when you use VoltStride.',
            ),
            style: TextStyle(color: colors.onSurface, height: 1.5),
          ),
          const SizedBox(height: 14),
          for (final (String title, String body) in sections) ...<Widget>[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    body,
                    style: TextStyle(
                      color: colors.onSurface,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
