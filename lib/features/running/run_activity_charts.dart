// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
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
