# VoltStride v2

VoltStride adalah aplikasi sport-tech berbasis Flutter untuk merekam lari, melihat perkembangan latihan, mengatur interval, dan mempelajari hasil setiap sesi. Proyek ini memakai Dart untuk logika aplikasi dan Flutter untuk antarmukanya.

## Fitur yang terhubung ke navigasi utama

- **Beranda:** ringkasan jarak dan waktu bergerak minggu ini, elevasi, serta aktivitas terbaru.
- **Rekam:** pengaturan aktivitas luar/dalam ruangan, lari atau jalan, pilihan interval, dan perekaman sesi.
- **Riwayat:** daftar sesi yang tersimpan di SQLite, halaman detail, serta ekspor/impor cadangan JSON.
- **Kemajuan:** ringkasan latihan, grafik mingguan, dan personal record.
- **Akun/Lainnya:** akses ke timer interval, coach lokal, katalog latihan kekuatan, dan ringkasan pemulihan.

Folder `lib/features/` berisi alur aplikasi yang aktif. Ada juga kode versi lama di `lib/logic/`, `lib/models/` tertentu, `lib/services/online_coach_service.dart`, `lib/services/strava_api_client.dart`, dan `lib/screens/tracker_page.dart`. Kode lama masih berguna sebagai referensi, tetapi tidak semuanya dipanggil oleh navigasi utama. Baca `PENJELASAN_KODE.md` sebelum memindahkan atau menghapus bagian-bagian tersebut.

## Menjalankan aplikasi

Pastikan Flutter dan Android SDK sudah terpasang, lalu jalankan perintah berikut dari folder proyek:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Versi SDK yang dinyatakan proyek ada di `pubspec.yaml`: Dart `>=3.10.0 <4.0.0` dan Flutter `>=3.38.0`. Versi Flutter pada komputer pengembang tetap harus cocok dengan dependensi yang dipakai.

## Bagaimana perekaman GPS bekerja?

Alur rekam aktif menggunakan `RunningPage` → `RunningController` → `RunningEngine`.

1. Aplikasi memeriksa apakah layanan lokasi menyala dan izin lokasi diberikan.
2. Mesin menunggu satu posisi awal dengan akurasi yang memenuhi batas.
3. Setelah hitung mundur selesai, stopwatch dimulai dan stream lokasi diikuti.
4. Posisi dengan koordinat atau akurasi tidak valid ditolak. Perpindahan yang mengindikasikan kecepatan di atas 35 km/jam juga ditolak dan titik acuan diperbarui agar satu lonjakan GPS tidak membuat seluruh sesi macet.
5. Jarak dihitung dari perpindahan koordinat mentah yang lolos pemeriksaan menggunakan rumus Haversine. Ambang gerak adaptif membantu menahan noise kecil. Koordinat rute dihaluskan khusus untuk tampilan peta, bukan untuk menambah jarak.
6. `Stopwatch` menjadi sumber waktu sesi. Saat dijeda, penghitung berhenti; setelah dilanjutkan, titik GPS pertama hanya menjadi titik acuan baru.
7. Mesin menghitung pace, split per kilometer, dan segmen 100 meter. Ketika sesi selesai, datanya dibungkus menjadi `RunSession` dan disimpan oleh `RunHistoryRepository`.

Penyaringan GPS mengurangi kesalahan, tetapi tidak dapat menjamin jarak benar-benar presisi. Hasil tetap dipengaruhi perangkat, kondisi langit, gedung, pepohonan, dan kualitas sinyal.

## Coach: lokal dan online adalah dua hal berbeda

Halaman coach yang terhubung ke menu utama memakai `AiCoachService` di `lib/features/ai_coach/ai_coach_service.dart`. Respons dibuat secara lokal dengan aturan dan pencocokan kata kunci, serta dapat membaca sesi yang tersimpan. Ini **bukan model bahasa generatif** dan tidak mengirim percakapan ke server AI.

`lib/services/online_coach_service.dart` adalah kerangka untuk menghubungi endpoint HTTP pada alur versi lama. Nilai endpoint dan API key di file tersebut bukan konfigurasi siap produksi. Jika fitur online akan diaktifkan, sediakan backend sendiri dan simpan rahasia di server. Jangan menaruh API key rahasia di aplikasi mobile karena isi APK dapat diperiksa.

## Integrasi Strava

`lib/services/strava_api_client.dart` adalah kerangka kode lama untuk membuat URL otorisasi dan mengirim aktivitas. File tersebut belum otomatis berarti login Strava sudah terhubung ke alur aplikasi aktif. Implementasi produksi masih memerlukan konfigurasi aplikasi Strava, penanganan redirect/deep link, pertukaran authorization code dengan token melalui backend, penyimpanan token yang aman, serta pengujian izin dan payload API.

## Penyimpanan dan cadangan

Riwayat disimpan di database SQLite lokal oleh `RunHistoryRepository`. Model `RunSession` mengubah data menjadi kolom database; beberapa kumpulan titik disimpan sebagai JSON di kolom terkait. Cadangan dapat diekspor dan diimpor melalui halaman Riwayat. File cadangan dapat berisi koordinat rute GPS, jadi jangan membagikannya secara publik.

## Pengujian

Folder `test/` berisi pengujian untuk respons coach lokal, state machine mesin lari, penyaringan lonjakan GPS, penghitungan split 100 meter, personal record, elevasi, dan serialisasi sesi. Jalankan `flutter test` pada komputer yang sudah memiliki Flutter SDK untuk memverifikasi seluruh tes terhadap lingkunganmu.

Untuk penjelasan fungsi, alur data, algoritma, dan daftar file satu per satu, baca **[PENJELASAN_KODE.md](PENJELASAN_KODE.md)**.
