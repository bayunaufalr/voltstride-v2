import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/profil_pelari.dart';
import '../models/rencana_latihan.dart';

/// Menghubungkan modul coach lokal dengan layanan AI melalui HTTP.
///
/// Layanan ini mengirim profil atau kerangka rencana latihan ke backend.
/// Jika server tidak merespons, metode mengembalikan `null` agar pemanggil
/// dapat memakai hasil lokal. Perhitungan inti tidak seharusnya bergantung
/// pada koneksi internet.
///
/// Catatan: layanan ini berasal dari alur pelacak lama. Halaman coach yang
/// dibuka melalui navigasi utama saat ini memakai `AiCoachService` lokal di
/// `features/ai_coach/ai_coach_service.dart`, bukan layanan HTTP ini.
class OnlineCoachService {
  /// Alamat endpoint AI. Ganti dengan milikmu sendiri saat deploy.
  ///
  /// Format endpoint yang diharapkan:
  ///   POST {endpoint}/chat      -> body: {profil, pesan, riwayat}
  ///   POST {endpoint}/rencana  -> body: {profil, rencanaLokal}
  ///
  /// Header wajib: Authorization: Bearer {apiKey}.
  static const String endpoint =
      'https://api.voltstride.id/v1';

  /// API key. Nilai di bawah hanya placeholder untuk portofolio.
  ///
  /// Nilai ini hanya placeholder dan tidak dapat dipakai untuk autentikasi.
  /// Untuk produksi, simpan kunci rahasia di backend atau layanan serverless
  /// seperti Cloud Functions/Cloud Run. Jangan menanam kunci rahasia di APK:
  /// isi APK dapat diperiksa oleh orang lain.
  static const String apiKey = 'GANTI_DENGAN_API_KEY_MILIKMU';

  /// Batas waktu tiap request. Jika terlampaui, metode mengembalikan `null`
  /// sehingga layar dapat melanjutkan dengan jawaban atau rencana lokal.
  static const int timeoutDetik = 12;

  /// Klien HTTP yang dipakai ulang untuk request di kelas ini.
  static final http.Client _klien = http.Client();

  // ------------------------------------------------------------
  // PAYLOAD
  // ------------------------------------------------------------
  /// Membangun body JSON profil pelari untuk dikirim ke server.
  ///
  /// Server butuh data ini agar bisa memberi saran yang relevan:
  /// umur, target jarak, target pace adaptif, skor kebugaran, dan
  /// peta zona latihan.
  static Map<String, dynamic> profilKeJson(ProfilPelari profil) {
    return <String, dynamic>{
      'umur': profil.umur,
      'target_jarak_km': profil.targetJarakKm,
      'target_pace_detik_per_km': profil.targetPaceAdaptifDetik,
      'pace_10km_terakhir_detik_per_km': profil.pace10kTerakhirDetik,
      'hr_max_estimasi': profil.hrMaxEstimasi,
      'skor_kebugaran': double.parse(profil.skorKebugaran.toStringAsFixed(1)),
      'zona_tempo_bpm': <String, int>{
        'bawah': profil.zonaTempo.bawah,
        'atas': profil.zonaTempo.atas,
      },
      'peta_zona_detik_per_km': <String, int>{
        'easy': profil.petaZona.paceEasy,
        'tempo': profil.petaZona.paceTempo,
        'interval': profil.petaZona.paceInterval,
        'long_run': profil.petaZona.paceLongRun,
      },
    };
  }

  /// Membangun body JSON rencana lokal untuk dikirim ke server.
  ///
  /// Server menerima kerangka lokal lalu bisa menyesuaikannya.
  /// Mengirim rancangan latihan lokal sebagai dasar penyesuaian server.
  /// Dengan begitu, server menerima konteks awal dan hasilnya tetap mengikuti
  /// struktur data yang dipahami oleh aplikasi.
  static Map<String, dynamic> rencanaKeJson(RencanaLatihan rencana) {
    return <String, dynamic>{
      'jumlah_minggu': rencana.jumlahMinggu,
      'tujuan': rencana.tujuan,
      'minggu': rencana.minggu.map((MingguLatihan mg) {
        return <String, dynamic>{
          'nomor': mg.nomor,
          'fase': mg.fase,
          'total_km': double.parse(mg.totalJarakKm.toStringAsFixed(1)),
          'sesi': mg.sesi.map((SesiLatihan s) {
            return <String, dynamic>{
              'nama': s.nama,
              'hari': s.hari,
              'jarak_km': s.jarakKm,
              'pace_detik_per_km': s.paceDetik,
              'durasi_menit': double.parse(s.durasiMenit.toStringAsFixed(1)),
            };
          }).toList(),
        };
      }).toList(),
    };
  }

  // ------------------------------------------------------------
  // CHAT
  // ------------------------------------------------------------
  /// Mengirim pertanyaan ke online coach dan menerima jawabannya.
  ///
  /// Parameter:
  ///   - [profil]: profil pelari hasil hitungan engine lokal.
  ///   - [pertanyaan]: pesan pengguna.
  ///   - [riwayat]: percakapan sebelumnya dalam bentuk daftar role dan isi.
  ///
  /// Mengembalikan teks jawaban coach, atau null bila server gagal.
  /// Null berarti UI harus memakai fallback lokal.
  ///
  /// Timeout, status HTTP gagal, atau JSON yang tidak valid ditangani
  /// dengan mengembalikan null agar error tidak merambat ke tampilan.
  static Future<String?> tanyaCoach({
    required ProfilPelari profil,
    required String pertanyaan,
    required List<Map<String, String>> riwayat,
  }) async {
    final Uri url = Uri.parse('$endpoint/chat');

    try {
      // .timeout() membungkus seluruh future sehingga request yang
      // menggantung tidak akan membekukan UI.
      final http.Response respons = await _klien
          .post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, dynamic>{
              'profil': profilKeJson(profil),
              'pesan': pertanyaan,
              'riwayat': riwayat,
            }),
          )
          .timeout(const Duration(seconds: timeoutDetik));

      // Terima semua kode HTTP pada rentang 2xx sebagai respons sukses.
      if (respons.statusCode < 200 || respons.statusCode >= 300) {
        return null;
      }

      // Decode JSON. Kalau body bukan JSON valid, jsonDecode melempar
      // FormatException yang ditangkap oleh catch di bawah.
      final Map<String, dynamic> data =
          jsonDecode(respons.body) as Map<String, dynamic>;

      final String? jawaban = data['jawaban'] as String?;
      return jawaban;
    } catch (_) {
      // Semua jenis error (timeout, socket, format JSON, dll) berakhir di
      // sini. Mengembalikan null jauh lebih aman daripada melempar
      // exception ke UI.
      return null;
    }
  }

  // ------------------------------------------------------------
  // RENCANA
  // ------------------------------------------------------------
  /// Meminta server menyesuaikan rencana latihan lokal.
  ///
  /// Mengembalikan rencana hasil server, atau null bila gagal.
  /// UI harus selalu menampilkan rencana lokal sebagai default.
  static Future<RencanaLatihan?> mintaRencana({
    required ProfilPelari profil,
    required RencanaLatihan rencanaLokal,
  }) async {
    final Uri url = Uri.parse('$endpoint/rencana');

    try {
      final http.Response respons = await _klien
          .post(
            url,
            headers: <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, dynamic>{
              'profil': profilKeJson(profil),
              'rencana_lokal': rencanaKeJson(rencanaLokal),
            }),
          )
          .timeout(const Duration(seconds: timeoutDetik));

      if (respons.statusCode < 200 || respons.statusCode >= 300) {
        return null;
      }

      // Parse JSON server ke object RencanaLatihan.
      final Map<String, dynamic> data =
          jsonDecode(respons.body) as Map<String, dynamic>;
      return _jsonKeRencana(data);
    } catch (_) {
      return null;
    }
  }

  /// Mengubah JSON dari server menjadi [RencanaLatihan].
  /// Nilai default membantu menangani beberapa field opsional yang tidak
  /// dikirim server. Struktur inti tetap harus valid agar rencana bisa dipakai.
  static RencanaLatihan? _jsonKeRencana(Map<String, dynamic> json) {
    try {
      final List<dynamic> mingguJson =
          (json['minggu'] as List<dynamic>?) ?? <dynamic>[];

      final List<MingguLatihan> minggu = <MingguLatihan>[];

      for (final dynamic item in mingguJson) {
        final Map<String, dynamic> mg =
            item as Map<String, dynamic>;

        final List<SesiLatihan> sesi = <SesiLatihan>[];

        for (final dynamic itemSesi
            in (mg['sesi'] as List<dynamic>?) ?? <dynamic>[]) {
          final Map<String, dynamic> sj = itemSesi as Map<String, dynamic>;

          // Semua angka datang dari server sebagai dynamic, jadi harus
          // dikonversi eksplisit ke tipe Dart yang benar.
          sesi.add(SesiLatihan(
            nama: (sj['nama'] as String?) ?? 'Sesi Latihan',
            hari: (sj['hari'] as num?)?.toInt() ?? 1,
            jarakKm: (sj['jarak_km'] as num?)?.toDouble(),
            paceDetik: (sj['pace_detik_per_km'] as num?)?.toInt(),
            durasiMenit:
                (sj['durasi_menit'] as num?)?.toDouble() ?? 30.0,
            zonaJantung: sj['zona'] as String?,
            instruksi: (sj['instruksi'] as String?) ?? 'Ikuti struktur sesi.',
            // Tandai asal data supaya UI bisa menampilkan badge "Coach".
            sumber: 'COACH',
          ));
        }

        minggu.add(MingguLatihan(
          nomor: (mg['nomor'] as num?)?.toInt() ?? minggu.length + 1,
          tema: (mg['tema'] as String?) ?? 'Latihan',
          fase: (mg['fase'] as String?) ?? 'build',
          sesi: sesi,
        ));
      }

      if (minggu.isEmpty) return null;

      return RencanaLatihan(
        tujuan: (json['tujuan'] as String?) ?? 'Rencana latihan',
        jumlahMinggu: (json['jumlah_minggu'] as num?)?.toInt() ?? minggu.length,
        minggu: minggu,
        ringkasan: (json['ringkasan'] as String?) ??
            'Rencana disesuaikan oleh online coach.',
      );
    } catch (_) {
      // JSON server tidak sesuai struktur yang diharapkan.
      return null;
    }
  }
}
