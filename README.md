# VoltStride

Aplikasi sport-tech mobile berbasis Flutter: **AI Running Coach**, **live GPS tracking**,
**interval round timer**, dan **katalog latihan kekuatan**.

## Struktur folder

```
lib/
├── main.dart                       root aplikasi + navigasi IndexedStack
├── theme/volt_theme.dart           palet warna dan ThemeData
├── models/
│   ├── profil_pelari.dart          hasil kalkulasi AI + zona latihan
│   ├── rencana_latihan.dart        program multi-minggu
│   ├── split_kilometer.dart        satu kilometer + konversi Strava
│   └── latihan.dart                katalog kategori dan gerakan
├── logic/
│   ├── ai_coach_engine.dart        target pace adaptif, HR, skor kebugaran
│   ├── penyusun_rencana.dart       periodisasi build, peak, taper
│   ├── split_strategi.dart         kurva pace per kilometer (negative split)
│   ├── race_simulator.dart         simulasi balapan Timer.periodic + Stopwatch
│   ├── pelacak_lari.dart           mesin GPS: Haversine, pace, split
│   └── kalman_gps.dart             filter Kalman, deteksi anomali, geometri
└── services/
    ├── lokasi_service.dart         konfigurasi geolocator akurasi tinggi
    ├── online_coach_service.dart   POST JSON ke endpoint AI
    └── strava_api_client.dart      OAuth url_launcher + upload activity
```

## Cara menjalankan

```bash
flutter pub get
flutter analyze
flutter run
```

Butuh Flutter **3.29+** (kode memakai `CardThemeData` dan `NavigationBarThemeData`).

## Permission lokasi (wajib)

`geolocator` tidak bisa jalan tanpa permission. Tanpa ini aplikasi crash saat
tombol "Mulai Lari GPS" ditekan.

**Android** — `android/app/src/main/AndroidManifest.xml`, tambahkan di dalam
`<manifest>`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Tambahkan juga agar GPS tetap jalan saat layar mati (opsional):

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
```

**iOS** — `ios/Runner/Info.plist`, tambahkan sebelum tag `</dict>`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>VoltStride memakai lokasi untuk mengukur jarak dan pace lari Anda.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>VoltStride memakai lokasi di latar belakang untuk merekam sesi lari panjang.</string>
```

## Online Coach

Buka `lib/services/online_coach_service.dart` dan ganti:

```dart
static const String endpoint = 'https://api.voltstride.id/v1';
static const String apiKey = 'GANTI_DENGAN_API_KEY_MILIKMU';
```

Kontrak endpoint yang diharapkan aplikasi:

| Metode | Endpoint | Body | Response |
| --- | --- | --- | --- |
| POST | `{endpoint}/chat` | `{profil, pesan, riwayat}` | `{"jawaban": "..."}` |
| POST | `{endpoint}/rencana` | `{profil, rencana_lokal}` | objek rencana `{tujuan, jumlah_minggu, minggu[]}` |

Kalau server tidak terjangkau, aplikasi **tidak** mati: chat dijawab oleh
`_jawabanLokal()` dan rencana tetap memakai hasil hitungan lokal. Ini pola
graceful degradation, dan seluruh perhitungan kritis sengaja diletakkan di
sisi klien.

**Keamanan:** API key tidak boleh ada di kode aplikasi mobile karena kode bisa
dibongkar. Untuk produksi, arahkan `endpoint` ke backend milikmu sendiri dan
simpan kunci di secret manager.

## Strava

`lib/services/strava_api_client.dart` sudah berisi:

- URL otorisasi OAuth lengkap (`buatUrlOtorisasi`).
- Pembuka browser sistem (`bukaOtorisasi`) memakai `url_launcher` dengan
  `LaunchMode.externalApplication`, sesuai syarat Strava dan Play Store.
- Parsing kode otorisasi dari deep link (`ekstrakKodeOtorisasi`).
- Payload activity + `splits_metric` per kilometer (`buatPayload`).
- POST ke `/api/v3/activities` (`unggahActivity`).

Yang perlu kamu lengkapi sendiri: daftarkan redirect URI `voltstride://auth/callback`
di Strava API settings, isi `clientId`, dan tukar kode jadi access token lewat
backend (lihat catatan keamanan di file tersebut).

## Catatan akurasi GPS

Pengukuran jarak tidak memakai penjumlahan mentah koordinat GPS, karena noise
GPS membuat jarak terhitung jauh lebih besar dari jarak sebenarnya. Rantai
pemrosesannya:

1. Buang titik dengan `accuracy` lebih buruk dari 50 meter.
2. Hitung jarak kasar antar titik dengan rumus Haversine.
3. Tolak titik yang gerakannya tidak manusiawi (> 35 km/jam atau < 1,5 meter).
4. Koreksi posisi dengan **filter Kalman 1D**, di mana radius akurasi GPS
   dipakai sebagai measurement noise sehingga titik yang kurang yakin otomatis
   diberi bobot kecil.
5. Akumulasi **selisih posisi terfilter**, bukan jarak kasar.

Angka kualitasnya bisa dilihat langsung di panel **AKURASI GPS** pada halaman
Lari, yang menampilkan jumlah titik diterima, ditolak, dan rasio data bersih.

Waktu bukan dihitung dari selisih antar titik GPS, melainkan dari `Stopwatch`,
karena delta waktu GPS hilang saat sinyal terputus sementara dan membuat total
waktu terlalu kecil. `Timer.periodic` hanya membangunkan UI.