import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'run_segment_data.dart';

/// Peta rute yang menampilkan warna pace dengan label kecil, bukan kartu besar.
/// Garis display boleh disederhanakan untuk visual; data GPS asli tidak diubah.
class RunRouteMapView extends StatefulWidget {
  const RunRouteMapView({
    super.key,
    required this.route,
    required this.laps,
    this.height = 280,
    this.followLastPoint = false,
    this.showIntervalSelector = false,
    this.initialIntervalMeters = 100,
    this.selectedIntervalMeters,
    this.onIntervalMetersChanged,
  });

  final List<RunPoint> route;
  final List<RunLap100m> laps;
  final double height;
  final bool followLastPoint;
  final bool showIntervalSelector;
  final int initialIntervalMeters;
  /// Jika diisi, pemilihan interval dikendalikan bersama oleh halaman induk.
  final int? selectedIntervalMeters;
  final ValueChanged<int>? onIntervalMetersChanged;

  @override
  State<RunRouteMapView> createState() => _RunRouteMapViewState();
}

class _DisplayPoint {
  const _DisplayPoint(this.point, this.distanceMeters);
  final RunPoint point;
  final double distanceMeters;
}

class _RunRouteMapViewState extends State<RunRouteMapView> {
  static const double _minZoom = 3;
  static const double _maxZoom = 19;
  static const double _defaultZoom = 16;
  static const double _maxMercatorLatitude = 85.05112878;

  final MapController _mapController = MapController();
  bool _mapReady = false;
  int _lastFollowLength = 0;
  late int _selectedIntervalMeters;

  @override
  void initState() {
    super.initState();
    _selectedIntervalMeters = runSegmentIntervalOptions.contains(widget.initialIntervalMeters)
        ? widget.initialIntervalMeters
        : 100;
  }

  int get _activeIntervalMeters =>
      widget.selectedIntervalMeters ?? _selectedIntervalMeters;

  @override
  void didUpdateWidget(covariant RunRouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIntervalMeters == null &&
        oldWidget.initialIntervalMeters != widget.initialIntervalMeters &&
        runSegmentIntervalOptions.contains(widget.initialIntervalMeters)) {
      _selectedIntervalMeters = widget.initialIntervalMeters;
    }
    if (widget.followLastPoint &&
        widget.route.isNotEmpty &&
        widget.route.length != _lastFollowLength) {
      _followLatestPoint();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  bool _isValidCoordinate(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -_maxMercatorLatitude &&
      latitude <= _maxMercatorLatitude &&
      longitude >= -180 &&
      longitude <= 180;

  List<RunPoint> _validRoute() {
    final List<RunPoint> result = <RunPoint>[];
    bool breakBeforeNext = false;
    for (final RunPoint point in widget.route) {
      if (!_isValidCoordinate(point.latitude, point.longitude)) {
        breakBeforeNext = true;
        continue;
      }
      final double? altitude = point.altitudeMeters;
      result.add(RunPoint(
        latitude: point.latitude,
        longitude: point.longitude,
        timestamp: point.timestamp,
        accuracyMeters: point.accuracyMeters,
        altitudeMeters: altitude != null && altitude.isFinite ? altitude : null,
        startsNewSegment: point.startsNewSegment || breakBeforeNext,
      ));
      breakBeforeNext = false;
    }
    return result;
  }

  void _followLatestPoint() {
    if (!widget.followLastPoint || widget.route.isEmpty) return;
    _lastFollowLength = widget.route.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final List<RunPoint> route = _validRoute();
      if (route.isEmpty) return;
      try {
        final double zoom = _mapController.camera.zoom;
        _mapController.move(
          LatLng(route.last.latitude, route.last.longitude),
          zoom.isFinite ? zoom.clamp(_minZoom, _maxZoom).toDouble() : _defaultZoom,
        );
      } catch (_) {
        // Kamera dapat belum siap pada frame pertama.
      }
    });
  }

  List<_DisplayPoint> _displayRoute(List<RunPoint> route) {
    if (route.length == 1) return <_DisplayPoint>[_DisplayPoint(route.first, 0)];
    // Akumulasi jarak dilakukan pada semua titik valid sebelum simplifikasi,
    // sehingga pewarnaan segmen tidak berubah hanya karena titik display dikurangi.
    final Map<RunPoint, double> cumulativeByPoint = <RunPoint, double>{};
    double cumulative = 0;
    for (int i = 0; i < route.length; i++) {
      if (i > 0 && !route[i].startsNewSegment) {
        cumulative += distanceBetweenMeters(
          latitude1: route[i - 1].latitude,
          longitude1: route[i - 1].longitude,
          latitude2: route[i].latitude,
          longitude2: route[i].longitude,
        );
      }
      cumulativeByPoint[route[i]] = cumulative;
    }

    final List<RunPoint> result = <RunPoint>[];
    int segmentStart = 0;
    for (int i = 1; i <= route.length; i++) {
      final bool isEnd = i == route.length;
      if (!isEnd && !route[i].startsNewSegment) continue;
      final List<RunPoint> segment = route.sublist(segmentStart, i);
      result.addAll(_simplifySegment(segment));
      segmentStart = i;
    }
    return result.map((RunPoint point) => _DisplayPoint(
      point,
      cumulativeByPoint[point] ?? 0,
    )).toList(growable: false);
  }

  List<RunPoint> _simplifySegment(List<RunPoint> input) {
    if (input.length <= 3) return input;
    const int maxVertices = 1200;
    List<RunPoint> points = input;
    if (points.length > maxVertices) {
      final int stride = (points.length / maxVertices).ceil();
      final List<RunPoint> sampled = <RunPoint>[points.first];
      for (int i = stride; i < points.length - 1; i += stride) {
        sampled.add(points[i]);
      }
      sampled.add(points.last);
      points = sampled;
    }

    // Iterative Douglas-Peucker in approximate local metres. This affects only
    // display polyline, not distance, splits, GPX points, or elevation source.
    final double originLat = points.first.latitude * math.pi / 180;
    final double cosLat = math.cos(originLat).abs().clamp(0.1, 1.0).toDouble();
    Offset projected(RunPoint point) => Offset(
      point.longitude * 111320 * cosLat,
      point.latitude * 110540,
    );
    final List<Offset> xy = points.map(projected).toList(growable: false);
    const double toleranceMeters = 2.8;
    final List<bool> keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    final List<(int, int)> stack = <(int, int)>[(0, points.length - 1)];
    while (stack.isNotEmpty) {
      final (int first, int last) = stack.removeLast();
      double maxDistance = 0;
      int index = -1;
      final Offset a = xy[first];
      final Offset b = xy[last];
      final Offset ab = b - a;
      final double denominator = ab.distanceSquared;
      for (int i = first + 1; i < last; i++) {
        final Offset ap = xy[i] - a;
        final double t = denominator <= 0
            ? 0
            : (ap.dx * ab.dx + ap.dy * ab.dy) / denominator;
        final Offset nearest = a + ab * t.clamp(0.0, 1.0).toDouble();
        final double distance = (xy[i] - nearest).distance;
        if (distance > maxDistance) {
          maxDistance = distance;
          index = i;
        }
      }
      if (index >= 0 && maxDistance > toleranceMeters) {
        keep[index] = true;
        stack.add((first, index));
        stack.add((index, last));
      }
    }
    final List<RunPoint> simplified = <RunPoint>[];
    for (int i = 0; i < points.length; i++) {
      if (keep[i]) simplified.add(points[i]);
    }
    return simplified;
  }

  Color _paceColor(double? pace) {
    if (pace == null || !pace.isFinite || pace <= 0) return const Color(0xFF888888);
    if (pace <= 300) return const Color(0xFF111111); // cepat
    if (pace <= 420) return const Color(0xFF444444); // sedang
    if (pace <= 600) return const Color(0xFF777777); // santai
    return const Color(0xFFBBBBBB); // pelan
  }

  List<Polyline> _coloredPolylines(List<_DisplayPoint> display, List<RunDistanceSegment> splits) {
    if (display.length < 2) return const <Polyline>[];
    final List<Polyline> result = <Polyline>[];
    List<LatLng> currentPoints = <LatLng>[
      LatLng(display.first.point.latitude, display.first.point.longitude),
    ];
    Color? currentColor;
    for (int i = 1; i < display.length; i++) {
      final _DisplayPoint previous = display[i - 1];
      final _DisplayPoint current = display[i];
      final double middleMeters = (previous.distanceMeters + current.distanceMeters) / 2;
      final RunDistanceSegment? split = _splitForDistance(splits, middleMeters);
      final Color nextColor = _paceColor(split?.paceSecondsPerKm);
      if (current.point.startsNewSegment) {
        if (currentPoints.length >= 2) {
          result.add(Polyline(points: currentPoints, strokeWidth: 4.5, color: currentColor ?? nextColor));
        }
        currentPoints = <LatLng>[LatLng(current.point.latitude, current.point.longitude)];
        currentColor = nextColor;
        continue;
      }
      if (currentPoints.isNotEmpty && currentColor != null && nextColor != currentColor) {
        currentPoints.add(LatLng(current.point.latitude, current.point.longitude));
        if (currentPoints.length >= 2) {
          result.add(Polyline(points: currentPoints, strokeWidth: 4.5, color: currentColor));
        }
        currentPoints = <LatLng>[LatLng(current.point.latitude, current.point.longitude)];
        currentColor = nextColor;
      } else {
        if (currentPoints.isEmpty) {
          currentPoints.add(LatLng(previous.point.latitude, previous.point.longitude));
        }
        currentPoints.add(LatLng(current.point.latitude, current.point.longitude));
        currentColor = nextColor;
      }
    }
    if (currentPoints.length >= 2) {
      result.add(Polyline(points: currentPoints, strokeWidth: 4.5, color: currentColor ?? const Color(0xFF111111)));
    }
    return result;
  }

  RunDistanceSegment? _splitForDistance(List<RunDistanceSegment> splits, double distance) {
    for (final RunDistanceSegment split in splits) {
      if (distance >= split.startMeters && distance <= split.endMeters) return split;
    }
    return splits.isEmpty ? null : splits.last;
  }

  @override
  Widget build(BuildContext context) {
    final List<RunPoint> validRoute = _validRoute();
    if (validRoute.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.gps_not_fixed, size: 38, color: VoltWarna.teksAbu),
                SizedBox(height: 8),
                Text('Rute akan tampil setelah beberapa titik GPS masuk.', textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );
    }

    final List<_DisplayPoint> display = _displayRoute(validRoute);
    final List<LatLng> coordinates = display.map((p) => LatLng(p.point.latitude, p.point.longitude)).toList(growable: false);
    final List<RunDistanceSegment> splits =
        buildRunDistanceSegments(widget.laps, _activeIntervalMeters);
    final List<Polyline> polylines = _coloredPolylines(display, splits);
    final LatLng center = widget.followLastPoint
        ? LatLng(validRoute.last.latitude, validRoute.last.longitude)
        : _safeFitCenter(coordinates);
    final LatLng startPoint = LatLng(validRoute.first.latitude, validRoute.first.longitude);
    final LatLng lastPoint = LatLng(validRoute.last.latitude, validRoute.last.longitude);

    final List<Marker> markers = <Marker>[
      Marker(
        point: startPoint,
        width: 22,
        height: 22,
        child: const Icon(Icons.flag_circle_rounded, color: Colors.black, size: 21),
      ),
      if (validRoute.length > 1)
        Marker(
          point: lastPoint,
          width: 22,
          height: 22,
          child: const Icon(Icons.location_on_rounded, color: Colors.black, size: 21),
        ),
      ..._splitMarkers(splits),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewportWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 0 ? constraints.maxWidth : 320;
        final double zoom = widget.followLastPoint
            ? _defaultZoom
            : _safeFitZoom(coordinates, viewportWidth, widget.height);
        return SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Stack(
              children: <Widget>[
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: zoom.isFinite ? zoom : _defaultZoom,
                    minZoom: _minZoom,
                    maxZoom: _maxZoom,
                    onTap: (TapPosition _, LatLng point) =>
                        _showNearestSplit(point, splits),
                    onMapReady: () {
                      _mapReady = true;
                      _followLatestPoint();
                    },
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.voltstride',
                      maxNativeZoom: 19,
                    ),
                    if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                    MarkerLayer(markers: markers),
                    const RichAttributionWidget(
                      attributions: <SourceAttribution>[
                        TextSourceAttribution('© OpenStreetMap contributors'),
                      ],
                    ),
                  ],
                ),
                if (widget.showIntervalSelector)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xE9222222),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(color: Colors.white24),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _activeIntervalMeters,
                          dropdownColor: const Color(0xFF222222),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          iconEnabledColor: Colors.white,
                          isDense: true,
                          items: runSegmentIntervalOptions.map((int meters) => DropdownMenuItem<int>(
                            value: meters,
                            child: Text(meters >= 1000 ? '${meters ~/ 1000} km' : '$meters m'),
                          )).toList(growable: false),
                          onChanged: (int? value) {
                            if (value == null) return;
                            if (widget.selectedIntervalMeters == null) {
                              setState(() => _selectedIntervalMeters = value);
                            }
                            widget.onIntervalMetersChanged?.call(value);
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Marker> _splitMarkers(List<RunDistanceSegment> splits) {
    if (splits.isEmpty) return const <Marker>[];

    // Pace tercepat adalah pace valid terkecil (detik/km). Label pace dibuat
    // untuk setiap segmen hasil pilihan interval, bukan dijarangkan per 500 m
    // atau 2 km seperti versi sebelumnya.
    int? fastestIndex;
    double fastestPace = double.infinity;
    for (int index = 0; index < splits.length; index++) {
      final double? pace = splits[index].paceSecondsPerKm;
      if (pace != null && pace.isFinite && pace > 0 && pace < fastestPace) {
        fastestPace = pace;
        fastestIndex = index;
      }
    }

    return <Marker>[
      for (int index = 0; index < splits.length; index++)
        _splitMarker(
          splits[index],
          isFastest: index == fastestIndex,
          labelOffset: _paceLabelOffset(index),
        ),
    ];
  }

  // Label dipindah bergantian mengelilingi titik untuk mengurangi tumpang
  // tindih ketika interval pendek. Titik GPS dan posisi segmen tidak berubah.
  Offset _paceLabelOffset(int index) {
    switch (index % 4) {
      case 0:
        return const Offset(0, -15);
      case 1:
        return const Offset(17, -3);
      case 2:
        return const Offset(0, 15);
      default:
        return const Offset(-17, -3);
    }
  }

  Marker _splitMarker(
    RunDistanceSegment split, {
    required bool isFastest,
    required Offset labelOffset,
  }) {
    final double? pace = split.paceSecondsPerKm;
    final Color paceColor = _paceColor(pace);
    final String paceText = pace == null ? '--:--' : _formatPace(pace);
    // Label terang di atas latar gelap membuat angka pace tetap terbaca
    // pada peta yang penuh detail. Pace tercepat ditandai dengan inversi warna.
    final Color labelColor = isFastest ? Colors.black : Colors.white;
    final Color labelBackground =
        isFastest ? const Color(0xFFF5F5F5) : const Color(0xEE202020);
    final Color borderColor = isFastest ? Colors.black : paceColor;

    return Marker(
      point: LatLng(split.latitude, split.longitude),
      width: 40,
      height: 20,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showSplitDetails(split),
        child: Transform.translate(
          offset: labelOffset,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: labelBackground,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: borderColor,
                width: isFastest ? 2.0 : 1.0,
              ),
              boxShadow: isFastest
                  ? const <BoxShadow>[
                      BoxShadow(color: Color(0x55828282), blurRadius: 5),
                    ]
                  : null,
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                paceText,
                maxLines: 1,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showNearestSplit(LatLng tappedPoint, List<RunDistanceSegment> splits) {
    if (splits.isEmpty) return;
    RunDistanceSegment? nearest;
    double nearestDistance = double.infinity;
    for (final RunDistanceSegment split in splits) {
      final double distance = distanceBetweenMeters(
        latitude1: tappedPoint.latitude,
        longitude1: tappedPoint.longitude,
        latitude2: split.latitude,
        longitude2: split.longitude,
      );
      if (distance.isFinite && distance < nearestDistance) {
        nearestDistance = distance;
        nearest = split;
      }
    }
    // Sentuhan yang terlalu jauh dari garis rute tidak dianggap memilih segmen.
    if (nearest != null && nearestDistance <= 90) {
      unawaited(_showSplitDetails(nearest));
    }
  }

  Future<void> _showSplitDetails(RunDistanceSegment split) async {
    final double? pace = split.paceSecondsPerKm;
    final double? speed = split.speedKmh;
    final String distanceLabel = _activeIntervalMeters >= 1000
        ? '${(split.startMeters / 1000).toStringAsFixed(2)}–'
            '${(split.endMeters / 1000).toStringAsFixed(2)} km'
        : '${split.startMeters.round()}–${split.endMeters.round()} m';
    final String altitude = split.relativeElevationMeters != null && split.relativeElevationMeters!.isFinite
        ? '${split.relativeElevationMeters! >= 0 ? '+' : ''}${split.relativeElevationMeters!.round()} m'
        : '--';
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('Segmen $distanceLabel'),
        content: Text(
          'Panjang segmen: ${split.distanceMeters.toStringAsFixed(0)} m\n'
          'Durasi: ${(split.durationMilliseconds / 1000).toStringAsFixed(1)} detik\n'
          'Pace rata-rata: ${pace == null ? '--:--' : _formatPace(pace)}/km\n'
          'Kecepatan rata-rata: ${speed == null ? '--' : speed.toStringAsFixed(1)} km/jam\n'
          'Elevasi dari awal: $altitude',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Tutup')),
        ],
      ),
    );
  }

  LatLng _safeFitCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(-7.8, 110.36);
    double minLat = points.first.latitude;
    double maxLat = minLat;
    double minLon = points.first.longitude;
    double maxLon = minLon;
    for (final LatLng p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude).toDouble();
      maxLat = math.max(maxLat, p.latitude).toDouble();
      minLon = math.min(minLon, p.longitude).toDouble();
      maxLon = math.max(maxLon, p.longitude).toDouble();
    }
    final double lat = (minLat + maxLat) / 2;
    final double lon = (minLon + maxLon) / 2;
    return lat.isFinite && lon.isFinite ? LatLng(lat, lon) : points.last;
  }

  double _safeFitZoom(List<LatLng> points, double width, double height) {
    if (points.length < 2 || !width.isFinite || !height.isFinite || width <= 0 || height <= 0) return _defaultZoom;
    double minLat = points.first.latitude;
    double maxLat = minLat;
    double minLon = points.first.longitude;
    double maxLon = minLon;
    for (final LatLng p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude).toDouble();
      maxLat = math.max(maxLat, p.latitude).toDouble();
      minLon = math.min(minLon, p.longitude).toDouble();
      maxLon = math.max(maxLon, p.longitude).toDouble();
    }
    final double latSpan = maxLat - minLat;
    final double lonSpan = maxLon - minLon;
    if (!latSpan.isFinite || !lonSpan.isFinite || (latSpan < 0.00001 && lonSpan < 0.00001)) return _defaultZoom;
    final double xSpan = math.max(lonSpan / 360, 1e-7).toDouble();
    final double ySpan = math.max((_mercatorY(maxLat) - _mercatorY(minLat)).abs(), 1e-7).toDouble();
    final double zoomX = math.log(math.max(width - 72, 1) / (256 * xSpan)) / math.ln2;
    final double zoomY = math.log(math.max(height - 72, 1) / (256 * ySpan)) / math.ln2;
    final double fit = math.min(zoomX, zoomY).toDouble();
    return fit.isFinite ? fit.clamp(_minZoom, 18.0).toDouble() : _defaultZoom;
  }

  double _mercatorY(double latitude) {
    final double safeLatitude = latitude.clamp(-_maxMercatorLatitude, _maxMercatorLatitude).toDouble();
    final double radians = safeLatitude * math.pi / 180;
    return (1 - math.log(math.tan(math.pi / 4 + radians / 2)) / math.pi) / 2;
  }

  static String _formatPace(double secondsPerKm) {
    if (!secondsPerKm.isFinite || secondsPerKm <= 0 || secondsPerKm > 3600) return '--:--';
    final int seconds = secondsPerKm.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
