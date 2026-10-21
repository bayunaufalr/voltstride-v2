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
                          AppLanguageService.text(context, 'Profil', 'Profile'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editProfile(context, profile),
                        child: Text(complete ? AppLanguageService.text(context, 'Edit', 'Edit') : AppLanguageService.text(context, 'Lengkapi', 'Complete')),
                      ),
                    ],
                  ),
                  if (!complete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        AppLanguageService.text(context, 'Tanggal lahir, jenis kelamin, dan bio wajib diisi.', 'Date of birth, gender, and bio are required.'),
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  if (birthday != null)
                    _profileRow(
                      context,
                      'Umur',
                      '${age ?? '--'} ${AppLanguageService.text(context, 'tahun', 'years old')} · ${_dateText(birthday)}',
                    ),
                  if (gender.isNotEmpty)
                    _profileRow(context, AppLanguageService.text(context, 'Jenis kelamin', 'Gender'), _genderLabel(context, gender)),
                  if (bio.trim().isNotEmpty)
                    _profileRow(context, AppLanguageService.text(context, 'Bio', 'Bio'), bio.trim()),
                ],
              ),
            ),
          ],
        );
      },
    );
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
            return AlertDialog(
              title: Text(AppLanguageService.text(dialogContext, 'Data profil', 'Profile details')),
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
                                    helpText: AppLanguageService.text(dialogContext, 'Pilih tanggal lahir', 'Choose date of birth'),
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
                              Text(AppLanguageService.text(dialogContext, 'Tanggal lahir *', 'Date of birth *')),
                              Text(birthday == null
                                  ? AppLanguageService.text(dialogContext, 'Pilih tanggal', 'Choose a date')
                                  : _dateText(birthday!)),
                            ],
                          ),
                        ),
                        if (age != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Text(AppLanguageService.text(dialogContext, 'Umur: $age tahun', 'Age: $age years')),
                          ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: gender,
                          decoration: InputDecoration(
                            labelText: AppLanguageService.text(dialogContext, 'Jenis kelamin *', 'Gender *'),
                          ),
                          items: <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'Laki-laki',
                              child: Text(AppLanguageService.text(dialogContext, 'Laki-laki', 'Male')),
                            ),
                            DropdownMenuItem(
                              value: 'Perempuan',
                              child: Text(AppLanguageService.text(dialogContext, 'Perempuan', 'Female')),
                            ),
                            DropdownMenuItem(
                              value: 'Tidak ingin menyebutkan',
                              child: Text(AppLanguageService.text(dialogContext, 'Tidak ingin menyebutkan', 'Prefer not to say')),
                            ),
                          ],
                          validator: (String? value) =>
                              value == null || value.isEmpty
                                  ? AppLanguageService.text(dialogContext, 'Pilih jenis kelamin.', 'Choose a gender.')
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
                            labelText: AppLanguageService.text(dialogContext, 'Bio *', 'Bio *'),
                            hintText: AppLanguageService.text(dialogContext, 'Tulis bio singkat', 'Write a short bio'),
                            alignLabelWithHint: true,
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return AppLanguageService.text(dialogContext, 'Bio wajib diisi.', 'Bio is required.') as String;
                            }
                            if (value.trim().length < 3) {
                              return AppLanguageService.text(dialogContext, 'Bio terlalu singkat.', 'Bio is too short.') as String;
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
                  child: Text(AppLanguageService.text(dialogContext, 'Batal', 'Cancel')),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          if (birthday == null) {
                            setDialogState(() {
                              validationMessage = AppLanguageService.text(dialogContext, 'Pilih tanggal lahir.', 'Choose a date of birth.');
                            });
                            return;
                          }
                          if (gender == null || gender!.isEmpty) {
                            setDialogState(() {
                              validationMessage = AppLanguageService.text(dialogContext, 'Pilih jenis kelamin.', 'Choose a gender.');
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
                              validationMessage = AppLanguageService.text(dialogContext, 'Profil belum berhasil disimpan.', 'Could not save the profile.');
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(AppLanguageService.text(dialogContext, 'Simpan', 'Save')),
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


  static String _genderLabel(BuildContext context, String gender) {
    switch (gender) {
      case 'Laki-laki':
        return AppLanguageService.text(context, 'Laki-laki', 'Male');
      case 'Perempuan':
        return AppLanguageService.text(context, 'Perempuan', 'Female');
      case 'Tidak ingin menyebutkan':
        return AppLanguageService.text(context, 'Tidak ingin menyebutkan', 'Prefer not to say');
      default:
        return gender;
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
