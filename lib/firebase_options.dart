import 'package:firebase_core/firebase_core.dart';

/// Berkas sementara sampai VoltStride dihubungkan ke proyek Firebase milikmu.
///
/// Jalankan `flutterfire configure` dari folder proyek untuk mengganti berkas
/// ini dengan konfigurasi Firebase yang sesuai. Nilai konfigurasi tersebut
/// bukan kata sandi, tetapi tetap gunakan proyek Firebase milikmu sendiri.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    throw UnsupportedError(
      'Firebase belum dikonfigurasi. Jalankan perintah '
      '`flutterfire configure` dari folder proyek VoltStride.',
    );
  }
}
