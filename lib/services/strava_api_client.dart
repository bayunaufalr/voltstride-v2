import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/split_kilometer.dart';

/// Kerangka client untuk berkomunikasi dengan Strava API.
///
/// File ini menyiapkan URL otorisasi, payload aktivitas, dan request upload.
/// Namun, konfigurasi OAuth serta pertukaran kode menjadi access token tetap
/// harus diselesaikan sebelum integrasi dapat digunakan. Client ini juga
/// berasal dari alur pelacak lama dan belum dipanggil dari navigasi utama.
///
/// Jangan menyimpan client secret atau token rahasia di source code aplikasi.
/// Gunakan backend untuk pertukaran token dan simpan kredensial dengan aman.
class StravaApiClient {
  StravaApiClient._(); // kelas utilitas, tidak perlu instance

  /// Client ID aplikasi Strava (dari strava.com/settings/api).
  /// Ganti dengan milikmu. Angka di bawah bukan ID asli.
  static const int clientId = 123456;

  /// Client secret aplikasi Strava.
  ///
  /// CATATAN: secret TIDAK BOLEH ada di aplikasi mobile. Kode aplikasi
  /// bisa dibongkar siapa saja. Yang benar adalah melakukan pertukaran
  /// kode di backend sendiri. Nilai di bawah sengaja tidak diisi.
  static const String clientSecret = '';

  /// Access token sementara.
  ///
  /// Di aplikasi nyata, nilai ini diisi setelah pengguna selesai login
  /// di browser dan Strava mengembalikan kode lewat deep link.
  static String tokenAkses = '';

  /// Alamat endpoint Strava API v3.
  static const String baseUrl = 'https://www.strava.com/api/v3';

  /// Klien HTTP yang dipakai ulang antar-request.
  static final http.Client _klien = http.Client();

  // ------------------------------------------------------------
  // OAUTH
  // ------------------------------------------------------------
  /// Membangun URL otorisasi Strava.
  ///
  /// Parameter `scope` menentukan izin yang diminta:
  ///   - 'read'      : membaca activity (default)
  ///   - 'read_all'  : membaca seluruh aktivitas termasuk privat
  ///   - 'profile:read_all' : membaca profil termasuk berat dan zona
  ///   - 'activity:write'   : mengunggah activity baru (wajib untuk upload)
  ///
  /// Parameter `redirect_uri` harus dicatat persis sama di pengaturan
  /// aplikasi Strava, termasuk garis miring di akhir.
  static String buatUrlOtorisasi({
    String redirectUri = 'voltstride://auth/callback',
    String scope = 'read,activity:write',
  }) {
    // Uri.https mengodekan karakter khusus pada parameter URL dengan benar.
    // Ini lebih aman daripada merangkai URL secara manual.
    return Uri.https('www.strava.com', '/oauth/authorize', <String, String>{
      'client_id': clientId.toString(),
      'redirect_uri': redirectUri,
      // response_type=code berarti Strava mengembalikan kode otorisasi,
      // bukan token langsung. Ini alur yang wajib untuk aplikasi native
      // karena token tidak pernah terekspos lewat URL.
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': scope,
    }).toString();
  }

  /// Membuka halaman login Strava di browser sistem.
  ///
  /// `url_launcher` membuka halaman login di browser bawaan pengguna.
  /// Dengan cara ini, aplikasi tidak perlu meminta atau menyimpan kata sandi
  /// Strava secara langsung.
  ///
  /// Mengembalikan true bila browser berhasil dibuka.
  static Future<bool> bukaOtorisasi() async {
    final Uri url = Uri.parse(buatUrlOtorisasi());

    // launchUrl dengan mode externalApplication berarti buka di aplikasi
    // browser, bukan di webview internal. Ini yang diminta Strava dan
    // Play Store.
    final bool berhasil = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );

    return berhasil;
  }

  /// Mengekstrak kode otorisasi dari deep link yang kembali ke aplikasi.
  ///
  /// Parameter [url] adalah callback dari sistem, misalnya
  /// `voltstride://auth/callback?code=abc123&scope=read,activity:write`.
  ///
  /// Mengembalikan kode otorisasi, atau null kalau parameter `error`
  /// ada (pengguna menolak) atau format URL tidak dikenali.
  static String? ekstrakKodeOtorisasi(String url) {
    final Uri uri = Uri.parse(url);

    // Strava mengirim parameter error jika pengguna menolak akses atau
    // izin yang diminta tidak mencukupi.
    if (uri.queryParameters['error'] != null) {
      return null;
    }

    // Parameter 'code' adalah kode yang ditukar menjadi token.
    return uri.queryParameters['code'];
  }

  // ------------------------------------------------------------
  // PAYLOAD
  // ------------------------------------------------------------
  /// Membangun payload activity Strava dari hasil simulasi balapan.
  ///
  /// Parameter:
  ///   - [namaAktivitas]: nama aktivitas yang tampil di Strava feed.
  ///   - [deskripsi]: catatan opsional.
  ///   - [jarakKm]: jarak total dalam kilometer.
  ///   - [durasiDetik]: durasi total dalam detik.
  ///   - [splits]: daftar split per kilometer.
  ///   - [rataRataKecepatanMs]: kecepatan rata-rata dalam m/s.
  ///
  /// Mengembalikan Map yang siap di-encode jadi JSON.
  ///
  /// Catatan satuan yang wajib benar:
  ///   - `distance` dalam METER, bukan kilometer.
  ///   - `elapsed_time` dan `moving_time` dalam DETIK.
  ///   - `average_speed` dalam METER PER DETIK, bukan km/jam.
  static Map<String, dynamic> buatPayload({
    required String namaAktivitas,
    required String deskripsi,
    required double jarakKm,
    required int durasiDetik,
    required List<SplitKilometer> splits,
    required double rataRataKecepatanMs,
    DateTime? mulaiPada,
  }) {
    // Mengubah kilometer ke meter.
    final double jarakMeter = jarakKm * 1000.0;

    return <String, dynamic>{
      'name': namaAktivitas,
      'description': deskripsi,
      'distance': jarakMeter, // meter
      'type': 'Run', // strava SportType::Run
      'start_date': (mulaiPada ?? DateTime.now()).toUtc().toIso8601String(),
      'elapsed_time': durasiDetik, // detik
      'moving_time': durasiDetik, // detik
      'average_speed': rataRataKecepatanMs, // m/s
      'max_speed': _hitungKecepatanMaks(splits),
      'workout_type': 1, // 1 = race, sesuai ActivityType::Race
      // Array split per kilometer. Strava menghitung ulang pace
      // dari distance dan elapsed_time tiap split.
      'splits_metric': splits.map((SplitKilometer s) => s.keStravaSplit()).toList(),
      // Catatan etika: aktivitas simulasi diberi penanda pada deskripsi,
      // aktivitas yang dicurigai, bukan untuk menandai simulasi.
      // aktivitas yang dicurigai, bukan untuk menandai simulasi.
      // Penyalahgunaan field itu bisa membuat akun kena pembatasan.
    };
  }

  /// Menghitung kecepatan maksimum dari daftar split, dalam m/s.
  ///
  /// Kecepatan maksimum terjadi di kilometer tercepat, yaitu split
  /// dengan pace terkecil. Satu kilometer dengan pace 240 detik
  /// berarti 1000/240 = 4,17 meter per detik.
  static double _hitungKecepatanMaks(List<SplitKilometer> splits) {
    if (splits.isEmpty) return 0.0;

    int paceTercepat = splits.first.paceDetik;
    for (final SplitKilometer s in splits) {
      if (s.paceDetik < paceTercepat) {
        paceTercepat = s.paceDetik;
      }
    }

    return 1000.0 / paceTercepat;
  }

  // ------------------------------------------------------------
  // UPLOAD
  // ------------------------------------------------------------
  /// Mengirim activity ke Strava lewat POST.
  ///
  /// Mengembalikan `true` bila Strava menerima activity.
  ///
  /// Semua kondisi gagal ditangani di sini tanpa melempar exception,
  /// supaya UI cukup menampilkan pesan singkat.
  ///   - Token kosong: pengguna belum login.
  ///   - Respons di luar 2xx: Strava menolak, biasanya karena
  ///     scope kurang atau payload tidak valid.
  ///   - Timeout atau koneksi gagal: jaringan bermasalah.
  static Future<String?> unggahActivity({
    required Map<String, dynamic> payload,
  }) async {
    // Token kosong berarti belum otorisasi. Kembalikan pesan yang
    // bisa langsung ditampilkan ke pengguna.
    if (tokenAkses.isEmpty) {
      return 'Belum terhubung ke Strava. Login terlebih dahulu.';
    }

    final Uri url = Uri.parse('$baseUrl/activities');

    try {
      final http.Response respons = await _klien
          .post(
            url,
            headers: <String, String>{
              'Authorization': 'Bearer $tokenAkses',
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      // 201 Created adalah status sukses Strava untuk pembuatan activity.
      if (respons.statusCode == 201) {
        return null; // null berarti sukses, lihat catatan di bawah.
      }

      // Respons 401 berarti token kedaluwarsa atau salah.
      if (respons.statusCode == 401) {
        return 'Token Strava kedaluwarsa. Silakan login ulang.';
      }

      // Status lain: kembalikan body error supaya mudah didiagnosis.
      return 'Strava menolak upload (${respons.statusCode}). '
          '${respons.body}';
    } catch (error) {
      // Menangkap semua error jaringan.
      return 'Gagal menghubungi Strava. Periksa koneksi internetmu.';
    }
  }
}
