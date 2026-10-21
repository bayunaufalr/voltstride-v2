import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
import 'models/run_session.dart';
import 'services/run_history_repository.dart';
import 'run_detail_page.dart';
import 'run_route_map_view.dart';

/// Riwayat sesi yang disimpan lokal pada perangkat.
class RunHistoryPage extends StatefulWidget {
  const RunHistoryPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  RunHistoryPageState createState() => RunHistoryPageState();
}

class RunHistoryPageState extends State<RunHistoryPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);
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
          title: Text(_text('Ekspor cadangan riwayat?', 'Export activity backup?')),
          content: Text(_text('Cadangan dapat berisi titik koordinat GPS rute lari. Simpan file di tempat pribadi dan jangan unggah secara publik.', 'The backup may include GPS coordinates from your routes. Keep it private and do not upload it publicly.')),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_text('Batal', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_text('Lanjutkan', 'Continue')),
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
        dialogTitle: _text('Simpan cadangan riwayat VoltStride', 'Save VoltStride activity backup'),
        fileName: 'VoltStride_Activities_$stamp.json',
        bytes: Uint8List.fromList(utf8.encode(contents)),
        mimeType: 'application/json',
      );
      if (!mounted) return;
      _showSnackBar(
        savedUri == null
            ? _text('Ekspor dibatalkan.', 'Export cancelled.')
            : _text('Cadangan riwayat berhasil dibuat. Simpan file di tempat aman.', 'Activity backup created. Store the file somewhere safe.'),
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_text('Gagal membuat cadangan. Coba lagi.', 'Could not create the backup. Please try again.')); 
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
      if (!mounted) return;
      final String contents = utf8.decode(bytes);

      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: Text(_text('Pulihkan riwayat?', 'Restore activity history?')),
            content: Text(_text('Data dari cadangan akan digabung dengan riwayat yang ada. Riwayat lain tidak dihapus. Jika waktu mulai sesi sama, data sesi dari cadangan akan menggantikan sesi tersebut.', 'Backup data will be merged with your current history. Other sessions will not be deleted. If a session has the same start time, the backup version will replace it.')),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_text('Batal', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(_text('Pulihkan', 'Restore')),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;

      final int importedCount = await _repository.importBackupJson(contents);
      await reload();
      if (!mounted) return;
      _showSnackBar(_text('$importedCount sesi berhasil dipulihkan atau digabungkan.', '$importedCount sessions restored or merged.'));
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_text('Cadangan gagal dipulihkan. Pastikan file VoltStride valid.', 'Could not restore the backup. Make sure the file is a valid VoltStride backup.'));
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
            title: Text(_text('Info penyimpanan', 'Storage diagnostics')),
            content: SingleChildScrollView(
              child: SelectableText(
                '${_text('Jumlah sesi', 'Session count')}: ${info['sessionCount']}\n'
                '${_text('File database ada', 'Database file exists')}: ${info['fileExists']}\n'
                '${_text('Ukuran file', 'File size')}: ${info['fileSizeBytes']} ${_text('byte', 'bytes')}\n'
                'SQLite ${_text('Pemeriksaan', 'integrity check')}: ${info['integrity']}\n'
'SQLite ${_text('Versi', 'version')}: ${info['sqliteVersion']}\n\n'
                '${_text('Lokasi database', 'Database location')}:\n${info['databasePath']}',
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(_text('Tutup', 'Close')),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      _showSnackBar(_text('Gagal membaca info penyimpanan.', 'Could not read storage diagnostics.'));
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
          title: Text(_text('Hapus aktivitas?', 'Delete activity?')),
          content: Text(
            _text('Sesi ${session.distanceText} km akan dihapus dari akun dan perangkat ini.', 'The ${session.distanceText} km session will be deleted from this account and device.'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_text('Batal', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_text('Hapus', 'Delete')),
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
    if (widget.embedded) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Row(
              children: <Widget>[
                const Spacer(),
                IconButton(
                  tooltip: _text('Muat ulang', 'Refresh'),
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                ),
                _backupMenu(),
              ],
            ),
          ),
          Expanded(child: _historyContent()),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('Riwayat aktivitas', 'Activity history')),
        actions: <Widget>[
          IconButton(
            tooltip: _text('Muat ulang', 'Refresh'),
            onPressed: reload,
            icon: const Icon(Icons.refresh),
          ),
          _backupMenu(),
        ],
      ),
      body: SafeArea(child: _historyContent()),
    );
  }

  PopupMenuButton<String> _backupMenu() {
    return PopupMenuButton<String>(
      tooltip: _text('Cadangan dan diagnostik', 'Backup and diagnostics'),
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
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'export',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.download_outlined),
            title: Text(_text('Ekspor cadangan', 'Export backup')),
          ),
        ),
        PopupMenuItem<String>(
          value: 'import',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.upload_file_outlined),
            title: Text(_text('Pulihkan cadangan', 'Restore backup')),
          ),
        ),
        PopupMenuItem<String>(
          value: 'diagnostics',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.storage_outlined),
            title: Text(_text('Info penyimpanan', 'Storage diagnostics')),
          ),
        ),
      ],
    );
  }

  Widget _historyContent() {
    return FutureBuilder<List<RunSession>>(
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
            title: _text('Riwayat tidak dapat dibuka', 'Activity history is unavailable'),
            message: _text('Penyimpanan lokal mengalami masalah.', 'Local storage reported a problem.'),
            action: FilledButton.icon(
              onPressed: reload,
              icon: const Icon(Icons.refresh),
              label: Text(_text('Coba lagi', 'Try again')),
            ),
          );
        }

        final List<RunSession> sessions =
            snapshot.data ?? const <RunSession>[];
        if (sessions.isEmpty) {
          return _messageState(
            icon: Icons.history_rounded,
            title: _text('Belum ada riwayat', 'No activity history yet'),
            message:
                _text('Selesaikan satu aktivitas. Hasilnya akan disimpan ke akun dan salinan perangkat ini.', 'Complete an activity to save it to your account and this device.'),
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
              return _sessionCard(sessions[index]);
            },
          ),
        );
      },
    );
  }

  String _activityLabel(RunSession session) {
    if (session.activityType == RunActivityType.walk) return _text('Berjalan', 'Walk');
    if (session.intervalPlan != null) return _text('Lari interval', 'Interval run');
    return _text('Lari', 'Run');
  }

  String _environmentLabel(RunSession session) =>
      session.environment == RunEnvironment.outdoor
          ? _text('Luar ruangan', 'Outdoor')
          : _text('Dalam ruangan', 'Indoor');

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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${_activityLabel(session)} • ${session.distanceText} km',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        Text(dateText, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _text('Hapus sesi', 'Delete session'),
                    onPressed: () => _deleteSession(session),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              if (session.route.length > 1) ...<Widget>[
                const SizedBox(height: 11),
                ClipRRect(
                  borderRadius: BorderRadius.zero,
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
                  _compactMetric(_text('Waktu', 'Time'), session.elapsedText),
                  _compactMetric('Pace', '${session.averagePaceText}/km'),
                  _compactMetric(_text('Lokasi', 'Location'), _environmentLabel(session)),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(_text('Lihat detail →', 'View details →'), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w800)),
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
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
            Icon(icon, size: 58, color: Theme.of(context).colorScheme.primary),
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
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
