import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../running/models/run_session.dart';
import '../running/services/personal_records_service.dart';
import '../running/services/run_history_repository.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  ProgressPageState createState() => ProgressPageState();
}

class ProgressPageState extends State<ProgressPage> {
  Future<List<RunSession>> _sessionsFuture =
      RunHistoryRepository.instance.getAll();

  Future<void> reload() async {
    final Future<List<RunSession>> next = RunHistoryRepository.instance.getAll();
    if (mounted) setState(() => _sessionsFuture = next);
    try {
      await next;
    } catch (_) {
      // Error is handled by FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kemajuan')),
      body: FutureBuilder<List<RunSession>>(
        future: _sessionsFuture,
        builder: (BuildContext context, AsyncSnapshot<List<RunSession>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton(onPressed: reload, child: const Text('Muat ulang')),
            );
          }
          final List<RunSession> sessions = snapshot.data ?? <RunSession>[];
          final Map<String, PersonalRecord> records =
              PersonalRecordsService.calculate(sessions);
          final DateTime now = DateTime.now();
          final DateTime monday = DateTime(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          final List<RunSession> week = sessions
              .where((RunSession s) => !s.startedAt.isBefore(monday))
              .toList(growable: false);
          final double weekDistance = week.fold<double>(
            0,
            (double total, RunSession s) => total + s.distanceKm,
          );
          final Duration weekTime = week.fold<Duration>(
            Duration.zero,
            (Duration total, RunSession s) => total + s.movingTime,
          );
          final double weekAscent = week.fold<double>(
            0,
            (double total, RunSession s) => total + s.elevationStats.totalAscentMeters,
          );
          final RunSession? longest = _bestByDistance(sessions);
          final RunSession? highestAscent = _bestByAscent(sessions);
          final RunSession? highestPeak = _bestByPeak(sessions);

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: <Widget>[
                _hero(sessions.length),
                const SizedBox(height: 16),
                _sectionTitle('Minggu ini'),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(child: _summaryMetric('Jarak', '${weekDistance.toStringAsFixed(2)} km', Icons.route_rounded)),
                    const SizedBox(width: 10),
                    Expanded(child: _summaryMetric('Waktu', _durationText(weekTime), Icons.timer_outlined)),
                    const SizedBox(width: 10),
                    Expanded(child: _summaryMetric('Naik', '${weekAscent.round()} m', Icons.trending_up_rounded)),
                  ],
                ),
                const SizedBox(height: 22),
                _sectionTitle('Rekor pribadi'),
                const SizedBox(height: 6),
                const Text(
                  'Waktu dan pace terbaik dari sesi yang tersimpan. Tanda ~ berarti perkiraan dari pace rata-rata jika data split detail tidak tersedia.',
                  style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 12),
                ...PersonalRecordsService.distances.map((DistanceRecordDefinition definition) =>
                    _recordCard(definition.label, records[definition.key]),
                ),
                const SizedBox(height: 18),
                _sectionTitle('Rekor lainnya'),
                const SizedBox(height: 10),
                _statRecordCard(
                  icon: Icons.route_rounded,
                  title: 'Lari terjauh',
                  value: longest == null ? '--' : '${longest.distanceKm.toStringAsFixed(2)} km',
                  date: longest == null ? 'Belum ada data' : _dateText(longest.startedAt),
                ),
                const SizedBox(height: 10),
                _statRecordCard(
                  icon: Icons.trending_up_rounded,
                  title: 'Kenaikan elevasi tertinggi',
                  value: highestAscent == null ? '--' : '${highestAscent.elevationStats.totalAscentMeters.round()} m naik',
                  date: highestAscent == null ? 'Belum ada data elevasi' : _dateText(highestAscent.startedAt),
                ),
                const SizedBox(height: 10),
                _statRecordCard(
                  icon: Icons.terrain_rounded,
                  title: 'Puncak tertinggi dari titik start',
                  value: highestPeak == null ? '--' : '+${highestPeak.elevationStats.maxAboveStartMeters.round()} m',
                  date: highestPeak == null ? 'Belum ada data elevasi' : _dateText(highestPeak.startedAt),
                ),
                const SizedBox(height: 22),
                _sectionTitle('Jarak 12 minggu terakhir'),
                const SizedBox(height: 12),
                _weeklyBars(sessions, now),
                const SizedBox(height: 14),
                Text(
                  '${sessions.length} aktivitas dalam riwayat akun.',
                  style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _hero(int activities) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF16384D), Color(0xFF26324D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: VoltWarna.aksen.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('LATIHANMU, PROGRESMU', style: TextStyle(color: VoltWarna.aksen, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 8),
                const Text('Buktikan progres lewat data.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, height: 1.1)),
                const SizedBox(height: 7),
                Text('$activities aktivitas terekam', style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.emoji_events_rounded, size: 54, color: VoltWarna.aksen),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
      );

  Widget _summaryMetric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        border: Border.all(color: VoltWarna.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: VoltWarna.aksen, size: 19),
          const SizedBox(height: 10),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _recordCard(String label, PersonalRecord? record) {
    if (record == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: VoltWarna.kartu, borderRadius: BorderRadius.circular(16), border: Border.all(color: VoltWarna.border)),
        child: Row(
          children: <Widget>[
            const Icon(Icons.flag_outlined, color: VoltWarna.teksAbu),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))),
            const Text('--:--', style: TextStyle(color: VoltWarna.teksAbu, fontWeight: FontWeight.w900)),
          ],
        ),
      );
    }
    final String time = PersonalRecordsService.formatDuration(record.duration);
    final String pace = PersonalRecordsService.formatPace(record.paceSecondsPerKm);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: record.estimated ? VoltWarna.border : VoltWarna.aksen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(color: VoltWarna.surface, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.emoji_events_outlined, color: VoltWarna.aksen),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  '${record.estimated ? '~' : ''}$pace/km • ${_dateText(record.session.startedAt)}',
                  style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${record.estimated ? '~' : ''}$time',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _statRecordCard({required IconData icon, required String title, required String value, required String date}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: VoltWarna.kartu, borderRadius: BorderRadius.circular(17), border: Border.all(color: VoltWarna.border)),
      child: Row(
        children: <Widget>[
          Container(width: 42, height: 42, decoration: BoxDecoration(color: VoltWarna.surface, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: VoltWarna.aksen)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(date, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11))])),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _weeklyBars(List<RunSession> sessions, DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final List<double> totals = <double>[];
    final List<String> labels = <String>[];
    for (int weeksAgo = 11; weeksAgo >= 0; weeksAgo--) {
      final DateTime weekEnd = today.subtract(Duration(days: today.weekday - 1 + weeksAgo * 7));
      final DateTime start = weekEnd;
      final DateTime end = start.add(const Duration(days: 7));
      final double total = sessions
          .where((RunSession s) => !s.startedAt.isBefore(start) && s.startedAt.isBefore(end))
          .fold<double>(0, (double sum, RunSession s) => sum + s.distanceKm);
      totals.add(total);
      labels.add(_monthShort(start.month));
    }
    final double maxValue = totals.fold<double>(1, (double value, double item) => item > value ? item : value);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      decoration: BoxDecoration(color: VoltWarna.kartu, borderRadius: BorderRadius.circular(18), border: Border.all(color: VoltWarna.border)),
      child: SizedBox(
        height: 145,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List<Widget>.generate(totals.length, (int index) {
            final double ratio = totals[index] / maxValue;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    Text(totals[index] == 0 ? '' : totals[index].toStringAsFixed(0), style: const TextStyle(fontSize: 9, color: VoltWarna.teksAbu)),
                    const SizedBox(height: 4),
                    Container(
                      height: 86 * ratio.clamp(0.04, 1).toDouble(),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        gradient: const LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: <Color>[VoltWarna.aksenGelap, VoltWarna.aksen]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[index], style: const TextStyle(fontSize: 8, color: VoltWarna.teksAbu)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  RunSession? _bestByDistance(List<RunSession> sessions) {
    if (sessions.isEmpty) return null;
    return sessions.reduce((RunSession a, RunSession b) => a.distanceMeters >= b.distanceMeters ? a : b);
  }

  RunSession? _bestByAscent(List<RunSession> sessions) {
    final List<RunSession> valid = sessions.where((RunSession s) => s.elevationStats.hasAltitudeData).toList();
    if (valid.isEmpty) return null;
    return valid.reduce((RunSession a, RunSession b) => a.elevationStats.totalAscentMeters >= b.elevationStats.totalAscentMeters ? a : b);
  }

  RunSession? _bestByPeak(List<RunSession> sessions) {
    final List<RunSession> valid = sessions.where((RunSession s) => s.elevationStats.hasAltitudeData).toList();
    if (valid.isEmpty) return null;
    return valid.reduce((RunSession a, RunSession b) => a.elevationStats.maxAboveStartMeters >= b.elevationStats.maxAboveStartMeters ? a : b);
  }

  String _dateText(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} • '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _durationText(Duration value) {
    if (value.inHours > 0) return '${value.inHours}j ${value.inMinutes.remainder(60)}m';
    return '${value.inMinutes}m';
  }

  String _monthShort(int month) => const <String>['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'][month - 1];
}
