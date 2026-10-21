import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Menyimpan bahasa aplikasi supaya pilihan tetap dipakai setelah aplikasi dibuka ulang.
class AppLanguageService {
  AppLanguageService._();

  static const String _storageKey = 'voltstride_app_language';
  static final ValueNotifier<Locale> localeNotifier =
      ValueNotifier<Locale>(const Locale('id'));

  static Future<void> load() async {
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      final String saved = preferences.getString(_storageKey) ?? 'id';
      localeNotifier.value = Locale(saved == 'en' ? 'en' : 'id');
    } catch (_) {
      // Preferensi bahasa yang gagal dibaca tidak boleh mencegah runApp().
      localeNotifier.value = const Locale('id');
    }
  }

  static Future<void> setLanguage(Locale locale) async {
    final String code = locale.languageCode == 'en' ? 'en' : 'id';
    localeNotifier.value = Locale(code);
    try {
      final SharedPreferences preferences =
          await SharedPreferences.getInstance();
      await preferences.setString(_storageKey, code);
    } catch (_) {
      // Bahasa langsung berganti pada sesi ini meski tidak dapat disimpan.
    }
  }

  /// Terjemahan untuk bagian yang telah mendukung Bahasa Indonesia dan Inggris.
  static String text(BuildContext context, String indonesia, String english) {
    return Localizations.localeOf(context).languageCode == 'en'
        ? english
        : indonesia;
  }

  static String textForCode(String code, String indonesia, String english) {
    return code == 'en' ? english : indonesia;
  }
}

class AppLanguageSettingCard extends StatelessWidget {
  const AppLanguageSettingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final Color border = Theme.of(context).dividerColor;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppLanguageService.text(context, 'Bahasa', 'Language'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<Locale>(
            valueListenable: AppLanguageService.localeNotifier,
            builder: (BuildContext context, Locale locale, Widget? child) {
              return DropdownButtonFormField<Locale>(
                initialValue: locale,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: AppLanguageService.text(
                    context,
                    'Bahasa aplikasi',
                    'App language',
                  ),
                ),
                items: const <DropdownMenuItem<Locale>>[
                  DropdownMenuItem<Locale>(
                    value: Locale('id'),
                    child: Text('Bahasa Indonesia'),
                  ),
                  DropdownMenuItem<Locale>(
                    value: Locale('en'),
                    child: Text('English'),
                  ),
                ],
                onChanged: (Locale? pilihan) {
                  if (pilihan != null) {
                    unawaited(AppLanguageService.setLanguage(pilihan));
                  }
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
