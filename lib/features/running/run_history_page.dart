import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'services/run_history_repository.dart';
import 'run_detail_page.dart';
import 'run_route_map_view.dart';

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

  Future<void> _exportBackup() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Ekspor cadangan riwayat?'),
          content: const Text(
            'Cadangan dapat berisi titik koordinat GPS rute lari. Simpan file '
            'di tempat pribadi dan jangan unggah secara publik.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Lanjutkan'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      final String contents = await _repository.exportBackupJson();
      final DateTime now = DateTime.now();
      final String stamp =
          '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}_'
          '${_twoDigits(now.hour)}${_twoDigits(now.minute)}';
      final Uri? savedUri = await FilePicker.saveFile(
        dialogTitle: 'Simpan cadangan riwayat VoltStride',
        fileName: 'VoltStride_Riwayat_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
      );
      if (!mounted) return;
      _showSnackBar(
        savedUri == null
            ? 'Ekspor dibatalkan.'
            : 'Cadangan riwayat berhasil dibuat. Simpan file di tempat aman.',
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Gagal membuat cadangan. Coba lagi. ($error)');
    }
  }

  Future<void> _importBackup() async {
    try {
      final PlatformFile? selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
      if (selected == null || !mounted) return;

      final Uint8List bytes = await selected.readAsBytes();
      final String contents = utf8.decode(bytes);

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Pulihkan riwayat?'),
            content: const Text(
              'Data dari cadangan akan digabung dengan riwayat yang ada. '
              'Riwayat lain tidak dihapus. Jika waktu mulai sesi sama, '
              'data sesi dari cadangan akan menggantikan sesi tersebut.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Pulihkan'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      final int importedCount = await _repository.importBackupJson(contents);
      await reload();
      if (!mounted) return;
      _showSnackBar('$importedCount sesi berhasil dipulihkan atau digabungkan.');
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Cadangan gagal dipulihkan. Pastikan file VoltStride valid. ($error)');
    }
  }

  Future<void> _showStorageDiagnostics() async {
    try {
      final Map<String, Object?> info = await _repository.diagnostics();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Info penyimpanan'),
            content: SingleChildScrollView(
              child: SelectableText(
                'Jumlah sesi: ${info['sessionCount']}\n'
                'File database ada: ${info['fileExists']}\n'
                'Ukuran file: ${info['fileSizeBytes']} byte\n'
                'Pemeriksaan SQLite: ${info['integrity']}\n'
                'Versi SQLite: ${info['sqliteVersion']}\n\n'
                'Lokasi database:\n${info['databasePath']}',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Gagal membaca info penyimpanan. ($error)');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _deleteSession(RunSession session) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Hapus aktivitas?'),
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
        title: const Text('Riwayat aktivitas'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            tooltip: 'Cadangan dan diagnostik',
            onSelected: (String value) {
              switch (value) {
                case 'export':
                  unawaited(_exportBackup());
                  break;
                case 'import':
                  unawaited(_importBackup());
                  break;
                case 'diagnostics':
                  unawaited(_showStorageDiagnostics());
                  break;
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Ekspor cadangan'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Pulihkan cadangan'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'diagnostics',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storage_outlined),
                  title: Text('Info penyimpanan'),
                ),
              ),
            ],
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
                    'Selesaikan satu aktivitas. Hasilnya akan otomatis disimpan di perangkat ini.',
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
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => RunDetailPage(session: session),
            ),
          );
          await reload();
        },
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundColor: VoltWarna.surface,
                    foregroundColor: VoltWarna.aksen,
                    child: Icon(session.activityType == RunActivityType.walk
                        ? Icons.directions_walk_rounded
                        : Icons.directions_run_rounded),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${session.displayLabel} • ${session.distanceText} km',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        Text(dateText, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hapus sesi',
                    onPressed: () => _deleteSession(session),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (session.route.length > 1) ...<Widget>[
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: RunRouteMapView(
                    key: ValueKey<String>('history-${session.startedAt.toIso8601String()}'),
                    route: session.route,
                    laps: const <RunLap100m>[],
                    height: 145,
                  ),
                ),
              ],
              const SizedBox(height: 11),
              Row(
                children: <Widget>[
                  _compactMetric('Waktu', session.elapsedText),
                  _compactMetric('Pace', '${session.averagePaceText}/km'),
                  _compactMetric('Lokasi', session.environment.label),
                ],
              ),
              const SizedBox(height: 6),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('Lihat detail →', style: TextStyle(color: VoltWarna.aksen, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: VoltWarna.teksAbu)),
        ],
      ),
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
