import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'account_service.dart';

/// Halaman masuk dan pendaftaran akun VoltStride.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
      if (mounted) setState(() => _pesanError = pesanErrorAkun(error));
    } catch (error) {
      if (mounted) {
        setState(() {
          _pesanError =
              'Akun belum dapat diproses. Periksa koneksi serta pengaturan Firebase.';
        });
      }
    } finally {
      if (mounted) setState(() => _sedangMemproses = false);
    }
  }

  Future<void> _lupaKataSandi() async {
    final String email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _pesanError = 'Isi email terlebih dahulu untuk menerima link pemulihan.');
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
        const SnackBar(
          content: Text('Link untuk mengatur ulang kata sandi telah dikirim jika email terdaftar.'),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _pesanError = pesanErrorAkun(error));
    } catch (_) {
      if (mounted) {
        setState(() => _pesanError = 'Link pemulihan belum dapat dikirim. Coba lagi nanti.');
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
    if (email.isEmpty) return 'Email wajib diisi.';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Masukkan alamat email yang valid.';
    }
    return null;
  }

  String? _periksaKataSandi(String? nilai) {
    final String sandi = nilai ?? '';
    if (sandi.isEmpty) return 'Kata sandi wajib diisi.';
    if (sandi.length < 8) return 'Gunakan minimal 8 karakter.';
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
                      _sedangDaftar ? 'Buat akunmu' : 'Selamat datang kembali',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _sedangDaftar
                          ? 'Simpan catatan latihan dan buka di perangkat lain dengan akun yang sama.'
                          : 'Masuk untuk melanjutkan.',
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
                        decoration: const InputDecoration(
                          labelText: 'Nama panggilan',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (String? nilai) {
                          if (nilai == null || nilai.trim().isEmpty) {
                            return 'Nama wajib diisi.';
                          }
                          if (nilai.trim().length < 2) {
                            return 'Nama minimal 2 karakter.';
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
                      decoration: const InputDecoration(
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
                        labelText: 'Kata sandi',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          tooltip: _sandiTerlihat
                              ? 'Sembunyikan kata sandi'
                              : 'Lihat kata sandi',
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
                        decoration: const InputDecoration(
                          labelText: 'Ulangi kata sandi',
                          prefixIcon: Icon(Icons.lock_reset_rounded),
                        ),
                        validator: (String? nilai) {
                          if (nilai != _sandiController.text) {
                            return 'Kedua kata sandi belum sama.';
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
                          : Text(_sedangDaftar ? 'Buat akun' : 'Masuk'),
                    ),
                    if (!_sedangDaftar) ...<Widget>[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _sedangMemproses ? null : _lupaKataSandi,
                        child: const Text('Lupa kata sandi?'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _sedangDaftar
                              ? 'Sudah punya akun?'
                              : 'Belum punya akun?',
                          style: const TextStyle(color: VoltWarna.teksAbu),
                        ),
                        TextButton(
                          onPressed: _sedangMemproses ? null : _gantiMode,
                          child: Text(_sedangDaftar ? 'Masuk' : 'Daftar'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Gunakan email dan kata sandi milikmu sendiri.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: VoltWarna.teksRedup,
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
