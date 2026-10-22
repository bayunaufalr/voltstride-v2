import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
import '../ai_coach/training_data_export_service.dart';

class MorePage extends StatefulWidget {
  const MorePage({
    super.key,
    required this.onOpenTimer,
    required this.onOpenStrength,
  });

  final VoidCallback onOpenTimer;
  final VoidCallback onOpenStrength;

  @override
  MorePageState createState() => MorePageState();
}

class MorePageState extends State<MorePage> {
  Future<void> reload() async {}

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_text('Lainnya', 'More'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _menuItem(
            _text('Timer latihan', 'Workout timer'),
            widget.onOpenTimer,
          ),
          _menuItem(
            _text('Latihan kekuatan', 'Strength training'),
            widget.onOpenStrength,
          ),
          _menuItem(
            _text('Ekspor data latihan untuk AI', 'Export training data for AI'),
            _exportTrainingData,
            subtitle: _text(
              'Bagikan satu file JSON ke ChatGPT atau layanan AI lain.',
              'Share one JSON file with ChatGPT or another AI service.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTrainingData() async {
    try {
      final int count = await TrainingDataExportService.shareAllSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Ekspor berisi $count sesi latihan. Pilih aplikasi AI dari menu berbagi.',
            'Export contains $count training sessions. Choose an AI app from the share menu.',
          )),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Ekspor data gagal: $error',
            'Training data export failed: $error',
          )),
        ),
      );
    }
  }

  Widget _menuItem(String title, VoidCallback onTap, {String? subtitle}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
