// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/app_language_service.dart';
import '../account/account_service.dart';
import '../../theme/volt_theme.dart';
import 'models/run_session.dart';

enum _MetricKind { elevation, pace, cadence, heartRate }

/// Grafik lokal tanpa dependensi tambahan. Grafik dapat digeser/disentuh untuk
/// membaca nilai tepat pada jarak yang dipilih.
class RunActivityCharts extends StatelessWidget {
  const RunActivityCharts({super.key, required this.session});

  final RunSession session;

  @override
  Widget build(BuildContext context) {
    String text(String indonesia, String english) =>
        AppLanguageService.text(context, indonesia, english);
    final List<Offset> elevation = _elevationPoints(session.route);
    final List<Offset> pace = session.hundredMeterLaps
        .where((RunLap100m lap) {
          final double? value = lap.paceSecondsPerKm;
          // Nilai ekstrem pada data split biasanya berasal dari GPS yang sesaat
          // berhenti/berloncatan; jangan biarkan satu sampel merusak skala grafik.
          return value != null && value.isFinite && value >= 150 && value <= 1800;
        })
        .map((RunLap100m lap) => Offset(
              lap.distanceMeters / 1000,
              lap.paceSecondsPerKm!,
            ))
        .toList(growable: false);
    final List<Offset> heartRate = _downsample(
      session.heartRateSamples
          .where((RunHeartRateSample sample) =>
              sample.elapsedSeconds >= 0 &&
              sample.bpm >= 30 &&
              sample.bpm <= 240)
          .map((RunHeartRateSample sample) => Offset(
                sample.elapsedSeconds.toDouble(),
                sample.bpm.toDouble(),
              ))
          .toList(growable: false),
    );
    final List<Offset> cadence = session.cadenceSamples
        .where((RunCadenceSample sample) =>
            sample.distanceMeters.isFinite &&
            sample.cadenceSpm.isFinite &&
            sample.cadenceSpm >= 20 &&
            sample.cadenceSpm <= 300)
        .map((RunCadenceSample sample) => Offset(
              sample.distanceMeters / 1000,
              sample.cadenceSpm,
            ))
        .toList(growable: false);

    return Column(
      children: <Widget>[
        _InteractiveMetricChart(
          key: const ValueKey<String>('elevation-chart'),
          title: text('Elevasi', 'Elevation'),
          subtitle: text('Elevasi relatif • meter', 'Relative elevation • meters'),
          points: elevation,
          emptyText: text('Data elevasi belum cukup.', 'Not enough elevation data.'),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFF0F0F0)
              : const Color(0xFF222222),
          kind: _MetricKind.elevation,
        ),
        const SizedBox(height: 12),
        _InteractiveMetricChart(
          key: const ValueKey<String>('pace-chart'),
          title: 'Pace',
          subtitle: text('Menit per kilometer', 'Minutes per kilometer'),
          points: pace,
          emptyText: text('Belum ada split 100 m yang lengkap.', 'No complete 100 m splits are available.'),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFBDBDBD)
              : const Color(0xFF555555),
          kind: _MetricKind.pace,
          invertVertical: true,
        ),
        const SizedBox(height: 12),
        _InteractiveMetricChart(
          key: const ValueKey<String>('heart-rate-chart'),
          title: text('Detak jantung', 'Heart rate'),
          subtitle: text('Denyut per menit • waktu aktivitas', 'Beats per minute • elapsed time'),
          points: heartRate,
          emptyText: session.averageHeartRateBpm == null
              ? text('Sensor HR tidak merekam data pada sesi ini.', 'No heart-rate samples were recorded during this session.')
              : text('Rerata tersedia, tetapi sampel grafik tidak direkam.', 'The average is available, but chart samples were not recorded.'),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFFE0E0E0)
              : const Color(0xFF303030),
          kind: _MetricKind.heartRate,
        ),
        const SizedBox(height: 8),
        _HeartRateZoneBreakdown(session: session),
        const SizedBox(height: 12),
        _InteractiveMetricChart(
          key: const ValueKey<String>('cadence-chart'),
          title: 'Cadence',
          subtitle: text('Langkah per menit', 'Steps per minute'),
          points: cadence,
          emptyText: text('Cadence belum tersedia.', 'Cadence data is unavailable.'),
          color: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF858585)
              : const Color(0xFF888888),
          kind: _MetricKind.cadence,
        ),
      ],
    );
  }

  List<Offset> _elevationPoints(List<RunPoint> route) {
    final List<Offset> raw = <Offset>[];
    double distance = 0;
    double? elevationAtStart;
    RunPoint? previous;
    for (final RunPoint point in route) {
      if (previous != null && !point.startsNewSegment) {
        distance += distanceBetweenMeters(
          latitude1: previous.latitude,
          longitude1: previous.longitude,
          latitude2: point.latitude,
          longitude2: point.longitude,
        );
      }
      final double? altitude = point.altitudeMeters;
      if (altitude != null && altitude.isFinite) {
        elevationAtStart ??= altitude;
        raw.add(Offset(distance / 1000, altitude - elevationAtStart));
      }
      previous = point;
    }
    if (raw.length < 5) return _downsample(raw);

    final List<Offset> smoothed = List<Offset>.generate(raw.length, (int index) {
      final int first = math.max(0, index - 3).toInt();
      final int last = math.min(raw.length - 1, index + 3).toInt();
      final List<double> window = raw
          .sublist(first, last + 1)
          .map((Offset point) => point.dy)
          .toList()
        ..sort();
      return Offset(raw[index].dx, window[window.length ~/ 2]);
    }, growable: false);
    return _downsample(smoothed);
  }

  List<Offset> _downsample(List<Offset> points) {
    const int maxPoints = 500;
    if (points.length <= maxPoints) return points;
    final int stride = (points.length / maxPoints).ceil();
    final List<Offset> result = <Offset>[];
    for (int i = 0; i < points.length; i += stride) {
      result.add(points[i]);
    }
    if (result.last != points.last) result.add(points.last);
    return result;
  }
}

class _HeartRateZoneBreakdown extends StatefulWidget {
  const _HeartRateZoneBreakdown({required this.session});

  final RunSession session;

  @override
  State<_HeartRateZoneBreakdown> createState() => _HeartRateZoneBreakdownState();
}

class _HeartRateZoneBreakdownState extends State<_HeartRateZoneBreakdown> {
  int? _selectedZone;

  @override
  Widget build(BuildContext context) {
    String text(String indonesia, String english) =>
        AppLanguageService.text(context, indonesia, english);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: AccountService.perubahanProfil,
      builder: (BuildContext context,
          AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot) {
        final Map<String, dynamic> profile =
            snapshot.data?.data() ?? <String, dynamic>{};
        final DateTime? birthDate = DateTime.tryParse(
          profile['tanggalLahir'] as String? ?? '',
        );
        if (birthDate == null) {
          return _zoneInfoCard(
            context,
            text(
              'Lengkapi tanggal lahir di profil untuk memperkirakan zona HR.',
              'Add your birth date to the profile to estimate HR zones.',
            ),
          );
        }
        final DateTime today = DateTime.now();
        int age = today.year - birthDate.year;
        if (today.month < birthDate.month ||
            (today.month == birthDate.month && today.day < birthDate.day)) {
          age--;
        }
        if (age < 1 || age > 110) {
          return _zoneInfoCard(
            context,
            text('Tanggal lahir pada profil tidak valid.', 'The profile birth date is invalid.'),
          );
        }
        final int estimatedMaxHr = 220 - age;
        return _buildZoneCard(context, estimatedMaxHr, text);
      },
    );
  }

  Widget _zoneInfoCard(BuildContext context, String message) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Text(
        message,
        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
      ),
    );
  }

  Widget _buildZoneCard(
    BuildContext context,
    int estimatedMaxHr,
    String Function(String, String) text,
  ) {
    final RunSession session = widget.session;
    final List<RunHeartRateSample> samples = session.heartRateSamples
        .where((RunHeartRateSample sample) =>
            sample.elapsedSeconds >= 0 && sample.bpm >= 30 && sample.bpm <= 240)
        .toList(growable: false)
      ..sort((RunHeartRateSample a, RunHeartRateSample b) =>
          a.elapsedSeconds.compareTo(b.elapsedSeconds));
    final List<int> secondsByZone = List<int>.filled(5, 0);
    for (int index = 0; index < samples.length; index++) {
      final RunHeartRateSample sample = samples[index];
      final int endSeconds = index + 1 < samples.length
          ? samples[index + 1].elapsedSeconds
          : session.elapsed.inSeconds;
      final int intervalSeconds = endSeconds - sample.elapsedSeconds;
      if (intervalSeconds <= 0) continue;
      // A long sensor gap is not treated as if the last reading were accurate
      // for the whole gap.
      final int countedSeconds = intervalSeconds > 10 ? 10 : intervalSeconds;
      secondsByZone[_zoneIndex(sample.bpm, estimatedMaxHr)] += countedSeconds;
    }
    final int trackedSeconds = secondsByZone.fold<int>(
      0,
      (int sum, int seconds) => sum + seconds,
    );
    final int? averageBpm = session.averageHeartRateBpm;
    final int? averageZone = averageBpm == null
        ? null
        : _zoneIndex(averageBpm, estimatedMaxHr);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final List<Color> colors = dark
        ? const <Color>[
            Color(0xFFECECEC),
            Color(0xFFC8C8C8),
            Color(0xFFA5A5A5),
            Color(0xFF828282),
            Color(0xFF5F5F5F),
          ]
        : const <Color>[
            Color(0xFF292929),
            Color(0xFF494949),
            Color(0xFF696969),
            Color(0xFF898989),
            Color(0xFFA9A9A9),
          ];
    const List<String> zoneShort = <String>['Z1', 'Z2', 'Z3', 'Z4', 'Z5'];
    final List<String> zoneNames = <String>[
      text('Pemulihan', 'Recovery'),
      text('Mudah', 'Easy'),
      text('Aerobik', 'Aerobic'),
      text('Ambang batas', 'Threshold'),
      text('Tinggi', 'High'),
    ];
    const List<String> zoneRanges = <String>[
      '<60%',
      '60–70%',
      '70–80%',
      '80–90%',
      '≥90%',
    ];
    final int selected = _selectedZone ?? averageZone ?? 0;
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final double fraction = trackedSeconds > 0 && selected >= 0 && selected < 5
        ? secondsByZone[selected] / trackedSeconds
        : 0;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            text('WAKTU DI ZONA DETAK JANTUNG', 'HEART RATE ZONE TIME'),
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            text(
              'Zona perkiraan berdasarkan HR maksimal $estimatedMaxHr bpm (220 − usia).',
              'Estimated zones use max HR $estimatedMaxHr bpm (220 − age).',
            ),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
          ),
          if (averageZone != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              text(
                'Zona rata-rata: ${zoneShort[averageZone]} · ${zoneNames[averageZone]}',
                'Average zone: ${zoneShort[averageZone]} · ${zoneNames[averageZone]}',
              ),
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (samples.isEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              text(
                'Sampel HR tidak tersedia, jadi durasi tiap zona belum dapat dihitung.',
                'HR samples are unavailable, so time in each zone cannot be calculated.',
              ),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ] else if (trackedSeconds == 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              text('Sampel HR terlalu jarang untuk menghitung durasi zona.', 'HR samples are too sparse to calculate zone duration.'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 112,
                  height: 112,
                  child: CustomPaint(
                    painter: _HeartRateZoneDonutPainter(
                      secondsByZone: secondsByZone,
                      colors: colors,
                      selectedZone: selected,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                '${(fraction * 100).round()}%',
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                text('dipilih', 'selected'),
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: List<Widget>.generate(5, (int index) {
                      final bool isSelected = index == selected;
                      final String timeText = _formatZoneDuration(
                        secondsByZone[index],
                        english,
                      );
                      return InkWell(
                        onTap: () => setState(() => _selectedZone = index),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? scheme.surfaceContainerHighest
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: <Widget>[
                              Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: colors[index],
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${zoneShort[index]} ${zoneNames[index]}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                timeText,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${zoneShort[selected]} • ${zoneRanges[selected]} HRmax • ${(fraction * 100).round()}% ${text("dari waktu HR yang terekam", "of recorded HR time")}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
          const SizedBox(height: 7),
          Text(
            text(
              'Zona ini hanya perkiraan kebugaran umum; rumus HR maksimal dapat meleset untuk individu.',
              'Zones are general estimates; age-predicted maximum HR can differ from individual values.',
            ),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }

  int _zoneIndex(int bpm, int estimatedMaxHr) {
    final double fraction = bpm / estimatedMaxHr;
    if (fraction < 0.6) return 0;
    if (fraction < 0.7) return 1;
    if (fraction < 0.8) return 2;
    if (fraction < 0.9) return 3;
    return 4;
  }

  String _formatZoneDuration(int seconds, bool english) {
    final int minutes = seconds ~/ 60;
    final int remainder = seconds % 60;
    if (minutes >= 60) {
      final int hours = minutes ~/ 60;
      final String leftoverMinutes = (minutes % 60).toString().padLeft(2, '0');
      return english ? '${hours}h ${leftoverMinutes}m' : '${hours}j ${leftoverMinutes}m';
    }
    if (minutes > 0) {
      final String leftoverSeconds = remainder.toString().padLeft(2, '0');
      return english ? '${minutes}m ${leftoverSeconds}s' : '${minutes}m ${leftoverSeconds}dtk';
    }
    return english ? '${remainder}s' : '${remainder}dtk';
  }
}

class _HeartRateZoneDonutPainter extends CustomPainter {
  const _HeartRateZoneDonutPainter({
    required this.secondsByZone,
    required this.colors,
    required this.selectedZone,
    required this.backgroundColor,
  });

  final List<int> secondsByZone;
  final List<Color> colors;
  final int? selectedZone;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double strokeWidth = size.shortestSide * 0.15;
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint background = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, background);
    final int total = secondsByZone.fold<int>(
      0,
      (int sum, int value) => sum + value,
    );
    if (total <= 0) return;
    double startAngle = -math.pi / 2;
    for (int index = 0; index < secondsByZone.length; index++) {
      final int value = secondsByZone[index];
      if (value <= 0) continue;
      final double sweep = value / total * math.pi * 2;
      final bool selected = selectedZone == index;
      final Paint segment = Paint()
        ..color = colors[index]
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = selected ? strokeWidth * 1.18 : strokeWidth;
      final double segmentSweep = sweep > 0.05 ? sweep - 0.05 : 0.0;
      canvas.drawArc(
        rect,
        startAngle + 0.025,
        segmentSweep,
        false,
        segment,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _HeartRateZoneDonutPainter oldDelegate) =>
      oldDelegate.secondsByZone != secondsByZone ||
      oldDelegate.colors != colors ||
      oldDelegate.selectedZone != selectedZone ||
      oldDelegate.backgroundColor != backgroundColor;
}

class _InteractiveMetricChart extends StatefulWidget {
  const _InteractiveMetricChart({
    super.key,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.emptyText,
    required this.color,
    required this.kind,
    this.invertVertical = false,
  });

  final String title;
  final String subtitle;
  final List<Offset> points;
  final String emptyText;
  final Color color;
  final _MetricKind kind;
  final bool invertVertical;

  @override
  State<_InteractiveMetricChart> createState() => _InteractiveMetricChartState();
}

class _InteractiveMetricChartState extends State<_InteractiveMetricChart> {
  static const double _plotLeft = 54;
  static const double _plotRightInset = 12;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.points.isEmpty ? 0 : widget.points.length - 1;
  }

  List<Offset> get _points => widget.points
      .where((Offset point) => point.dx.isFinite && point.dy.isFinite)
      .toList(growable: false);

  @override
  void didUpdateWidget(covariant _InteractiveMetricChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final List<Offset> points = _points;
    if (_selectedIndex >= points.length) {
      _selectedIndex = points.isEmpty ? 0 : points.length - 1;
    }
  }

  void _selectNearest(Offset localPosition, double width) {
    final List<Offset> points = _points;
    if (points.length < 2 || width <= _plotLeft + _plotRightInset) return;
    final double minX = points.first.dx;
    final double maxX = points.last.dx;
    if (!minX.isFinite || !maxX.isFinite) return;
    final double plotWidth = width - _plotLeft - _plotRightInset;
    final double fraction =
        ((localPosition.dx - _plotLeft) / plotWidth)
            .clamp(0.0, 1.0)
            .toDouble();
    final double targetX = minX + fraction * (maxX - minX);

    int nearestIndex = 0;
    double nearestDelta = double.infinity;
    for (int i = 0; i < points.length; i++) {
      final double delta = (points[i].dx - targetX).abs();
      if (delta < nearestDelta) {
        nearestDelta = delta;
        nearestIndex = i;
      }
    }
    if (nearestIndex != _selectedIndex && mounted) {
      setState(() => _selectedIndex = nearestIndex);
    }
  }

  String _valueText(double value) {
    switch (widget.kind) {
      case _MetricKind.pace:
        final int seconds = value.round();
        return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}/km';
      case _MetricKind.elevation:
        return '${value > 0 ? '+' : ''}${value.round()} m';
      case _MetricKind.cadence:
        return '${value.round()} spm';
      case _MetricKind.heartRate:
        return '${value.round()} bpm';
    }
  }

  String _xValueText(double value) {
    if (widget.kind != _MetricKind.heartRate) {
      return '${value.toStringAsFixed(2)} km';
    }
    final int seconds = math.max(0, value.round()).toInt();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _metricName() {
    switch (widget.kind) {
      case _MetricKind.pace:
        return AppLanguageService.text(context, 'Pace pada jarak ini', 'Pace at this distance');
      case _MetricKind.elevation:
        return AppLanguageService.text(context, 'Elevasi relatif', 'Relative elevation');
      case _MetricKind.cadence:
        return AppLanguageService.text(context, 'Cadence pada jarak ini', 'Cadence at this distance');
      case _MetricKind.heartRate:
        return AppLanguageService.text(context, 'Detak jantung pada waktu ini', 'Heart rate at this time');
    }
  }

  String _rangeText(List<Offset> points) {
    final List<double> values = points.map((Offset point) => point.dy).toList();
    final double low = values.reduce((double a, double b) => a < b ? a : b);
    final double high = values.reduce((double a, double b) => a > b ? a : b);
    switch (widget.kind) {
      case _MetricKind.pace:
        return AppLanguageService.text(context, 'Rentang ${_valueText(low)} – ${_valueText(high)}', 'Range ${_valueText(low)} – ${_valueText(high)}');
      case _MetricKind.elevation:
        return AppLanguageService.text(context, 'Terendah ${_valueText(low)} • tertinggi ${_valueText(high)}', 'Lowest ${_valueText(low)} • highest ${_valueText(high)}');
      case _MetricKind.cadence:
        return AppLanguageService.text(context, 'Rentang ${low.round()}–${high.round()} spm', 'Range ${low.round()}–${high.round()} spm');
      case _MetricKind.heartRate:
        return AppLanguageService.text(context, 'Rentang ${low.round()}–${high.round()} bpm', 'Range ${low.round()}–${high.round()} bpm');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Offset> points = _points;
    if (points.isNotEmpty && _selectedIndex >= points.length) {
      _selectedIndex = points.length - 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: 25,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 11,
                color: VoltWarna.teksAbu,
              ),
            ),
            const SizedBox(height: 8),
            if (points.length < 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 22),
                child: Text(
                  widget.emptyText,
                  style: TextStyle(
                    color: VoltWarna.teksAbu,
                    fontSize: 12,
                  ),
                ),
              )
            else ...<Widget>[
              Text(
                _rangeText(points),
                style: TextStyle(
                  fontSize: 11,
                  color: VoltWarna.teksAbu,
                ),
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Size chartSize = Size(
                    constraints.maxWidth,
                    220,
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (TapDownDetails details) =>
                        _selectNearest(details.localPosition, chartSize.width),
                    onHorizontalDragStart: (DragStartDetails details) =>
                        _selectNearest(details.localPosition, chartSize.width),
                    onHorizontalDragUpdate: (DragUpdateDetails details) =>
                        _selectNearest(details.localPosition, chartSize.width),
                    child: SizedBox(
                      height: chartSize.height,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _MetricChartPainter(
                          points: points,
                          color: widget.color,
                          textColor: Theme.of(context).colorScheme.onSurface,
                          gridColor: Theme.of(context).dividerColor,
                          kind: widget.kind,
                          invertVertical: widget.invertVertical,
                          selectedIndex: _selectedIndex,
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: widget.color.withValues(alpha: 0.38),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.straighten_rounded, color: widget.color, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _xValueText(points[_selectedIndex].dx),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _metricName(),
                            style: TextStyle(
                              color: VoltWarna.teksAbu,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      _valueText(points[_selectedIndex].dy),
                      style: TextStyle(
                        color: widget.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Text(
                AppLanguageService.text(context, 'Ketuk atau geser grafik untuk meninjau nilai pada jarak tertentu.', 'Tap or drag the chart to inspect values at a specific point.'),
                style: TextStyle(
                  color: VoltWarna.teksAbu,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChartPainter extends CustomPainter {
  const _MetricChartPainter({
    required this.points,
    required this.color,
    required this.textColor,
    required this.gridColor,
    required this.kind,
    required this.invertVertical,
    required this.selectedIndex,
  });

  final List<Offset> points;
  final Color color;
  final Color textColor;
  final Color gridColor;
  final _MetricKind kind;
  final bool invertVertical;
  final int selectedIndex;

  static const double _left = 54;
  static const double _right = 12;
  static const double _top = 16;
  static const double _bottom = 34;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.width <= _left + _right + 4 ||
        size.height <= _top + _bottom + 4) {
      return;
    }

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    final Rect plot = Rect.fromLTRB(
      _left,
      _top,
      math.max(_left + 1, size.width - _right),
      math.max(_top + 1, size.height - _bottom),
    );
    double minX = points.first.dx;
    double maxX = points.last.dx;
    double minY = points.map((Offset p) => p.dy).reduce((double a, double b) => a < b ? a : b);
    double maxY = points.map((Offset p) => p.dy).reduce((double a, double b) => a > b ? a : b);
    if (maxX <= minX) maxX = minX + 0.1;
    if (maxY - minY < 0.5) {
      minY -= 0.5;
      maxY += 0.5;
    }
    final double paddingY = (maxY - minY) * 0.08;
    minY -= paddingY;
    maxY += paddingY;
    final double rangeY = maxY - minY;

    final Paint gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Paint fillPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final Paint cursorPaint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..strokeWidth = 1.2;

    for (int i = 0; i <= 2; i++) {
      final double fraction = i / 2;
      final double y = plot.top + plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final double tickValue = invertVertical
          ? minY + rangeY * fraction
          : maxY - rangeY * fraction;
      _drawText(
        canvas,
        _tickText(tickValue),
        Offset(_left - 6, y - 6),
        maxWidth: _left - 12,
        fontSize: 9,
        align: TextAlign.right,
      );
    }

    Offset mapPoint(Offset point) {
      final double x = plot.left +
          ((point.dx - minX) / (maxX - minX)) * plot.width;
      double normalizedY = (point.dy - minY) / rangeY;
      if (invertVertical) normalizedY = 1 - normalizedY;
      final double y = plot.bottom - normalizedY * plot.height;
      return Offset(x, y);
    }

    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final Offset point = mapPoint(points[i]);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final Path fill = Path.from(path)
      ..lineTo(plot.right, plot.bottom)
      ..lineTo(plot.left, plot.bottom)
      ..close();
    canvas.drawPath(fill, fillPaint);
    canvas.drawPath(path, linePaint);

    final int activeIndex = selectedIndex.clamp(0, points.length - 1).toInt();
    final Offset selected = mapPoint(points[activeIndex]);
    canvas.drawLine(
      Offset(selected.dx, plot.top),
      Offset(selected.dx, plot.bottom),
      cursorPaint,
    );
    canvas.drawCircle(
      selected,
      6,
      Paint()..color = color.withValues(alpha: 0.20),
    );
    canvas.drawCircle(
      selected,
      3.5,
      Paint()..color = color,
    );
    canvas.drawCircle(
      selected,
      3.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final double middleX = (minX + maxX) / 2;
    _drawText(canvas, _xAxisText(minX), Offset(plot.left, plot.bottom + 9), maxWidth: 70, fontSize: 9);
    _drawText(canvas, _xAxisText(middleX), Offset(plot.left + plot.width / 2, plot.bottom + 9), maxWidth: 70, fontSize: 9, align: TextAlign.center);
    _drawText(canvas, _xAxisText(maxX), Offset(plot.right, plot.bottom + 9), maxWidth: 70, fontSize: 9, align: TextAlign.right);
    canvas.restore();
  }

  String _tickText(double value) {
    switch (kind) {
      case _MetricKind.pace:
        final int seconds = value.round().clamp(0, 99999).toInt();
        return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
      case _MetricKind.elevation:
        return value.round().toString();
      case _MetricKind.cadence:
        return value.round().toString();
      case _MetricKind.heartRate:
        return value.round().toString();
    }
  }

  String _xAxisText(double value) {
    if (kind != _MetricKind.heartRate) {
      return '${value.toStringAsFixed(2)} km';
    }
    final int seconds = math.max(0, value.round()).toInt();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    required double maxWidth,
    double fontSize = 9,
    TextAlign align = TextAlign.left,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    double x = position.dx;
    if (align == TextAlign.right) x -= painter.width;
    if (align == TextAlign.center) x -= painter.width / 2;
    painter.paint(canvas, Offset(x, position.dy));
  }

  @override
  bool shouldRepaint(covariant _MetricChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.textColor != textColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.kind != kind ||
      oldDelegate.invertVertical != invertVertical ||
      oldDelegate.selectedIndex != selectedIndex;
}
