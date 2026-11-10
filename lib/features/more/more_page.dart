import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';

class MorePage extends StatelessWidget {
  const MorePage({
    super.key,
    required this.onOpenTimer,
  });

  final VoidCallback onOpenTimer;

  String _text(BuildContext context, String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_text(context, 'Lainnya', 'More'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _menuItem(
            context,
            _text(context, 'Timer latihan', 'Workout timer'),
            onOpenTimer,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(BuildContext context, String title, VoidCallback onTap) {
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
