import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'account_service.dart';
import '../running/models/run_session.dart';
import 'training_insights_card.dart';

/// Profil wajib dan ringkasan kemampuan latihan ditampilkan dalam satu alur.
class ProfileTrainingSummary extends StatelessWidget {
  const ProfileTrainingSummary({super.key, required this.sessions});

  final List<RunSession> sessions;

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
                      const Expanded(
                        child: Text(
                          'Profil',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editProfile(context, profile),
                        child: Text(complete ? 'Edit' : 'Lengkapi'),
                      ),
                    ],
                  ),
                  if (!complete)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Tanggal lahir, jenis kelamin, dan bio wajib diisi.',
                        style: TextStyle(fontSize: 12, color: secondaryText),
                      ),
                    ),
                  if (birthday != null)
                    _profileRow(
                      context,
                      'Umur',
                      '${age ?? '--'} tahun · ${_dateText(birthday)}',
                    ),
                  if (gender.isNotEmpty)
                    _profileRow(context, 'Jenis kelamin', gender),
                  if (bio.trim().isNotEmpty)
                    _profileRow(context, 'Bio', bio.trim()),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TrainingInsightsCard(sessions: sessions, age: age),
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
              title: const Text('Data profil'),
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
                                    helpText: 'Pilih tanggal lahir',
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
                              const Text('Tanggal lahir *'),
                              Text(birthday == null
                                  ? 'Pilih tanggal'
                                  : _dateText(birthday!)),
                            ],
                          ),
                        ),
                        if (age != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 10),
                            child: Text('Umur: $age tahun'),
                          ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: gender,
                          decoration: const InputDecoration(
                            labelText: 'Jenis kelamin *',
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'Laki-laki',
                              child: Text('Laki-laki'),
                            ),
                            DropdownMenuItem(
                              value: 'Perempuan',
                              child: Text('Perempuan'),
                            ),
                            DropdownMenuItem(
                              value: 'Tidak ingin menyebutkan',
                              child: Text('Tidak ingin menyebutkan'),
                            ),
                          ],
                          validator: (String? value) =>
                              value == null || value.isEmpty
                                  ? 'Pilih jenis kelamin.'
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
                          decoration: const InputDecoration(
                            labelText: 'Bio *',
                            hintText: 'Tulis bio singkat',
                            alignLabelWithHint: true,
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Bio wajib diisi.';
                            }
                            if (value.trim().length < 3) {
                              return 'Bio terlalu singkat.';
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
                  child: const Text('Batal'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          if (birthday == null) {
                            setDialogState(() {
                              validationMessage = 'Pilih tanggal lahir.';
                            });
                            return;
                          }
                          if (gender == null || gender!.isEmpty) {
                            setDialogState(() {
                              validationMessage = 'Pilih jenis kelamin.';
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
                              validationMessage = 'Profil belum berhasil disimpan.';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Simpan'),
                ),
              ],
            );
          },
        ),
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil diperbarui.')),
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
