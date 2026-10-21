import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Mengurus akun VoltStride dan profil yang disimpan di Firebase.
///
/// Firebase Authentication menyimpan akun serta sesi login. Profil tambahan
/// disimpan di Firestore pada users/{uid}; UID adalah ID unik milik satu akun.
class AccountService {
  AccountService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _database = FirebaseFirestore.instance;

  static Stream<User?> get perubahanAkun => _auth.authStateChanges();
  static User? get akunAktif => _auth.currentUser;

  static CollectionReference<Map<String, dynamic>> get _profilAkun =>
      _database.collection('users');


  /// Aliran perubahan profil pengguna yang sedang masuk.
  static Stream<DocumentSnapshot<Map<String, dynamic>>> get perubahanProfil {
    final User? pengguna = _auth.currentUser;
    if (pengguna == null) return const Stream.empty();
    return _profilAkun.doc(pengguna.uid).snapshots();
  }

  /// Menyimpan foto profil kecil sebagai teks Base64 di dokumen akun.
  /// Dengan cara ini foto ikut tersinkron tanpa Firebase Storage berbayar.
  static Future<void> perbaruiFotoProfil(String fotoBase64) async {
    final User? pengguna = _auth.currentUser;
    if (pengguna == null) {
      throw StateError('Masuk ke akun sebelum mengubah foto profil.');
    }
    if (fotoBase64.isEmpty || fotoBase64.length > 700 * 1024) {
      throw ArgumentError('Ukuran foto profil tidak sesuai.');
    }

    await _profilAkun.doc(pengguna.uid).set(
      <String, dynamic>{
        'fotoProfilBase64': fotoBase64,
        'diperbaruiPada': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Mengembalikan avatar ke ikon orang bawaan.
  static Future<void> hapusFotoProfil() async {
    final User? pengguna = _auth.currentUser;
    if (pengguna == null) {
      throw StateError('Masuk ke akun sebelum mengubah foto profil.');
    }
    await _profilAkun.doc(pengguna.uid).set(
      <String, dynamic>{
        'fotoProfilBase64': FieldValue.delete(),
        'diperbaruiPada': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Membuat akun baru dengan nama, email, dan kata sandi.
  static Future<UserCredential> daftarAkun({
    required String nama,
    required String email,
    required String kataSandi,
  }) async {
    final UserCredential hasil = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: kataSandi,
    );

    final User? pengguna = hasil.user;
    if (pengguna == null) {
      throw FirebaseAuthException(
        code: 'user-creation-failed',
        message: 'Akun berhasil diproses, tetapi data pengguna tidak tersedia.',
      );
    }

    await pengguna.updateDisplayName(nama.trim());
    await _simpanProfil(pengguna, nama: nama.trim(), buatProfilBaru: true);
    return hasil;
  }

  /// Masuk ke akun yang sudah terdaftar.
  static Future<UserCredential> masukAkun({
    required String email,
    required String kataSandi,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: kataSandi,
    );
  }

  /// Menyimpan data profil yang dibutuhkan untuk analisis latihan.
  static Future<void> perbaruiDetailProfil({
    required DateTime tanggalLahir,
    required String jenisKelamin,
    required String bio,
  }) async {
    final User? pengguna = _auth.currentUser;
    if (pengguna == null) {
      throw StateError('Masuk ke akun sebelum mengubah profil.');
    }

    final DateTime tanggal = DateTime(
      tanggalLahir.year,
      tanggalLahir.month,
      tanggalLahir.day,
    );
    final DateTime sekarang = DateTime.now();
    if (tanggal.isAfter(DateTime(sekarang.year, sekarang.month, sekarang.day))) {
      throw ArgumentError('Tanggal lahir tidak boleh di masa depan.');
    }
    if (jenisKelamin.trim().isEmpty || bio.trim().isEmpty) {
      throw ArgumentError('Tanggal lahir, jenis kelamin, dan bio wajib diisi.');
    }

    await _profilAkun.doc(pengguna.uid).set(
      <String, dynamic>{
        'tanggalLahir':
            '${tanggal.year.toString().padLeft(4, '0')}-'
            '${tanggal.month.toString().padLeft(2, '0')}-'
            '${tanggal.day.toString().padLeft(2, '0')}',
        'jenisKelamin': jenisKelamin.trim(),
        'bio': bio.trim(),
        'diperbaruiPada': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  /// Mengirim email untuk mengatur ulang kata sandi.
  static Future<void> kirimLinkAturUlangSandi(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Keluar dari akun aktif di perangkat ini.
  static Future<void> keluarAkun() => _auth.signOut();

  /// Memastikan akun memiliki dokumen profil, termasuk akun lama yang dibuat
  /// sebelum fitur profil cloud tersedia.
  static Future<void> pastikanProfilAda(User pengguna) async {
    final DocumentReference<Map<String, dynamic>> dokumen =
        _profilAkun.doc(pengguna.uid);
    final DocumentSnapshot<Map<String, dynamic>> hasil = await dokumen.get();
    if (hasil.exists) return;

    await _simpanProfil(
      pengguna,
      nama: pengguna.displayName ?? '',
      buatProfilBaru: true,
    );
  }

  static Future<void> _simpanProfil(
    User pengguna, {
    required String nama,
    required bool buatProfilBaru,
  }) async {
    final Map<String, dynamic> dataProfil = <String, dynamic>{
      'uid': pengguna.uid,
      'nama': nama,
      'email': pengguna.email,
      'diperbaruiPada': FieldValue.serverTimestamp(),
    };

    if (buatProfilBaru) {
      dataProfil['dibuatPada'] = FieldValue.serverTimestamp();
    }

    await _profilAkun.doc(pengguna.uid).set(
          dataProfil,
          SetOptions(merge: true),
        );
  }
}

/// Pesan error yang lebih mudah dipahami pengguna aplikasi.
String pesanErrorAkun(FirebaseAuthException error, {bool english = false}) {
  if (english) {
    switch (error.code) {
      case 'invalid-email': return 'Enter a valid email address.';
      case 'email-already-in-use': return 'This email is already registered. Try signing in.';
      case 'weak-password': return 'This password is too easy to guess. Use a stronger password.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential': return 'The email or password is incorrect.';
      case 'too-many-requests': return 'There have been too many attempts. Wait a moment and try again.';
      case 'network-request-failed': return 'Could not connect to the internet. Check your connection and try again.';
      case 'operation-not-allowed': return 'Email and password sign-in is not enabled in Firebase Console.';
      case 'requires-recent-login': return 'Sign in again before making this change.';
      default: return error.message?.isNotEmpty == true
          ? 'Could not process the account: ${error.message}'
          : 'Could not process the account. Please try again shortly.';
    }
  }
  switch (error.code) {
    case 'invalid-email':
      return 'Format email belum benar. Periksa kembali alamat emailmu.';
    case 'email-already-in-use':
      return 'Email ini sudah terdaftar. Coba masuk ke akunmu.';
    case 'weak-password':
      return 'Kata sandi terlalu mudah ditebak. Gunakan kata sandi yang lebih kuat.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Email atau kata sandi tidak cocok.';
    case 'too-many-requests':
      return 'Terlalu banyak percobaan. Tunggu sebentar sebelum mencoba lagi.';
    case 'network-request-failed':
      return 'Tidak dapat terhubung ke internet. Periksa koneksi lalu coba lagi.';
    case 'operation-not-allowed':
      return 'Login email dan kata sandi belum diaktifkan di Firebase Console.';
    case 'requires-recent-login':
      return 'Silakan masuk kembali sebelum melakukan perubahan ini.';
    default:
      return error.message?.isNotEmpty == true
          ? 'Akun belum dapat diproses: ${error.message}'
          : 'Akun belum dapat diproses. Coba lagi beberapa saat.';
  }
}
