import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';

class MorePage extends StatefulWidget {
  const MorePage({
    super.key,
    required this.onOpenTimer,
    required this.onOpenCoach,
    required this.onOpenStrength,
    required this.onOpenRoutePlanner,
  });

  final VoidCallback onOpenTimer;
  final VoidCallback onOpenCoach;
  final VoidCallback onOpenStrength;
  final VoidCallback onOpenRoutePlanner;

  @override
  MorePageState createState() => MorePageState();
}

class MorePageState extends State<MorePage> {
  Future<void> reload() async {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lainnya')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _menuItem('Rencanakan rute', widget.onOpenRoutePlanner),
          _menuItem('Timer latihan', widget.onOpenTimer),
          _menuItem('Coach', widget.onOpenCoach),
          _menuItem('Latihan kekuatan', widget.onOpenStrength),
        ],
      ),
    );
  }

  Widget _menuItem(String judul, VoidCallback saatDibuka) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: VoltWarna.border),
      ),
      child: ListTile(
        title: Text(judul, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right, color: Colors.black),
        onTap: saatDibuka,
      ),
    );
  }
}
