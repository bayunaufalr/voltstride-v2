import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';

class MorePage extends StatefulWidget {
  const MorePage({
    super.key,
    required this.onOpenTimer,
    required this.onOpenCoach,
    required this.onOpenStrength,
  });

  final VoidCallback onOpenTimer;
  final VoidCallback onOpenCoach;
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
          _menuItem('Coach', widget.onOpenCoach),
          _menuItem(
            _text('Latihan kekuatan', 'Strength training'),
            widget.onOpenStrength,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(String title, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onTap: onTap,
      ),
    );
  }
}
