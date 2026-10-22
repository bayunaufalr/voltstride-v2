// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'account_service.dart';
import '../../services/app_language_service.dart';

/// Profil wajib dan ringkasan kemampuan latihan ditampilkan dalam satu alur.
class ProfileTrainingSummary extends StatelessWidget {
  const ProfileTrainingSummary({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AccountService.perubahanProfil,
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        final Map<String, dynamic> profile =
            snapshot.data?.data() ?? <String, dynamic>{};
        final DateTime? birthday =
            DateTime.tryParse(profile['tanggalLahir'] as String? ?? '');
        final int? age = birthday == null ? null : _ageFromBirthday(birthday);
        final String gender = profile['jenisKelamin'] as String? ?? '';
        final String bio = profile['bio'] as String? ?? '';
        final bool complete = birthday != null &&
            gender.isNotEmpty &&
            bio.trim().isNotEmpty;
        final Color secondaryText =
            Theme.of(context).colorScheme.onSurfaceVariant;
        String text(String indonesia, String english) =>
            AppLanguageService.text(context, indonesia, english);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          text('Profil', 'Profile'),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editProfile(context, profile),
                        child: Text(complete ? text('Edit', 'Edit') : text('Lengkapi', 'Complete profile')),
                      ),
                    ],
                  ),
                  if (!complete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        text('Tanggal lahir, jenis kelamin, dan bio wajib diisi.', 'Date of birth, gender, and bio are required.'),
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  if (birthday != null)
                    _profileRow(
                      context,
                      text('Umur', 'Age'),
                      text(
                        '${age ?? '--'} tahun · ${_dateText(birthday)}',
                        '${age ?? '--'} years · ${_dateText(birthday)}',
                      ),
                    ),
                  if (gender.isNotEmpty)
                    _profileRow(context, text('Jenis kelamin', 'Gender'), _genderText(context, gender)),
                  if (bio.trim().isNotEmpty)
                    _profileRow(context, text('Bio', 'Bio'), bio.trim()),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _genderText(BuildContext context, String value) {
    return switch (value) {
      'Laki-laki' => AppLanguageService.text(context, 'Laki-laki', 'Male'),
      'Perempuan' => AppLanguageService.text(context, 'Perempuan', 'Female'),
      'Tidak ingin menyebutkan' => AppLanguageService.text(
          context,
          'Tidak ingin menyebutkan',
          'Prefer not to say',
        ),
      _ => value,
    };
  }

  Widget _profileRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _editProfile(
    BuildContext context,
    Map<String, dynamic> profile,
  ) async {
    final GlobalKey<FormState> formKey = GlobalKey<FormState>();
    final TextEditingController bioController = TextEditingController(
      text: profile['bio'] as String? ?? '',
    );
    DateTime? birthday =
        DateTime.tryParse(profile['tanggalLahir'] as String? ?? '');
    String? gender = profile['jenisKelamin'] as String?;
    String? validationMessage;
    bool saving = false;

    try {
      final bool? saved = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => StatefulBuilder(
          builder: (
            BuildContext dialogContext,
            StateSetter setDialogState,
          ) {
            final int? age = birthday == null ? null : _ageFromBirthday(birthday!);
            String dialogText(String indonesia, String english) =>
                AppLanguageService.text(dialogContext, indonesia, english);
            return AlertDialog(
              title: Text(dialogText('Data profil', 'Profile details')),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final DateTime now = DateTime.now();
                                  final DateTime? chosen = await showDatePicker(
                                    context: dialogContext,
                                    initialDate: birthday ??
                                        DateTime(now.year - 16, now.month, now.day),
                                    firstDate: DateTime(1900),
                                    lastDate: now,
                                    helpText: dialogText('Pilih tanggal lahir', 'Choose date of birth'),
                                  );
                                  if (chosen != null) {
                                    setDialogState(() {
                                      birthday = chosen;
                                      validationMessage = null;
                                    });
                                  }
                                },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(dialogText('Tanggal lahir *', 'Date of birth *')),
                              Text(birthday == null
                                  ? dialogText('Pilih tanggal', 'Choose date')
                                  : _dateText(birthday!)),
                            ],
                          ),
                        ),
                        if (age != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Text(dialogText('Umur: $age tahun', 'Age: $age years')),
                          ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: gender,
                          decoration: InputDecoration(
                            labelText: dialogText('Jenis kelamin *', 'Gender *'),
                          ),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'Laki-laki',
                              child: Text(dialogText('Laki-laki', 'Male')),
                            ),
                            DropdownMenuItem(
                              value: 'Perempuan',
                              child: Text(dialogText('Perempuan', 'Female')),
                            ),
                            DropdownMenuItem(
                              value: 'Tidak ingin menyebutkan',
                              child: Text(dialogText(
                                'Tidak ingin menyebutkan',
                                'Prefer not to say',
                              )),
                            ),
                          ],
                          validator: (String? value) =>
                              value == null || value.isEmpty
                                  ? dialogText('Pilih jenis kelamin.', 'Choose your gender.')
                                  : null,
                          onChanged: saving
                              ? null
                              : (String? value) => setDialogState(
                                    () => gender = value,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: bioController,
                          maxLines: 3,
                          maxLength: 160,
                          decoration: InputDecoration(
                            labelText: dialogText('Bio *', 'Bio *'),
                            hintText: dialogText('Tulis bio singkat', 'Write a short bio'),
                            alignLabelWithHint: true,
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return dialogText('Bio wajib diisi.', 'Bio is required.');
                            }
                            if (value.trim().length < 3) {
                              return dialogText('Bio terlalu singkat.', 'Bio is too short.');
                            }
                            return null;
                          },
                        ),
                        if (validationMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              validationMessage!,
                              style: TextStyle(
                                color: Theme.of(dialogContext).colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: Text(dialogText('Batal', 'Cancel')),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          if (birthday == null) {
                            setDialogState(() {
                              validationMessage = dialogText('Pilih tanggal lahir.', 'Choose your date of birth.');
                            });
                            return;
                          }
                          if (gender == null || gender!.isEmpty) {
                            setDialogState(() {
                              validationMessage = dialogText('Pilih jenis kelamin.', 'Choose your gender.');
                            });
                            return;
                          }
                          setDialogState(() => saving = true);
                          try {
                            await AccountService.perbaruiDetailProfil(
                              tanggalLahir: birthday!,
                              jenisKelamin: gender!,
                              bio: bioController.text,
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop(true);
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              saving = false;
                              validationMessage = dialogText('Profil belum berhasil disimpan.', 'Could not save the profile.');
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(dialogText('Simpan', 'Save')),
                ),
              ],
            );
          },
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLanguageService.text(context, 'Profil diperbarui.', 'Profile updated.'))),
        );
      }
    } finally {
      bioController.dispose();
    }
  }

  static int _ageFromBirthday(DateTime birthday) {
    final DateTime today = DateTime.now();
    int age = today.year - birthday.year;
    if (today.month < birthday.month ||
        (today.month == birthday.month && today.day < birthday.day)) {
      age--;
    }
    return age;
  }

  static String _dateText(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
