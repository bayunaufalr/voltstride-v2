import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';

enum _PosterLayout { routeFocus, statsFirst, splitFocus, minimal, editorial }

class RunSharePage extends StatefulWidget {
  const RunSharePage({super.key, required this.session});

  final RunSession session;

  @override
  State<RunSharePage> createState() => _RunSharePageState();
}

class _ShareTheme {
  const _ShareTheme({
    required this.name,
    required this.background,
    required this.card,
    required this.accent,
    required this.text,
    required this.muted,
  });

  final String name;
  final Color background;
  final Color card;
  final Color accent;
  final Color text;
  final Color muted;
}

class _ShareMetric {
  const _ShareMetric(this.key, this.label, this.value);

  final String key;
  final String label;
  final String value;
}

class _RunSharePageState extends State<RunSharePage> {
  final GlobalKey _posterKey = GlobalKey();

  static const List<_ShareTheme> _themes = <_ShareTheme>[
    _ShareTheme(
      name: 'Gelap',
      background: Color(0xFF111111),
      card: Color(0xFF292929),
      accent: Color(0xFFD0D0D0),
      text: Colors.white,
      muted: Color(0xFFB5B5B5),
    ),
    _ShareTheme(
      name: 'Terang',
      background: Color(0xFFFFFFFF),
      card: Color(0xFFF2F2F2),
      accent: Color(0xFF222222),
      text: Color(0xFF111111),
      muted: Color(0xFF666666),
    ),
    _ShareTheme(
      name: 'Abu-abu',
      background: Color(0xFFE5E5E5),
      card: Color(0xFFFFFFFF),
      accent: Color(0xFF444444),
      text: Color(0xFF111111),
      muted: Color(0xFF666666),
    ),
  ];

  static const Map<_PosterLayout, String> _layoutNames =
      <_PosterLayout, String>{
    _PosterLayout.routeFocus: 'Rute utama',
    _PosterLayout.statsFirst: 'Statistik dahulu',
    _PosterLayout.splitFocus: 'Split kilometer',
    _PosterLayout.minimal: 'Minimalis',
    _PosterLayout.editorial: 'Editorial',
  };

  int _selectedTheme = 0;
  _PosterLayout _layout = _PosterLayout.routeFocus;
  bool _showDistance = true;
  bool _showDuration = true;
  bool _showPace = true;
  bool _showMap = true;
  bool _showElevation = true;
  bool _showSteps = true;
  bool _showCadence = true;
  bool _showCalories = true;
  bool _showDate = true;
  bool _showSplits = false;
  bool _sharing = false;

  @override
  Widget build(BuildContext context) {
    final _ShareTheme theme = _themes[_selectedTheme];
    return Scaffold(
      appBar: AppBar(title: const Text('Bagikan aktivitas')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: <Widget>[
          Center(
            child: RepaintBoundary(
              key: _posterKey,
              child: _poster(theme),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Tampilan',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List<Widget>.generate(_themes.length, (int index) {
              final _ShareTheme item = _themes[index];
              return ChoiceChip(
                label: Text(item.name),
                selected: _selectedTheme == index,
                onSelected: (_) => setState(() => _selectedTheme = index),
                avatar: CircleAvatar(backgroundColor: item.accent, radius: 7),
              );
            }),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pilih susunan template',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _PosterLayout.values.map((_PosterLayout layout) {
              return ChoiceChip(
                label: Text(_layoutNames[layout]!),
                selected: _layout == layout,
                onSelected: (_) => setState(() {
                  _layout = layout;
                  if (layout != _PosterLayout.splitFocus) _showSplits = false;
                }),
              );
            }).toList(growable: false),
          ),
          const SizedBox(height: 20),
          const Text(
            'Atur data yang ditampilkan',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'Aktifkan hanya informasi yang ingin dimasukkan ke gambar.',
            style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              _contentChip('Jarak', _showDistance, (bool v) => _showDistance = v),
              _contentChip('Durasi', _showDuration, (bool v) => _showDuration = v),
              _contentChip('Pace', _showPace, (bool v) => _showPace = v),
              _contentChip('Peta rute', _showMap, (bool v) => _showMap = v),
              _contentChip('Elevasi', _showElevation, (bool v) => _showElevation = v),
              _contentChip('Jumlah langkah', _showSteps, (bool v) => _showSteps = v),
              _contentChip('Cadence', _showCadence, (bool v) => _showCadence = v),
              _contentChip('Kalori', _showCalories, (bool v) => _showCalories = v),
              _contentChip('Tanggal', _showDate, (bool v) => _showDate = v),
              _contentChip('Split per km', _showSplits, (bool v) {
                _showSplits = v;
                if (v) _layout = _PosterLayout.splitFocus;
              }),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _sharing ? null : _sharePoster,
            icon: _sharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share_rounded),
            label: Text(
              _sharing ? 'Menyiapkan gambar…' : 'Bagikan gambar aktivitas',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Gambar dibuat di perangkat. Tidak perlu akun atau layanan berbayar.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _contentChip(
    String label,
    bool selected,
    ValueChanged<bool> onChanged,
  ) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (bool value) => setState(() => onChanged(value)),
    );
  }

  List<_ShareMetric> _visibleMetrics() {
    final RunSession session = widget.session;
    final RunElevationStats elevation = session.elevationStats;
    final List<_ShareMetric> metrics = <_ShareMetric>[];
    if (_showDuration) {
      metrics.add(_ShareMetric('duration', 'DURASI', session.elapsedText));
    }
    if (_showPace) {
      metrics.add(_ShareMetric(
        'pace',
        'PACE',
        session.averagePaceText == '--:--'
            ? '--'
            : '${session.averagePaceText}/km',
      ));
    }
    if (_showElevation) {
      metrics.add(_ShareMetric(
        'elevation',
        'ELEVASI +',
        elevation.hasAltitudeData
            ? '${elevation.totalAscentMeters.round()} m'
            : '--',
      ));
    }
    if (_showSteps) {
      metrics.add(_ShareMetric(
        'steps',
        'LANGKAH',
        session.totalSteps?.toString() ?? '--',
      ));
    }
    if (_showCadence) {
      metrics.add(_ShareMetric(
        'cadence',
        'CADENCE',
        session.averageCadenceSpm == null
            ? '--'
            : '${session.averageCadenceSpm!.round()} spm',
      ));
    }
    if (_showCalories) {
      metrics.add(_ShareMetric(
        'calories',
        'KALORI*',
        '${session.estimatedCalories.round()} kcal',
      ));
    }
    return metrics;
  }

  Widget _poster(_ShareTheme theme) {
    final RunSession session = widget.session;
    final String activityLabel = session.intervalPlan != null
        ? 'LARI INTERVAL'
        : session.activityType == RunActivityType.walk
            ? 'BERJALAN'
            : 'BERLARI';
    final double aspectRatio = _layout == _PosterLayout.minimal ? 0.76 : 0.64;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: theme.accent.withValues(alpha: 0.45)),
        ),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _posterHeader(theme, activityLabel),
            const SizedBox(height: 12),
            if (_layout == _PosterLayout.editorial)
              _editorialHero(theme)
            else if (_showDistance)
              _distanceHero(theme, compact: _layout == _PosterLayout.statsFirst),
            if (_layout != _PosterLayout.minimal) const SizedBox(height: 10),
            if (_layout == _PosterLayout.statsFirst) _metricsGrid(theme),
            if (_layout == _PosterLayout.splitFocus) ...<Widget>[
              if (_showMap && _showSplits && session.splits.isNotEmpty) ...<Widget>[
                SizedBox(height: 82, child: _routePanel(theme)),
                const SizedBox(height: 7),
              ],
              if (_showMap && (!_showSplits || session.splits.isEmpty))
                Expanded(child: _routePanel(theme))
              else if (_showSplits && session.splits.isNotEmpty)
                Expanded(child: _splitPanel(theme))
              else
                Expanded(child: _emptyPanel(theme)),
            ] else ...<Widget>[
              Expanded(
                child: _showMap
                    ? _routePanel(theme)
                    : _emptyPanel(theme),
              ),
            ],
            if (_layout != _PosterLayout.statsFirst &&
                _layout != _PosterLayout.minimal) ...<Widget>[
              const SizedBox(height: 10),
              _metricsGrid(theme),
            ] else if (_layout == _PosterLayout.minimal) ...<Widget>[
              const SizedBox(height: 8),
              _metricsGrid(theme, compact: true),
            ],
            if (_showDate) ...<Widget>[
              const SizedBox(height: 9),
              Text(
                '${session.startedAt.toLocal().day.toString().padLeft(2, '0')}/'
                '${session.startedAt.toLocal().month.toString().padLeft(2, '0')}/'
                '${session.startedAt.toLocal().year} • ${session.environment.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: theme.muted, fontSize: 9),
              ),
            ],
            if (_showCalories) ...<Widget>[
              const SizedBox(height: 3),
              Text(
                '*Kalori merupakan perkiraan.',
                style: TextStyle(color: theme.muted, fontSize: 8),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _posterHeader(_ShareTheme theme, String activityLabel) {
    // Header tanpa logo atau hiasan merek. Nama aktivitas menjadi judulnya.
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        activityLabel,
        maxLines: 1,
        style: TextStyle(
          color: theme.text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _distanceHero(_ShareTheme theme, {bool compact = false}) {
    if (!_showDistance) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.session.distanceKm.toStringAsFixed(2),
          maxLines: 1,
          style: TextStyle(
            color: theme.text,
            fontSize: compact ? 35 : 43,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
        Text(
          'KILOMETER',
          style: TextStyle(
            color: theme.muted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }

  Widget _editorialHero(_ShareTheme theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (_showDistance)
          Expanded(child: _distanceHero(theme, compact: true)),
        if (_showDuration)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text('WAKTU', style: TextStyle(color: theme.muted, fontSize: 8)),
              Text(
                widget.session.elapsedText,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        if (!_showDistance && !_showDuration)
          Text(
            'AKTIVITAS',
            style: TextStyle(color: theme.text, fontSize: 23, fontWeight: FontWeight.w900),
          ),
      ],
    );
  }

  Widget _metricsGrid(_ShareTheme theme, {bool compact = false}) {
    final List<_ShareMetric> metrics = _visibleMetrics();
    if (metrics.isEmpty) return const SizedBox.shrink();
    final double itemWidth = compact ? 84 : 88;
    return Wrap(
      spacing: 7,
      runSpacing: compact ? 5 : 7,
      children: metrics.map((_ShareMetric metric) {
        return SizedBox(
          key: ValueKey<String>(metric.key),
          width: itemWidth,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 5 : 6,
              vertical: compact ? 5 : 6,
            ),
            decoration: BoxDecoration(
              color: theme.card,
              borderRadius: BorderRadius.zero,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.35,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _routePanel(_ShareTheme theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.zero,
      ),
      child: CustomPaint(
        painter: _PosterRoutePainter(
          route: widget.session.route,
          color: theme.accent,
          background: theme.card,
        ),
      ),
    );
  }

  Widget _emptyPanel(_ShareTheme theme) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.bolt_rounded, color: theme.accent, size: 38),
          const SizedBox(height: 8),
          Text(
            'SETIAP LANGKAH BERARTI',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitPanel(_ShareTheme theme) {
    final List<RunSplit> splits = widget.session.splits.take(5).toList(growable: false);
    if (splits.isEmpty) return _emptyPanel(theme);
    final int maxDuration = splits
        .map((RunSplit split) => split.durationSeconds)
        .fold<int>(1, (int best, int value) => value > best ? value : best);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.zero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SPLIT PER KM',
            style: TextStyle(
              color: theme.text,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          ...splits.map((RunSplit split) {
            final double ratio =
                (split.durationSeconds / maxDuration).clamp(0.12, 1.0).toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${split.kilometer}',
                      style: TextStyle(color: theme.muted, fontSize: 8),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.zero,
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: theme.muted.withValues(alpha: 0.16),
                        valueColor: AlwaysStoppedAnimation<Color>(theme.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: 38,
                    child: Text(
                      split.paceText.replaceAll('/km', ''),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _sharePoster() async {
    setState(() => _sharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final BuildContext? boundaryContext = _posterKey.currentContext;
      final RenderObject? render = boundaryContext?.findRenderObject();
      if (render is! RenderRepaintBoundary) {
        throw StateError('Tampilan gambar belum siap.');
      }
      final ui.Image image = await render.toImage(pixelRatio: 3);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('Gambar tidak dapat dibuat.');
      final Uint8List bytes = byteData.buffer.asUint8List();
      final String path = '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'voltstride-activity-${DateTime.now().millisecondsSinceEpoch}.png';
      final File file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: 'image/png')],
          title: 'Bagikan aktivitas VoltStride',
          text: _shareText(),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membagikan gambar: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _shareText() {
    final RunSession session = widget.session;
    final List<String> details = <String>[];
    if (_showDistance) details.add('${session.distanceText} km');
    if (_showDuration) details.add(session.elapsedText);
    if (_showPace) details.add('pace ${session.averagePaceText}/km');
    if (_showElevation && session.elevationStats.hasAltitudeData) {
      details.add('Elevasi +${session.elevationStats.totalAscentMeters.round()} m');
    }
    if (_showCalories) details.add('sekitar ${session.estimatedCalories.round()} kcal');
    return <String>['Aktivitas VoltStride', ...details].join(' • ');
  }
}

class _PosterRoutePainter extends CustomPainter {
  const _PosterRoutePainter({
    required this.route,
    required this.color,
    required this.background,
  });

  final List<RunPoint> route;
  final Color color;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final List<RunPoint> valid = route.where((RunPoint point) =>
        point.latitude.isFinite && point.longitude.isFinite &&
        point.latitude >= -90 && point.latitude <= 90 &&
        point.longitude >= -180 && point.longitude <= 180).toList(growable: false);
    if (valid.length < 2 || size.width <= 0 || size.height <= 0) {
      final TextPainter text = TextPainter(
        text: TextSpan(
          text: 'Rute belum tersedia',
          style: TextStyle(color: color, fontSize: 12),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width.isFinite ? size.width : 200);
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
      return;
    }

    double minLat = valid.first.latitude;
    double maxLat = minLat;
    double minLon = valid.first.longitude;
    double maxLon = minLon;
    for (final RunPoint point in valid.skip(1)) {
      minLat = math.min(minLat, point.latitude).toDouble();
      maxLat = math.max(maxLat, point.latitude).toDouble();
      minLon = math.min(minLon, point.longitude).toDouble();
      maxLon = math.max(maxLon, point.longitude).toDouble();
    }

    final double latSpan = (maxLat - minLat).abs();
    final double lonSpan = (maxLon - minLon).abs();
    final double centerLat = (minLat + maxLat) / 2;
    final double cosLat = math.cos(centerLat * math.pi / 180).abs().clamp(0.1, 1.0).toDouble();
    final double scaleX = size.width * 0.82 / (lonSpan <= 1e-7 ? 1e-7 : lonSpan * cosLat);
    final double scaleY = size.height * 0.78 / (latSpan <= 1e-7 ? 1e-7 : latSpan);
    final double scale = math.min(scaleX, scaleY).toDouble();
    final List<Offset> points = valid.map((RunPoint point) => Offset(
          size.width / 2 + (point.longitude - (minLon + maxLon) / 2) * cosLat * scale,
          size.height / 2 - (point.latitude - (minLat + maxLat) / 2) * scale,
        )).toList(growable: false);

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final Paint line = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      if (i == 0 || valid[i].startsNewSegment) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }
    canvas.drawPath(path, line);
    canvas.drawCircle(points.first, 5.5, Paint()..color = const Color(0xFFA5A5A5));
    canvas.drawCircle(points.last, 5.5, Paint()..color = const Color(0xFF909090));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PosterRoutePainter oldDelegate) =>
      oldDelegate.route != route ||
      oldDelegate.color != color ||
      oldDelegate.background != background;
}
