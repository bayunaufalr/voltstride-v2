import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'services/run_history_repository.dart';

/// Riwayat sesi yang disimpan lokal pada perangkat.
class RunHistoryPage extends StatefulWidget {
  const RunHistoryPage({super.key});

  @override
  RunHistoryPageState createState() => RunHistoryPageState();
}

class RunHistoryPageState extends State<RunHistoryPage> {
  final RunHistoryRepository _repository = RunHistoryRepository.instance;
  late Future<List<RunSession>> _sessionsFuture;

  @override
  void initState() {
    super.initState();
    _sessionsFuture = _repository.getAll();
  }

  Future<void> reload() async {
    final Future<List<RunSession>> future = _repository.getAll();
    if (mounted) setState(() => _sessionsFuture = future);
    try {
      await future;
    } catch (_) {
      // FutureBuilder reads the failed future and displays its error state.
      // Catch here as refresh callbacks shouldn't leak an unhandled error.
    }
  }

  Future<void> _deleteSession(RunSession session) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Hapus riwayat lari?'),
          content: Text(
            'Sesi ${session.distanceText} km akan dihapus dari perangkat ini.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _repository.delete(session.startedAt);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Lari'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<RunSession>>(
          future: _sessionsFuture,
          builder: (
            BuildContext context,
            AsyncSnapshot<List<RunSession>> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _messageState(
                icon: Icons.storage_outlined,
                title: 'Riwayat tidak dapat dibuka',
                message: 'Penyimpanan lokal mengalami masalah.',
                action: FilledButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi'),
                ),
              );
            }

            final List<RunSession> sessions =
                snapshot.data ?? const <RunSession>[];
            if (sessions.isEmpty) {
              return _messageState(
                icon: Icons.directions_run,
                title: 'Belum ada riwayat',
                message:
                    'Selesaikan satu sesi lari. Hasilnya akan otomatis disimpan di perangkat ini.',
              );
            }

            return RefreshIndicator(
              onRefresh: reload,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                itemCount: sessions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (BuildContext context, int index) {
                  final RunSession session = sessions[index];
                  return _sessionCard(session);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _sessionCard(RunSession session) {
    final DateTime localStart = session.startedAt.toLocal();
    final String dateText =
        '${_twoDigits(localStart.day)}/${_twoDigits(localStart.month)}/${localStart.year} '
        '${_twoDigits(localStart.hour)}:${_twoDigits(localStart.minute)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const CircleAvatar(
          backgroundColor: VoltWarna.aksen,
          foregroundColor: VoltWarna.latar,
          child: Icon(Icons.directions_run),
        ),
        title: Text(
          '${session.distanceText} km',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '$dateText\n${session.elapsedText}  •  ${session.averagePaceText}/km',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Divider(),
          Row(
            children: <Widget>[
              Expanded(
                child: _smallMetric('Moving time', session.movingTimeText),
              ),
              Expanded(
                child: _smallMetric('Akurasi GPS', session.gpsAccuracyText),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'SPLIT PER KM',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          if (session.splits.isEmpty)
            const Text(
              'Belum mencapai satu kilometer penuh.',
              style: TextStyle(color: VoltWarna.teksAbu),
            )
          else
            ...session.splits.map(
              (RunSplit split) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 64, child: Text('KM ${split.kilometer}')),
                    Expanded(child: Text('${split.durationSeconds} detik')),
                    Text(
                      split.paceText,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _deleteSession(session),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Hapus sesi'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: VoltWarna.teksAbu,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 58, color: VoltWarna.aksen),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: VoltWarna.teksAbu),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 18),
              action,
            ],
          ],
        ),
      ),
    );
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
