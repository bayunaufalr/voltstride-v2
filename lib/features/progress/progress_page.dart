import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  _WeekChartMetric _chartMetric = _WeekChartMetric.distance;

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

          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: <Widget>[
                _weeklyBars(weeks, selectedIndex),
                const SizedBox(height: 16),
                _predictionSection(sessions),
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
                _sectionTitle('Pencapaian'),
                const SizedBox(height: 10),
                ...PersonalRecordsService.distances.map(
                  (DistanceRecordDefinition definition) => _recordTextRow(
                    definition,
                    records[definition.key],
                    sessions,
                  ),
                ),
                const SizedBox(height: 16),
                _sectionTitle('Pencapaian lain'),
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
                  'Elevasi total terbesar',
                  mostClimb == null
                      ? '--'
                      : '+${mostClimb.elevationStats.totalAscentMeters.round()} m',
                  mostClimb == null
                      ? 'Belum ada data elevasi'
                      : _dateText(mostClimb.startedAt),
                ),

                const SizedBox(height: 16),
                Text(
                  '${sessions.length} aktivitas tersimpan.',
                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
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
    final _WeekData? previous =
        selectedIndex > 0 ? weeks[selectedIndex - 1] : null;
    final double maxValue = weeks.fold<double>(
      1,
      (double currentMax, _WeekData week) =>
          _angkaGrafik(week, _chartMetric) > currentMax
              ? _angkaGrafik(week, _chartMetric)
              : currentMax,
    );
    final double currentValue = _angkaGrafik(selected, _chartMetric);
    final double previousValue =
        previous == null ? 0 : _angkaGrafik(previous, _chartMetric);
    final double difference = currentValue - previousValue;
    final String comparison = previous == null
        ? ''
        : '${_formatSelisih(difference, _chartMetric)} dibanding minggu sebelumnya';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '12 minggu terakhir',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _pilihanGrafik('Jarak', _WeekChartMetric.distance),
              _pilihanGrafik('Elevasi', _WeekChartMetric.elevation),
              _pilihanGrafik('Waktu', _WeekChartMetric.time),
              _pilihanGrafik('Aktivitas', _WeekChartMetric.activities),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _dateRange(selected.start),
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatAngkaGrafik(currentValue, _chartMetric),
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
          ),
          if (_chartMetric == _WeekChartMetric.distance ||
              _chartMetric == _WeekChartMetric.elevation)
            Text(
              '${selected.activityCount} aktivitas · ${_durationText(selected.movingTime)} waktu gerak',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
            ),
          if (comparison.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              comparison,
              style: TextStyle(
                color: difference > 0
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).hintColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(weeks.length, (int index) {
                final _WeekData week = weeks[index];
                final bool active = index == selectedIndex;
                final double amount = _angkaGrafik(week, _chartMetric);
                final double fraction = amount / maxValue;
                final double barHeight =
                    amount <= 0 ? 3 : (fraction * 96).clamp(5, 96).toDouble();
                return Expanded(
                  child: Tooltip(
                    message:
                        '${_dateRange(week.start)}\n${_formatAngkaGrafik(amount, _chartMetric)}',
                    child: InkWell(
                      onTap: () => setState(() => _selectedWeekIndex = index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            if (amount > 0)
                              Text(
                                _angkaRingkas(amount, _chartMetric),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 8,
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w400,
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
                                    ? Theme.of(context).colorScheme.onSurface
                                    : Theme.of(context).dividerColor,
                                border: active
                                    ? Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${week.start.day}',
                              style: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context).hintColor,
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w400,
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
          Text(
            'Pilih batang untuk melihat nilai tiap minggu.',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _pilihanGrafik(String label, _WeekChartMetric metric) {
    return ChoiceChip(
      label: Text(label),
      selected: _chartMetric == metric,
      onSelected: (bool dipilih) {
        if (!dipilih) return;
        setState(() => _chartMetric = metric);
      },
      selectedColor: Theme.of(context).colorScheme.onSurface,
      labelStyle: TextStyle(
        color: _chartMetric == metric
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.onSurface,
        fontSize: 12,
      ),
      side: BorderSide(color: Theme.of(context).dividerColor),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    );
  }

  double _angkaGrafik(_WeekData week, _WeekChartMetric metric) {
    switch (metric) {
      case _WeekChartMetric.distance:
        return week.distanceKm;
      case _WeekChartMetric.elevation:
        return week.elevationGainMeters;
      case _WeekChartMetric.time:
        return week.movingTime.inMinutes.toDouble();
      case _WeekChartMetric.activities:
        return week.activityCount.toDouble();
    }
  }

  String _formatSelisih(double value, _WeekChartMetric metric) {
    final String tanda = value >= 0 ? '+' : '';
    switch (metric) {
      case _WeekChartMetric.distance:
        return '$tanda${value.toStringAsFixed(1)} km';
      case _WeekChartMetric.elevation:
        return 'Elevasi $tanda${value.round()} m';
      case _WeekChartMetric.time:
        final int menit = value.round();
        return '$tanda${_durationText(Duration(minutes: menit))}';
      case _WeekChartMetric.activities:
        return '$tanda${value.round()} aktivitas';
    }
  }

  String _formatAngkaGrafik(double value, _WeekChartMetric metric) {
    switch (metric) {
      case _WeekChartMetric.distance:
        return '${value.toStringAsFixed(1)} km';
      case _WeekChartMetric.elevation:
        return 'Elevasi +${value.round()} m';
      case _WeekChartMetric.time:
        return _durationText(Duration(minutes: value.round()));
      case _WeekChartMetric.activities:
        return '${value.round()} aktivitas';
    }
  }

  String _angkaRingkas(double value, _WeekChartMetric metric) {
    switch (metric) {
      case _WeekChartMetric.distance:
        return value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
      case _WeekChartMetric.elevation:
        return value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.round().toString();
      case _WeekChartMetric.time:
        return value >= 60 ? '${(value / 60).toStringAsFixed(0)}j' : value.round().toString();
      case _WeekChartMetric.activities:
        return value.round().toString();
    }
  }

  Widget _predictionSection(List<RunSession> sessions) {
    final List<_RacePrediction> predictions = _buatPrediksi(sessions);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Prediksi waktu lomba',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final _RacePrediction prediction in predictions) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    prediction.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  prediction.seconds == null
                      ? 'Belum cukup data'
                      : '~${_formatRaceTime(prediction.seconds!)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (prediction.sourceDistanceKm != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 7),
                child: Text(
                  'Perkiraan dari lari ${prediction.sourceDistanceKm!.toStringAsFixed(1)} km',
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 10,
                  ),
                ),
              )
            else
              const SizedBox(height: 7),
            if (prediction != predictions.last)
              Divider(color: Theme.of(context).dividerColor, height: 1),
          ],
        ],
      ),
    );
  }

  List<_RacePrediction> _buatPrediksi(List<RunSession> sessions) {
    final DateTime batasBaru = DateTime.now().subtract(
      const Duration(days: 180),
    );
    final List<RunSession> semuaLari = sessions
        .where((RunSession s) =>
            s.activityType == RunActivityType.run &&
            s.distanceKm >= 3 &&
            (s.movingTime > Duration.zero || s.elapsed > Duration.zero))
        .toList(growable: false);
    final List<RunSession> latihanTerbaru = semuaLari
        .where((RunSession s) => !s.startedAt.isBefore(batasBaru))
        .toList(growable: false);
    final List<RunSession> sumber =
        latihanTerbaru.isNotEmpty ? latihanTerbaru : semuaLari;

    const List<({String label, double km, double minimalKm})> target =
        <({String label, double km, double minimalKm})>[
      (label: '5 km', km: 5, minimalKm: 3),
      (label: '10 km', km: 10, minimalKm: 5),
      (label: 'Half marathon', km: 21.0975, minimalKm: 10),
      (label: 'Full marathon', km: 42.195, minimalKm: 15),
    ];

    return target.map((item) {
      RunSession? sumberTerbaik;
      double? waktuTerbaik;
      for (final RunSession session in sumber) {
        if (session.distanceKm < item.minimalKm) continue;
        final Duration durasi = session.movingTime > Duration.zero
            ? session.movingTime
            : session.elapsed;
        final double prediksi = (durasi.inSeconds *
                math.pow(item.km / session.distanceKm, 1.06))
            .toDouble();
        if (!prediksi.isFinite || prediksi <= 0) continue;
        if (waktuTerbaik == null || prediksi < waktuTerbaik) {
          waktuTerbaik = prediksi;
          sumberTerbaik = session;
        }
      }
      return _RacePrediction(
        label: item.label,
        seconds: waktuTerbaik?.round(),
        sourceDistanceKm: sumberTerbaik?.distanceKm,
      );
    }).toList(growable: false);
  }

  String _formatRaceTime(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    final int remainder = seconds % 60;
    if (hours > 0) {
      return '${hours}j ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes}m ${remainder.toString().padLeft(2, '0')}d';
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      );

  Widget _summaryMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
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
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _recordTextRow(
    DistanceRecordDefinition definition,
    PersonalRecord? record,
    List<RunSession> sessions,
  ) {
    final PersonalRecord? previous = record == null
        ? null
        : PersonalRecordsService.previousBestBefore(
            sessions: sessions,
            definition: definition,
            currentRecord: record,
          );
    final String time = record == null
        ? '--:--'
        : '${record.estimated ? '~' : ''}'
            '${PersonalRecordsService.formatDuration(record.duration)}';
    final String? pace = record == null
        ? null
        : PersonalRecordsService.formatPace(record.paceSecondsPerKm);

    String? perubahan;
    if (record != null && previous != null) {
      final double deltaPace =
          previous.paceSecondsPerKm - record.paceSecondsPerKm;
      final double deltaPersen = previous.duration.inMilliseconds > 0
          ? (previous.duration.inMilliseconds - record.duration.inMilliseconds) /
              previous.duration.inMilliseconds *
              100
          : 0;
      if (deltaPace > 0) {
        perubahan = 'Δ −${PersonalRecordsService.formatPace(deltaPace)}/km'
            ' · ${deltaPersen.toStringAsFixed(1)}% lebih cepat';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  definition.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (pace != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    'Pace $pace/km',
                    style: TextStyle(
                      color: Theme.of(context).hintColor,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (perubahan != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    perubahan,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(time, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (record != null)
                Text(
                  _dateText(record.session.startedAt),
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _plainRecord(String title, String value, String date) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(date, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
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
    final List<RunSession> lari = sessions
        .where((RunSession sesi) => sesi.activityType == RunActivityType.run)
        .toList(growable: false);
    if (lari.isEmpty) return null;
    return lari.reduce(
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

enum _WeekChartMetric { distance, elevation, time, activities }

class _RacePrediction {
  const _RacePrediction({
    required this.label,
    required this.seconds,
    required this.sourceDistanceKm,
  });

  final String label;
  final int? seconds;
  final double? sourceDistanceKm;
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
