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
  int _selectedWeekIndex = 11;

  Future<void> reload() async {
    final Future<List<RunSession>> next = RunHistoryRepository.instance.getAll();
    if (mounted) setState(() => _sessionsFuture = next);
    try {
      await next;
    } catch (_) {
      // FutureBuilder menampilkan keadaan saat data belum dapat dibaca.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kemajuan')),
      body: FutureBuilder<List<RunSession>>(
        future: _sessionsFuture,
        builder: (BuildContext context, AsyncSnapshot<List<RunSession>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton(
                onPressed: reload,
                child: const Text('Muat ulang'),
              ),
            );
          }

          final List<RunSession> sessions = snapshot.data ?? <RunSession>[];
          final DateTime now = DateTime.now();
          final List<_WeekData> weeks = _buildWeeks(sessions, now);
          final int selectedIndex = _selectedWeekIndex
              .clamp(0, weeks.length - 1)
              .toInt();
          final _WeekData thisWeek = weeks.last;
          final Map<String, PersonalRecord> records =
              PersonalRecordsService.calculate(sessions);
          final RunSession? longest = _bestByDistance(sessions);
          final RunSession? mostClimb = _bestByAscent(sessions);
          final RunSession? highestRelativePoint = _bestByPeak(sessions);

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: <Widget>[
                _weeklyBars(weeks, selectedIndex),
                const SizedBox(height: 20),
                _sectionTitle('Minggu ini'),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _summaryMetric(
                        'Jarak',
                        '${thisWeek.distanceKm.toStringAsFixed(1)} km',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _summaryMetric(
                        'Waktu gerak',
                        _durationText(thisWeek.movingTime),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _summaryMetric(
                        'Aktivitas',
                        thisWeek.activityCount.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _sectionTitle('Rekor pribadi'),
                const SizedBox(height: 10),
                ...PersonalRecordsService.distances.map(
                  (DistanceRecordDefinition definition) => _recordTextRow(
                    definition.label,
                    records[definition.key],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionTitle('Rekor lain'),
                const SizedBox(height: 10),
                _plainRecord(
                  'Lari terjauh',
                  longest == null
                      ? '--'
                      : '${longest.distanceKm.toStringAsFixed(2)} km',
                  longest == null ? 'Belum ada data' : _dateText(longest.startedAt),
                ),
                const SizedBox(height: 8),
                _plainRecord(
                  'Kenaikan elevasi terbesar',
                  mostClimb == null
                      ? '--'
                      : '${mostClimb.elevationStats.totalAscentMeters.round()} m naik',
                  mostClimb == null
                      ? 'Belum ada data elevasi'
                      : _dateText(mostClimb.startedAt),
                ),
                const SizedBox(height: 8),
                _plainRecord(
                  'Kenaikan titik tertinggi dari awal',
                  highestRelativePoint == null
                      ? '--'
                      : '+${highestRelativePoint.elevationStats.maxAboveStartMeters.round()} m',
                  highestRelativePoint == null
                      ? 'Belum ada data elevasi'
                      : _dateText(highestRelativePoint.startedAt),
                ),
                const SizedBox(height: 16),
                Text(
                  '${sessions.length} aktivitas tersimpan.',
                  style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_WeekData> _buildWeeks(List<RunSession> sessions, DateTime now) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime monday = today.subtract(Duration(days: today.weekday - 1));
    final List<_WeekData> weeks = <_WeekData>[];

    for (int weeksAgo = 11; weeksAgo >= 0; weeksAgo--) {
      final DateTime start = monday.subtract(Duration(days: weeksAgo * 7));
      final DateTime end = start.add(const Duration(days: 7));
      final List<RunSession> aktivitasMinggu = sessions.where((RunSession session) {
        final DateTime localStart = session.startedAt.toLocal();
        return !localStart.isBefore(start) && localStart.isBefore(end);
      }).toList(growable: false);

      weeks.add(_WeekData(
        start: start,
        distanceKm: aktivitasMinggu.fold<double>(
          0,
          (double total, RunSession session) => total + session.distanceKm,
        ),
        movingTime: aktivitasMinggu.fold<Duration>(
          Duration.zero,
          (Duration total, RunSession session) => total + session.movingTime,
        ),
        activityCount: aktivitasMinggu.length,
        elevationGainMeters: aktivitasMinggu.fold<double>(
          0,
          (double total, RunSession session) =>
              total + session.elevationStats.totalAscentMeters,
        ),
      ));
    }
    return weeks;
  }

  Widget _weeklyBars(List<_WeekData> weeks, int selectedIndex) {
    final _WeekData selected = weeks[selectedIndex];
    final _WeekData? previous = selectedIndex > 0 ? weeks[selectedIndex - 1] : null;
    final double maxDistance = weeks.fold<double>(
      1,
      (double maxValue, _WeekData week) =>
          week.distanceKm > maxValue ? week.distanceKm : maxValue,
    );
    final double difference = selected.distanceKm - (previous?.distanceKm ?? 0);
    final String comparison = previous == null
        ? ''
        : previous.distanceKm <= 0
            ? (selected.distanceKm > 0
                ? 'Minggu sebelumnya: 0 km'
                : 'Sama dengan minggu sebelumnya')
            : '${difference >= 0 ? '+' : ''}${difference.toStringAsFixed(1)} km dari minggu sebelumnya';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Jarak 12 minggu terakhir',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            _dateRange(selected.start),
            style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '${selected.distanceKm.toStringAsFixed(2)} km',
                style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${selected.activityCount} aktivitas',
                  style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_durationText(selected.movingTime)} waktu gerak'
            '${selected.elevationGainMeters > 0 ? ' • ${selected.elevationGainMeters.round()} m naik' : ''}',
            style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
          ),
          if (comparison.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              comparison,
              style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 146,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(weeks.length, (int index) {
                final _WeekData week = weeks[index];
                final bool active = index == selectedIndex;
                final double fraction = week.distanceKm / maxDistance;
                final double barHeight = week.distanceKm <= 0
                    ? 3
                    : (fraction * 93).clamp(5, 93).toDouble();
                return Expanded(
                  child: Tooltip(
                    message:
                        '${_dateRange(week.start)}\n${week.distanceKm.toStringAsFixed(2)} km',
                    child: InkWell(
                      onTap: () => setState(() => _selectedWeekIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            if (week.distanceKm > 0)
                              Text(
                                week.distanceKm >= 10
                                    ? week.distanceKm.toStringAsFixed(0)
                                    : week.distanceKm.toStringAsFixed(1),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: active ? Colors.black : VoltWarna.teksAbu,
                                  fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                                ),
                              )
                            else
                              const SizedBox(height: 11),
                            const SizedBox(height: 4),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: barHeight,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: active
                                    ? Colors.black
                                    : const Color(0xFFD5D5D5),
                                border: active
                                    ? Border.all(color: Colors.black, width: 1)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${week.start.day}',
                              style: TextStyle(
                                fontSize: 9,
                                color: active ? Colors.black : VoltWarna.teksAbu,
                                fontWeight: active ? FontWeight.w800 : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ketuk batang untuk melihat rincian minggu tersebut.',
            style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      );

  Widget _summaryMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _recordTextRow(String label, PersonalRecord? record) {
    final String time = record == null
        ? '--:--'
        : '${record.estimated ? '~' : ''}${PersonalRecordsService.formatDuration(record.duration)}';
    final String? pace = record == null
        ? null
        : PersonalRecordsService.formatPace(record.paceSecondsPerKm);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: VoltWarna.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (pace != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    'Pace $pace/km',
                    style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(time, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _plainRecord(String title, String value, String date) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: VoltWarna.border),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(date, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  RunSession? _bestByDistance(List<RunSession> sessions) {
    if (sessions.isEmpty) return null;
    return sessions.reduce(
      (RunSession a, RunSession b) =>
          a.distanceMeters >= b.distanceMeters ? a : b,
    );
  }

  RunSession? _bestByAscent(List<RunSession> sessions) {
    final List<RunSession> valid = sessions
        .where((RunSession s) => s.elevationStats.hasAltitudeData)
        .toList();
    if (valid.isEmpty) return null;
    return valid.reduce((RunSession a, RunSession b) =>
        a.elevationStats.totalAscentMeters >= b.elevationStats.totalAscentMeters
            ? a
            : b);
  }

  RunSession? _bestByPeak(List<RunSession> sessions) {
    final List<RunSession> valid = sessions
        .where((RunSession s) => s.elevationStats.hasAltitudeData)
        .toList();
    if (valid.isEmpty) return null;
    return valid.reduce((RunSession a, RunSession b) =>
        a.elevationStats.maxAboveStartMeters >= b.elevationStats.maxAboveStartMeters
            ? a
            : b);
  }

  String _dateText(DateTime value) {
    final DateTime local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }

  String _dateRange(DateTime start) {
    final DateTime end = start.add(const Duration(days: 6));
    return '${start.day} ${_monthShort(start.month)}–'
        '${end.day} ${_monthShort(end.month)} ${end.year}';
  }

  String _durationText(Duration value) {
    if (value.inHours > 0) {
      return '${value.inHours}j ${value.inMinutes.remainder(60)}m';
    }
    return '${value.inMinutes}m';
  }

  String _monthShort(int month) => const <String>[
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
      ][month - 1];
}

class _WeekData {
  const _WeekData({
    required this.start,
    required this.distanceKm,
    required this.movingTime,
    required this.activityCount,
    required this.elevationGainMeters,
  });

  final DateTime start;
  final double distanceKm;
  final Duration movingTime;
  final int activityCount;
  final double elevationGainMeters;
}
