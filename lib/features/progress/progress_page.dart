// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
import '../account/account_service.dart';
import '../running/models/run_session.dart';
import '../running/services/personal_records_service.dart';
import '../running/services/run_history_repository.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key, this.embedded = false, this.belowWeeklyChart});

  // true: tampilkan isi kemajuan di dalam halaman Anda tanpa Scaffold/halaman baru.
  final bool embedded;
  final Widget? belowWeeklyChart;

  @override
  ProgressPageState createState() => ProgressPageState();
}

class ProgressPageState extends State<ProgressPage> {
  Future<List<RunSession>> _sessionsFuture =
      RunHistoryRepository.instance.getAll();
  int _selectedWeekIndex = 11;
  _WeekChartMetric _chartMetric = _WeekChartMetric.distance;
  @override
  void initState() {
    super.initState();
  }

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

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
    final Widget isiKemajuan = FutureBuilder<List<RunSession>>(
      future: _sessionsFuture,
      builder: (BuildContext context, AsyncSnapshot<List<RunSession>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: FilledButton(
                onPressed: reload,
                child: Text(AppLanguageService.text(context, 'Muat ulang', 'Reload')),
              ),
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

        final List<Widget> bagianKemajuan = <Widget>[
          _weeklyBars(weeks, selectedIndex),
          if (widget.belowWeeklyChart != null) ...<Widget>[
            const SizedBox(height: 12),
            widget.belowWeeklyChart!,
          ],
          const SizedBox(height: 16),
          _vo2MaxCard(sessions),
          const SizedBox(height: 16),
          _predictionSection(sessions),
          const SizedBox(height: 20),
          _sectionTitle(AppLanguageService.text(context, 'Aktivitas minggu ini', 'Activity this week')),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _summaryMetric(
                  AppLanguageService.text(context, 'Jarak', 'Distance'),
                  '${thisWeek.distanceKm.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryMetric(
                  AppLanguageService.text(context, 'Waktu gerak', 'Moving time'),
                  _durationText(thisWeek.movingTime),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryMetric(
                  AppLanguageService.text(context, 'Aktivitas', 'Activities'),
                  thisWeek.activityCount.toString(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _sectionTitle(AppLanguageService.text(context, 'Pencapaian', 'Personal records')),
          const SizedBox(height: 10),
          ...PersonalRecordsService.distances.map(
            (DistanceRecordDefinition definition) => _recordTextRow(
              definition,
              records[definition.key],
              sessions,
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(AppLanguageService.text(context, 'Pencapaian lain', 'Other milestones')),
          const SizedBox(height: 10),
          _plainRecord(
            AppLanguageService.text(context, 'Lari terjauh', 'Longest activity'),
            longest == null
                ? '--'
                : '${longest.distanceKm.toStringAsFixed(2)} km',
            longest == null ? AppLanguageService.text(context, 'Belum ada data', 'No data yet') : _dateText(longest.startedAt),
          ),
          const SizedBox(height: 8),
          _plainRecord(
            AppLanguageService.text(context, 'Elevasi total terbesar', 'Greatest elevation gain'),
            mostClimb == null
                ? '--'
                : '+${mostClimb.elevationStats.totalAscentMeters.round()} m',
            mostClimb == null
                ? AppLanguageService.text(context, 'Belum ada data elevasi', 'No elevation data')
                : _dateText(mostClimb.startedAt),
          ),
          const SizedBox(height: 16),
          Text(
            AppLanguageService.text(context, '${sessions.length} aktivitas tersimpan.', '${sessions.length} activities saved.'),
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 12,
            ),
          ),
        ];

        // Di tab Anda, seluruh bagian ditampilkan langsung dalam satu guliran.
        // Halaman kemajuan mandiri tetap bisa menggunakan tarik-untuk-muat-ulang.
        if (widget.embedded) {
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: bagianKemajuan,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: bagianKemajuan,
          ),
        );
      },
    );

    if (widget.embedded) return isiKemajuan;

    return Scaffold(
      appBar: AppBar(title: Text(_text('Kemajuan', 'Progress'))),
      body: isiKemajuan,
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
        : '${_formatSelisih(difference, _chartMetric)} ${_text('dibanding minggu sebelumnya', 'vs previous week')}';

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AppLanguageService.text(context, '12 minggu terakhir', 'Last 12 weeks'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              _pilihanGrafik(_text('Jarak', 'Distance'), _WeekChartMetric.distance),
              _pilihanGrafik(_text('Elevasi', 'Elevation'), _WeekChartMetric.elevation),
              _pilihanGrafik(_text('Waktu', 'Time'), _WeekChartMetric.time),
              _pilihanGrafik(_text('Aktivitas', 'Activities'), _WeekChartMetric.activities),
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
              '${selected.activityCount} ${_text('aktivitas', 'activities')} · ${_durationText(selected.movingTime)} ${_text('waktu gerak', 'moving time')}',
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
            AppLanguageService.text(context, 'Pilih batang untuk melihat nilai tiap minggu.', 'Select a bar to view that week’s value.'),
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
        return '${_text('Elevasi', 'Elevation')} $tanda${value.round()} m';
      case _WeekChartMetric.time:
        final int menit = value.round();
        return '$tanda${_durationText(Duration(minutes: menit))}';
      case _WeekChartMetric.activities:
        return '$tanda${value.round()} ${_text('aktivitas', 'activities')}';
    }
  }

  String _formatAngkaGrafik(double value, _WeekChartMetric metric) {
    switch (metric) {
      case _WeekChartMetric.distance:
        return '${value.toStringAsFixed(1)} km';
      case _WeekChartMetric.elevation:
        return '${_text('Elevasi', 'Elevation')} +${value.round()} m';
      case _WeekChartMetric.time:
        return _durationText(Duration(minutes: value.round()));
      case _WeekChartMetric.activities:
        return '${value.round()} ${_text('aktivitas', 'activities')}';
    }
  }

  String _angkaRingkas(double value, _WeekChartMetric metric) {
    switch (metric) {
      case _WeekChartMetric.distance:
        return value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
      case _WeekChartMetric.elevation:
        return value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : value.round().toString();
      case _WeekChartMetric.time:
        return value >= 60
            ? '${(value / 60).toStringAsFixed(0)}${_text('j', 'h')}'
            : value.round().toString();
      case _WeekChartMetric.activities:
        return value.round().toString();
    }
  }

  Widget _vo2MaxCard(List<RunSession> sessions) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AccountService.perubahanProfil,
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        final Map<String, dynamic> profile =
            snapshot.data?.data() ?? <String, dynamic>{};
        final DateTime? birthday =
            DateTime.tryParse(profile['tanggalLahir'] as String? ?? '');
        final int? age = birthday == null ? null : _ageFromBirthday(birthday);
        final String gender = profile['jenisKelamin'] as String? ?? '';

        final DateTime since = DateTime.now().subtract(
          const Duration(days: 180),
        );
        final List<({RunSession session, double value})> observations =
            sessions
                .where((RunSession session) =>
                    session.activityType == RunActivityType.run &&
                    !session.startedAt.isBefore(since))
                .map((RunSession session) {
                  final double? value = _estimateVo2FromTraining(session);
                  return value == null
                      ? null
                      : (session: session, value: value);
                })
                .whereType<({RunSession session, double value})>()
                .toList(growable: false)
              ..sort((a, b) => b.session.startedAt.compareTo(a.session.startedAt));

        final List<double> recentValues = observations
            .take(5)
            .map((({RunSession session, double value}) item) => item.value)
            .toList(growable: true)
          ..sort();
        final double? vo2max = recentValues.isEmpty
            ? null
            : recentValues[recentValues.length ~/ 2];
        final List<double>? thresholds = age == null
            ? null
            : _vo2Thresholds(age, gender);
        final String? grade = vo2max == null || thresholds == null
            ? null
            : _vo2Grade(vo2max, thresholds);
        final DateTime? lastSession = observations.isEmpty
            ? null
            : observations.first.session.startedAt;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    Icons.monitor_heart_outlined,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _text('Estimasi VO₂max', 'Estimated VO₂max'),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _text(
                  'Perkiraan otomatis dari jarak dan waktu bergerak pada sesi lari terbaru. Ini bukan pengukuran laboratorium.',
                  'Automatically estimated from distance and moving time in recent runs. This is not a laboratory measurement.',
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              if (vo2max != null) ...<Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      vo2max.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        'ml/kg/min',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (grade != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    child: Text(
                      grade,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  )
                else
                  Text(
                    _text(
                      age == null || !_genderCanBeClassified(gender)
                          ? 'Lengkapi tanggal lahir dan jenis kelamin di profil untuk melihat kategori berdasarkan usia.'
                          : 'Kategori pembanding tersedia untuk usia 13–79 tahun.',
                      age == null || !_genderCanBeClassified(gender)
                          ? 'Complete your date of birth and gender in your profile to see the age-based category.'
                          : 'Reference categories are available for ages 13–79.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 6),
                if (lastSession != null)
                  Text(
                    _text(
                      '${observations.length} sesi lari digunakan · terbaru ${_formatShortDate(lastSession)}',
                      '${observations.length} runs considered · latest ${_formatShortDate(lastSession)}',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ] else
                Text(
                  _text(
                    'Belum cukup data. Rekam sesi lari minimal 1,5 km dengan durasi bergerak 8 menit atau lebih.',
                    'Not enough data yet. Record a run of at least 1.5 km with 8 minutes or more of moving time.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  double? _estimateVo2FromTraining(RunSession session) {
    final double distanceMeters = session.distanceKm * 1000.0;
    final Duration duration = session.movingTime > Duration.zero
        ? session.movingTime
        : session.elapsed;
    final double minutes = duration.inSeconds / 60.0;
    if (!distanceMeters.isFinite || distanceMeters < 1500 ||
        !minutes.isFinite || minutes < 8 || minutes > 120) {
      return null;
    }
    final double velocityMetersPerMinute = distanceMeters / minutes;
    if (velocityMetersPerMinute < 50 || velocityMetersPerMinute > 450) {
      return null;
    }

    // Persamaan performa lari Daniels/VDOT: estimasi dari kecepatan berlari
    // dan durasi, bukan dari hasil tes yang harus dimasukkan pengguna.
    final double oxygenDemand = -4.60 +
        0.182258 * velocityMetersPerMinute +
        0.000104 * velocityMetersPerMinute * velocityMetersPerMinute;
    final double sustainableFraction = 0.8 +
        0.1894393 * math.exp(-0.012778 * minutes) +
        0.2989558 * math.exp(-0.1932605 * minutes);
    if (sustainableFraction <= 0) return null;
    final double estimate = oxygenDemand / sustainableFraction;
    if (!estimate.isFinite || estimate < 15 || estimate > 90) return null;
    return estimate;
  }

  int _ageFromBirthday(DateTime birthday) {
    final DateTime today = DateTime.now();
    int age = today.year - birthday.year;
    if (today.month < birthday.month ||
        (today.month == birthday.month && today.day < birthday.day)) {
      age--;
    }
    return age;
  }

  bool _genderCanBeClassified(String rawGender) {
    final String gender = rawGender.trim().toLowerCase();
    return gender == 'male' ||
        gender == 'pria' ||
        gender == 'laki-laki' ||
        gender == 'laki laki' ||
        gender == 'female' ||
        gender == 'wanita' ||
        gender == 'perempuan';
  }

  List<double>? _vo2Thresholds(int age, String rawGender) {
    final String gender = rawGender.trim().toLowerCase();
    final bool male = gender == 'male' ||
        gender == 'pria' ||
        gender == 'laki-laki' ||
        gender == 'laki laki';
    final bool female = gender == 'female' ||
        gender == 'wanita' ||
        gender == 'perempuan';
    if (!male && !female) return null;

    if (age >= 13 && age <= 19) {
      return male
          ? <double>[35.0, 38.4, 45.2, 51.0]
          : <double>[25.0, 31.0, 35.0, 39.0];
    }
    if (age < 20 || age > 79) return null;

    final int ageGroup = age < 30
        ? 0
        : age < 40
            ? 1
            : age < 50
                ? 2
                : age < 60
                    ? 3
                    : age < 70
                        ? 4
                        : 5;
    const List<List<double>> maleThresholds = <List<double>>[
      <double>[41.7, 45.4, 51.1, 55.4],
      <double>[40.5, 44.0, 48.3, 54.0],
      <double>[38.5, 42.4, 46.4, 52.5],
      <double>[35.6, 39.2, 43.4, 48.9],
      <double>[32.3, 35.5, 39.5, 45.7],
      <double>[29.4, 32.3, 36.7, 42.1],
    ];
    const List<List<double>> femaleThresholds = <List<double>>[
      <double>[36.1, 39.5, 43.9, 49.6],
      <double>[34.4, 37.8, 42.4, 47.4],
      <double>[33.0, 36.3, 39.7, 45.3],
      <double>[30.1, 33.0, 36.7, 41.1],
      <double>[27.5, 30.0, 33.0, 37.8],
      <double>[25.9, 28.1, 30.9, 36.7],
    ];
    return (male ? maleThresholds : femaleThresholds)[ageGroup];
  }

  String _vo2Grade(double value, List<double> thresholds) {
    if (value < thresholds[0]) return _text('Sangat kurang', 'Very low');
    if (value < thresholds[1]) return _text('Kurang', 'Below average');
    if (value < thresholds[2]) return _text('Normal / rata-rata', 'Average');
    if (value < thresholds[3]) return _text('Bagus', 'Good');
    return _text('Sangat bagus', 'Excellent');
  }

  String _formatShortDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

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
          Text(
            AppLanguageService.text(context, 'Prediksi waktu lomba', 'Race time estimates'),
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
                      ? AppLanguageService.text(context, 'Belum cukup data', 'Not enough data yet')
                      : '~${_formatRaceTime(prediction.seconds!)}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (prediction.sourceDistanceKm != null)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 7),
                child: Text(
                  AppLanguageService.text(context, 'Perkiraan dari lari ${prediction.sourceDistanceKm!.toStringAsFixed(1)} km', 'Estimated from a ${prediction.sourceDistanceKm!.toStringAsFixed(1)} km run'),
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
      return Localizations.localeOf(context).languageCode == 'en'
          ? '${hours}h ${minutes.toString().padLeft(2, '0')}m'
          : '${hours}j ${minutes.toString().padLeft(2, '0')}m';
    }
    return Localizations.localeOf(context).languageCode == 'en'
        ? '${minutes}m ${remainder.toString().padLeft(2, '0')}s'
        : '${minutes}m ${remainder.toString().padLeft(2, '0')}d';
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
            ' · ${deltaPersen.toStringAsFixed(1)}% ${_text('lebih cepat', 'faster')}';
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
      return Localizations.localeOf(context).languageCode == 'en'
          ? '${value.inHours}h ${value.inMinutes.remainder(60)}m'
          : '${value.inHours}j ${value.inMinutes.remainder(60)}m';
    }
    return '${value.inMinutes}m';
  }

  String _monthShort(int month) {
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final List<String> names = english
        ? <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        : <String>['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return names[month - 1];
  }
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
