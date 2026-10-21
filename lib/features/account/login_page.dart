import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../../services/app_language_service.dart';
import 'account_service.dart';

/// Halaman masuk dan pendaftaran akun VoltStride.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _sandiController = TextEditingController();
  final TextEditingController _ulangSandiController = TextEditingController();

  bool _sedangDaftar = false;
  bool _sandiTerlihat = false;
  bool _sedangMemproses = false;
  String? _pesanError;

  @override
  void dispose() {
    _namaController.dispose();
    _emailController.dispose();
    _sandiController.dispose();
    _ulangSandiController.dispose();
    super.dispose();
  }

  Future<void> _kirimFormulir() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _sedangMemproses = true;
      _pesanError = null;
    });

    try {
      if (_sedangDaftar) {
        await AccountService.daftarAkun(
          nama: _namaController.text,
          email: _emailController.text,
          kataSandi: _sandiController.text,
        );
      } else {
        await AccountService.masukAkun(
          email: _emailController.text,
          kataSandi: _sandiController.text,
        );
      }
      // AccountGate mendeteksi perubahan login dan membuka halaman utama.
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _pesanError = pesanErrorAkun(error, english: Localizations.localeOf(context).languageCode == 'en'));
    } catch (error) {
      if (mounted) {
        setState(() {
          _pesanError =
              _text('Akun belum dapat diproses. Periksa koneksi serta pengaturan Firebase.', 'Could not process the account. Check your connection and Firebase settings.');
        });
      }
    } finally {
      if (mounted) setState(() => _sedangMemproses = false);
    }
  }

  Future<void> _lupaKataSandi() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _pesanError = _text('Isi email terlebih dahulu untuk menerima link pemulihan.', 'Enter your email to receive a password reset link.'));
      return;
    }

    setState(() {
      _sedangMemproses = true;
      _pesanError = null;
    });

    try {
      await AccountService.kirimLinkAturUlangSandi(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text('Link untuk mengatur ulang kata sandi telah dikirim jika email terdaftar.', 'If this email is registered, a password reset link has been sent.')),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _pesanError = pesanErrorAkun(error, english: Localizations.localeOf(context).languageCode == 'en'));
    } catch (_) {
      if (mounted) {
        setState(() => _pesanError = _text('Link pemulihan belum dapat dikirim. Coba lagi nanti.', 'Could not send the reset link. Try again later.'));
      }
    } finally {
      if (mounted) setState(() => _sedangMemproses = false);
    }
  }

  void _gantiMode() {
    setState(() {
      _sedangDaftar = !_sedangDaftar;
      _pesanError = null;
      _formKey.currentState?.reset();
      _namaController.clear();
      _emailController.clear();
      _sandiController.clear();
      _ulangSandiController.clear();
    });
  }

  String? _periksaEmail(String? nilai) {
    final String email = nilai?.trim() ?? '';
    if (email.isEmpty) return _text('Email wajib diisi.', 'Email is required.');
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return _text('Masukkan alamat email yang valid.', 'Enter a valid email address.');
    }
    return null;
  }

  String? _periksaKataSandi(String? nilai) {
    final String sandi = nilai ?? '';
    if (sandi.isEmpty) return _text('Kata sandi wajib diisi.', 'Password is required.');
    if (sandi.length < 8) return _text('Gunakan minimal 8 karakter.', 'Use at least 8 characters.');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Text(
                      _sedangDaftar ? _text('Buat akunmu', 'Create your account') : _text('Selamat datang kembali', 'Welcome back'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _sedangDaftar
                          ? _text('Simpan catatan latihan dan buka di perangkat lain dengan akun yang sama.', 'Save your training history and access it on other devices with the same account.')
                          : _text('Masuk untuk melanjutkan.', 'Sign in to continue.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: VoltWarna.teksAbu,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_sedangDaftar) ...<Widget>[
                      TextFormField(
                        controller: _namaController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: _text('Nama panggilan', 'Display name'),
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (String? nilai) {
                          if (nilai == null || nilai.trim().isEmpty) {
                            return _text('Nama wajib diisi.', 'Name is required.');
                          }
                          if (nilai.trim().length < 2) {
                            return _text('Nama minimal 2 karakter.', 'Name must be at least 2 characters.');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                      validator: _periksaEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _sandiController,
                      obscureText: !_sandiTerlihat,
                      textInputAction: _sedangDaftar
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: (_) {
                        if (!_sedangDaftar) _kirimFormulir();
                      },
                      decoration: InputDecoration(
                        labelText: _text('Kata sandi', 'Password'),
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _sandiTerlihat
                              ? _text('Sembunyikan kata sandi', 'Hide password')
                              : _text('Lihat kata sandi', 'Show password'),
                          onPressed: () => setState(
                            () => _sandiTerlihat = !_sandiTerlihat,
                          ),
                          icon: Icon(
                            _sandiTerlihat
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: _periksaKataSandi,
                    ),
                    if (_sedangDaftar) ...<Widget>[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ulangSandiController,
                        obscureText: !_sandiTerlihat,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _kirimFormulir(),
                        decoration: InputDecoration(
                          labelText: _text('Ulangi kata sandi', 'Confirm password'),
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                        ),
                        validator: (String? nilai) {
                          if (nilai != _sandiController.text) {
                            return _text('Kedua kata sandi belum sama.', 'The passwords do not match.');
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_pesanError != null) ...<Widget>[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: VoltWarna.merah.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.zero,
                          border: Border.all(
                            color: VoltWarna.merah.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          _pesanError!,
                          style: const TextStyle(height: 1.45),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _sedangMemproses ? null : _kirimFormulir,
                      child: _sedangMemproses
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: VoltWarna.latar,
                              ),
                            )
                          : Text(_sedangDaftar ? _text('Buat akun', 'Create account') : _text('Masuk', 'Sign in')),
                    ),
                    if (!_sedangDaftar) ...<Widget>[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _sedangMemproses ? null : _lupaKataSandi,
                        child: Text(_text('Lupa kata sandi?', 'Forgot password?')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _sedangDaftar
                              ? _text('Sudah punya akun?', 'Already have an account?')
                              : _text('Belum punya akun?', 'Do not have an account yet?'),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        TextButton(
                          onPressed: _sedangMemproses ? null : _gantiMode,
                          child: Text(_sedangDaftar ? _text('Masuk', 'Sign in') : _text('Daftar', 'Create one')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _text('Gunakan email dan kata sandi milikmu sendiri.', 'Use your own email address and password.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
