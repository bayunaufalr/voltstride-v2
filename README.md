# VoltStride v2

VoltStride adalah aplikasi Flutter untuk merekam lari dan jalan kaki, melihat rute GPS, pace, split, lap 100 meter, kemajuan latihan, serta menggunakan coach latihan lokal.

## Yang baru pada sistem akun

- Daftar akun dan masuk memakai email serta kata sandi melalui Firebase Authentication.
- Link email untuk mengatur ulang kata sandi.
- Nama akun dan email ditampilkan di halaman **Akun**.
- Riwayat aktivitas, rute GPS, split, lap 100 meter, dan metrik lari disimpan pada ruang milik akun di Cloud Firestore.
- Salinan lokal tetap digunakan agar riwayat bisa dibaca saat jaringan tidak tersedia.
- Data setiap akun dipisahkan berdasarkan UID. Pengguna tidak bisa membaca riwayat pengguna lain jika aturan keamanan Firebase dipasang sesuai panduan.
- Riwayat lama yang tersimpan sebelum fitur akun tersedia tidak otomatis dipindahkan. Pemilik perangkat dapat memilih untuk menggabungkannya ke akun secara manual.

## Layanan Firebase yang digunakan

1. **Firebase Authentication** untuk membuat akun, masuk, keluar, dan pemulihan kata sandi.
2. **Cloud Firestore** untuk menyimpan profil dan riwayat aktivitas di cloud.

Penggunaan yang sesuai dapat dimulai dari paket Firebase Spark. Cloud Firestore mempunyai batas pemakaian gratis, sehingga pantau pemakaian jika aplikasi sudah digunakan banyak orang. Firebase tidak meminta metode pembayaran untuk memulai menggunakan produk gratis, tetapi kuota dan ketentuan produk tetap berlaku.

## Menyiapkan Firebase satu kali

### 1. Buat proyek dan aplikasi Android

1. Buka <https://console.firebase.google.com/> lalu buat proyek Firebase.
2. Tambahkan aplikasi Android dengan ID aplikasi berikut, sesuai konfigurasi saat ini:

   `com.example.voltstride`

3. Nama tampilan aplikasi boleh berbeda. Yang harus cocok adalah ID aplikasi Android.

### 2. Aktifkan daftar dan login

1. Buka menu **Authentication** di Firebase Console.
2. Pilih **Sign-in method**.
3. Aktifkan **Email/Password** lalu simpan.

### 3. Buat database cloud

1. Buka **Firestore Database**.
2. Buat database. Pilih **Production mode**.
3. Buka tab **Rules**.
4. Salin isi file `firestore.rules` dari folder proyek, tempelkan ke tab Rules, lalu klik **Publish**.

Aturan itu membatasi dokumen profil serta catatan lari hanya untuk akun dengan UID yang sama. Jangan menggantinya dengan aturan publik seperti `allow read, write: if true`.

### 4. Hubungkan Firebase ke GitHub Actions

VoltStride ini disiapkan agar proses pemeriksaan dan pembuatan APK berjalan di GitHub Actions. Kamu tidak perlu menjalankan perintah Flutter dari terminal lokal.

Ikuti panduan lengkap dalam file `PANDUAN_FIREBASE_GRATIS.md`. Intinya:

1. Aktifkan **Email/Password** di Firebase Authentication.
2. Buat Cloud Firestore dan terapkan aturan dari `firestore.rules`.
3. Ambil empat nilai konfigurasi dari aplikasi Android Firebase yang memiliki ID `com.example.voltstride`.
4. Tambahkan nilai itu ke **Settings → Secrets and variables → Actions** pada repository GitHub, dengan nama `VOLTSTRIDE_FIREBASE_API_KEY`, `VOLTSTRIDE_FIREBASE_APP_ID`, `VOLTSTRIDE_FIREBASE_MESSAGING_SENDER_ID`, dan `VOLTSTRIDE_FIREBASE_PROJECT_ID`.

GitHub Actions membuat `lib/firebase_options.dart` saat proses build berlangsung. File hasil build itu tidak perlu dibuat menggunakan FlutterFire CLI di laptop.

### 5. Periksa dan buat APK melalui GitHub

Setelah perubahan kode dikirim ke branch `main` atau `master`, buka tab **Actions**. Workflow **Build VoltStride APK** akan menjalankan `flutter pub get`, `flutter analyze`, `flutter test`, dan pembuatan APK secara otomatis. Kamu juga dapat menjalankannya dari tombol **Run workflow**.

Jika seluruh tahap berhasil, unduh `voltstride-apk-release` pada bagian **Artifacts** dalam hasil workflow. Kalau secret Firebase belum lengkap atau pengujian gagal, periksa pesan error di tahap terkait sebelum mencoba build kembali.

APK tetap bisa dibuat untuk pengujian tanpa keystore rilis. Dalam keadaan itu, workflow memakai debug key Android. Untuk publikasi ke Google Play, tambahkan secret signing key sesuai petunjuk pada `PANDUAN_FIREBASE_GRATIS.md`.

## Di mana data disimpan?

- **Firebase Authentication:** email akun dan informasi login yang dikelola Firebase. Kata sandi tidak disimpan dalam dokumen profil buatan aplikasi.
- **Cloud Firestore:** `users/{uid}` menyimpan profil dan `users/{uid}/runSessions/{id}` menyimpan catatan aktivitas.
- **Penyimpanan lokal SQLite:** salinan riwayat pada perangkat untuk pemakaian offline dan cadangan.

Rute GPS dapat mengungkap lokasi yang sensitif. Data cloud dipisahkan dengan aturan keamanan, tetapi kamu tetap perlu menjaga akses ke akun dan tidak membagikan data lokasi secara publik.

## Riwayat lama dari versi sebelumnya

Data pada perangkat yang sudah ada sebelum fitur akun ditambahkan diberi label `guest`. Data itu tidak otomatis masuk ke akun pertama yang login. Pada tab **Akun**, gunakan pilihan **Pindahkan ke akun ini** hanya bila semua aktivitas lama tersebut memang milikmu. Tindakan ini menyalin riwayat beserta data rute GPS ke akun yang sedang aktif.

## Catatan

- Firebase harus dikonfigurasi dengan proyek milik pengguna sebelum daftar/login dan sinkronisasi cloud bekerja.
- Riwayat lokal tetap dipakai sebagai salinan. Jika jaringan terputus atau aturan cloud belum benar, aplikasi memberi tahu ketika pengiriman aktivitas baru tidak berhasil.
- Timer, daftar latihan kekuatan, dan sebagian pengaturan antarmuka belum dibuat sebagai data cloud terpisah; fitur cloud pada versi ini berfokus pada profil akun dan riwayat aktivitas.
- Jangan pernah memublikasikan kata sandi, private key, `android/key.properties`, atau file keystore.

## Istilah sederhana

- **Firebase Authentication:** layanan yang mengurus pendaftaran dan login pengguna.
- **Cloud Firestore:** database online untuk menyimpan data akun.
- **UID:** kode unik yang diberikan Firebase pada setiap akun. Aplikasi menggunakan kode ini untuk memisahkan riwayat pengguna.
- **Sinkronisasi:** proses menyalin perubahan dari perangkat ke akun online atau sebaliknya.
