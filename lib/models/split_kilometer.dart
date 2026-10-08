/// ============================================================
/// MODEL: SPLIT KILOMETER
/// ============================================================
/// Objek ini mewakili SATU kilometer yang sudah selesai (atau sedang
/// berjalan) di simulasi balapan maupun rekaman GPS.
///
/// Kenapa perlu model sendiri (bukan Map atau array biasa)?
///  1. Data split dipakai tiga tempat sekaligus:
///     - kartu "strategi pace" di layar simulasi,
///     - payload JSON yang dikirim ke Strava,
///     - riwayat latihan di portofolio.
///     Model tunggal memastikan formatnya konsisten di semua tempat.
///  2. Typo pada nama field dicegah oleh tipe data, bukan dicek manual.
class SplitKilometer {
  /// Nomor kilometer (1-based). Kilometer ke-1 adalah yang pertama.
  final int nomor;

  /// Paca rata-rata kilometer ini dalam **detik per kilometer**.
  /// Disimpan sebagai int (detik) agar bebas dari pembulatan float.
  final int paceDetik;

  /// Waktu tempuh kumulatif sampai finishing kilometer ini (detik).
  final int waktuKumulatifDetik;

  /// Label jenis segmen, misalnya "PEMASAN", "TEMPO", "SPRINT".
  /// Dipakai untuk warna badge di UI dan intensitas di Strava.
  final String labelSegmen;

  /// Deskripsi singkat strategi yang dijalankan AI untuk kilometer ini.
  final String catatanCoach;

  SplitKilometer({
    required this.nomor,
    required this.paceDetik,
    required this.waktuKumulatifDetik,
    required this.labelSegmen,
    this.catatanCoach = '',
  });

  // ------------------------------------------------------------
  // FORMATTER PACE
  // ------------------------------------------------------------
  /// Mengubah pace (detik/km) menjadi teks "M'SS".
  /// Contoh: 245 detik menjadi "4'05"".
  ///
  /// Format ini dipakai di seluruh aplikasi agar tampilan pace konsisten
  /// dengan kebiasaan pelari (menit:detik per km).
  String get paceTeks {
    final int menit = paceDetik ~/ 60; // pembagian bulat -> menit
    final int detik = paceDetik % 60; // sisa pembagian -> detik
    return "$menit'${detik.toString().padLeft(2, '0')}\"";
  }

  /// Pace dalam bentuk menit desimal, untuk menghitung selisih pace.
  /// Contoh: 245 detik = 4.0833 menit.
  double get paceMenit => paceDetik / 60.0;

  /// Waktu kumulatif format HH:MM:SS untuk layar.
  String get waktuTeks {
    final int jam = waktuKumulatifDetik ~/ 3600;
    final int menit = (waktuKumulatifDetik % 3600) ~/ 60;
    final int detik = waktuKumulatifDetik % 60;
    return '${jam.toString().padLeft(2, '0')}:'
        '${menit.toString().padLeft(2, '0')}:'
        '${detik.toString().padLeft(2, '0')}';
  }

  /// Konversi ke Map untuk payload Strava.
  ///
  /// Tiga hal yang sering salah dan harus dijaga di sini:
  ///   - `distance` dalam **meter**, bukan kilometer;
  ///   - `elapsed_time` dalam **detik**;
  ///   - `average_speed` dalam **meter per detik**, bukan km/jam.
  ///     Salah satuan di sini membuat Strava menolak activity.
  Map<String, dynamic> keStravaSplit() {
    return <String, dynamic>{
      'distance': 1000.0, // meter
      'elapsed_time': paceDetik, // detik untuk 1 km
      'average_speed': 1000.0 / paceDetik, // m/s
      'pace_zone': _keStravaIntensity(),
    };
  }

  /// Menentukan tingkat intensitas (1..5) untuk Strava berdasarkan pace.
  ///
  /// Strava hanya menerima lima tingkat intensitas, jadi kita memetakan
  /// pace absolut ke skala tersebut. Ambang dipilih generik agar cocok
  /// untuk mayoritas pelari recreational.
  int _keStravaIntensity() {
    final double menitPerKm = paceMenit;
    if (menitPerKm <= 3.5) return 5; // sangat cepat
    if (menitPerKm <= 4.2) return 4; // cepat
    if (menitPerKm <= 5.0) return 3; // tempo
    if (menitPerKm <= 6.0) return 2; // ringan
    return 1; // sangat ringan / pemanasan
  }

  @override
  String toString() =>
      'SplitKilometer #$nomor: $paceTeks ($labelSegmen) total $waktuTeks';
}