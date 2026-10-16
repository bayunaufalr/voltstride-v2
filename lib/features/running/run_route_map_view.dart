import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'models/run_session.dart';
import '../../theme/volt_theme.dart';

/// Peta rute yang dapat dipakai saat berlari, di hasil, maupun di riwayat.
class RunRouteMapView extends StatefulWidget {
  const RunRouteMapView({
    super.key,
    required this.route,
    required this.laps,
    this.height = 280,
    this.followLastPoint = false,
  });

  final List<RunPoint> route;
  final List<RunLap100m> laps;
  final double height;
  final bool followLastPoint;

  @override
  State<RunRouteMapView> createState() => _RunRouteMapViewState();
}

class _RunRouteMapViewState extends State<RunRouteMapView> {
  static const double _minZoom = 3;
  static const double _maxZoom = 19;
  static const double _defaultZoom = 16;
  static const double _maxMercatorLatitude = 85.05112878;

  final MapController _mapController = MapController();
  bool _mapReady = false;
  int _lastFollowLength = 0;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RunRouteMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.followLastPoint &&
        widget.route.isNotEmpty &&
        widget.route.length != _lastFollowLength) {
      _followLatestPoint();
    }
  }

  bool _isValidCoordinate(double latitude, double longitude) {
    return latitude.isFinite &&
        longitude.isFinite &&
        latitude >= -_maxMercatorLatitude &&
        latitude <= _maxMercatorLatitude &&
        longitude >= -180 &&
        longitude <= 180;
  }

  List<RunPoint> _validRoute() {
    // Fast path: normal sessions should not allocate a second copy of every
    // GPS point on each rebuild while the live map is following the runner.
    final bool allPointsValid = widget.route.every(
      (RunPoint point) =>
          _isValidCoordinate(point.latitude, point.longitude) &&
          (point.altitudeMeters == null || point.altitudeMeters!.isFinite),
    );
    if (allPointsValid) return widget.route;

    final List<RunPoint> valid = <RunPoint>[];
    bool breakBeforeNext = false;

    for (final RunPoint point in widget.route) {
      if (!_isValidCoordinate(point.latitude, point.longitude)) {
        // Do not draw a straight line across a corrupt/missing GPS position.
        breakBeforeNext = true;
        continue;
      }

      final double? altitude = point.altitudeMeters;
      valid.add(
        RunPoint(
          latitude: point.latitude,
          longitude: point.longitude,
          timestamp: point.timestamp,
          accuracyMeters: point.accuracyMeters,
          altitudeMeters: altitude != null && altitude.isFinite
              ? altitude
              : null,
          startsNewSegment: point.startsNewSegment || breakBeforeNext,
        ),
      );
      breakBeforeNext = false;
    }

    return valid;
  }

  void _followLatestPoint() {
    if (!widget.followLastPoint || widget.route.isEmpty) return;
    _lastFollowLength = widget.route.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady) return;
      final List<RunPoint> route = _validRoute();
      if (route.isEmpty) return;

      final RunPoint point = route.last;
      try {
        final double currentZoom = _mapController.camera.zoom;
        final double safeZoom = currentZoom.isFinite
            ? currentZoom.clamp(_minZoom, _maxZoom).toDouble()
            : _defaultZoom;
        _mapController.move(
          LatLng(point.latitude, point.longitude),
          safeZoom,
        );
      } catch (_) {
        // Peta dapat belum selesai memasang camera saat frame pertama.
      }
    });
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
                Text(
                  'Belum ada titik GPS yang valid untuk menggambar rute.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Keep the exact GPS data in storage, but cap rendered vertices so long
    // activities do not rebuild thousands of map vertices on every update.
    final List<RunPoint> displayRoute = _routeForRendering(validRoute);
    final List<LatLng> displayCoordinates = displayRoute
        .map((RunPoint point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final LatLng startCoordinate = LatLng(
      validRoute.first.latitude,
      validRoute.first.longitude,
    );
    final LatLng lastCoordinate = LatLng(
      validRoute.last.latitude,
      validRoute.last.longitude,
    );

    final List<List<LatLng>> groups = <List<LatLng>>[];
    for (int i = 0; i < displayRoute.length; i++) {
      final RunPoint point = displayRoute[i];
      if (groups.isEmpty || point.startsNewSegment) {
        groups.add(<LatLng>[]);
      }
      groups.last.add(displayCoordinates[i]);
    }
    final List<Polyline> polylines = groups
        .where((List<LatLng> points) => points.length >= 2)
        .map(
          (List<LatLng> points) => Polyline(
            points: points,
            strokeWidth: 4.5,
            color: VoltWarna.aksen,
          ),
        )
        .toList(growable: false);

    final List<RunLap100m> validLaps = widget.laps
        .where(
          (RunLap100m lap) =>
              _isValidCoordinate(lap.latitude, lap.longitude) &&
              lap.distanceMeters.isFinite &&
              lap.distanceMeters >= 0,
        )
        .toList(growable: false);
    final List<Marker> markers = <Marker>[
      Marker(
        point: startCoordinate,
        width: 30,
        height: 30,
        child: const Icon(Icons.flag_circle, color: Colors.green, size: 28),
      ),
      if (validRoute.length > 1)
        Marker(
          point: lastCoordinate,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        ),
      ...validLaps.map(_lapMarker),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewportWidth = constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320;
        final LatLng center = widget.followLastPoint
            ? lastCoordinate
            : _safeFitCenter(displayCoordinates);
        final double initialZoom = widget.followLastPoint
            ? _defaultZoom
            : _safeFitZoom(
                displayCoordinates,
                viewportWidth,
                widget.height,
              );

        // Do not pass CameraFit.bounds to flutter_map. A route whose GPS
        // points are identical (common for very short/failed GPS sessions)
        // can produce an infinite/NaN fitted zoom, which crashes TileLayer.
        // The finite zoom below safely fits normal tracks and falls back to 16
        // for degenerate coordinates.
        final MapOptions mapOptions = MapOptions(
          initialCenter: center,
          initialZoom: initialZoom,
          minZoom: _minZoom,
          maxZoom: _maxZoom,
          onMapReady: () {
            _mapReady = true;
            _followLatestPoint();
          },
        );

        return SizedBox(
          height: widget.height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: mapOptions,
              children: <Widget>[
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.voltstride',
                  maxNativeZoom: 19,
                ),
                if (polylines.isNotEmpty)
                  PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  LatLng _safeFitCenter(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(-7.8, 110.36);

    double minLatitude = points.first.latitude;
    double maxLatitude = points.first.latitude;
    double minLongitude = points.first.longitude;
    double maxLongitude = points.first.longitude;

    for (final LatLng point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude).toDouble();
      maxLatitude = math.max(maxLatitude, point.latitude).toDouble();
      minLongitude = math.min(minLongitude, point.longitude).toDouble();
      maxLongitude = math.max(maxLongitude, point.longitude).toDouble();
    }

    final double latitude = (minLatitude + maxLatitude) / 2;
    final double longitude = (minLongitude + maxLongitude) / 2;
    if (!latitude.isFinite || !longitude.isFinite) {
      return points.last;
    }
    return LatLng(latitude, longitude);
  }

  double _safeFitZoom(
    List<LatLng> points,
    double viewportWidth,
    double viewportHeight,
  ) {
    if (points.length < 2 ||
        !viewportWidth.isFinite ||
        !viewportHeight.isFinite ||
        viewportWidth <= 0 ||
        viewportHeight <= 0) {
      return _defaultZoom;
    }

    double minLatitude = points.first.latitude;
    double maxLatitude = points.first.latitude;
    double minLongitude = points.first.longitude;
    double maxLongitude = points.first.longitude;

    for (final LatLng point in points.skip(1)) {
      minLatitude = math.min(minLatitude, point.latitude).toDouble();
      maxLatitude = math.max(maxLatitude, point.latitude).toDouble();
      minLongitude = math.min(minLongitude, point.longitude).toDouble();
      maxLongitude = math.max(maxLongitude, point.longitude).toDouble();
    }

    final double latitudeSpan = maxLatitude - minLatitude;
    final double longitudeSpan = maxLongitude - minLongitude;
    if (!latitudeSpan.isFinite ||
        !longitudeSpan.isFinite ||
        (latitudeSpan < 0.00001 && longitudeSpan < 0.00001)) {
      return _defaultZoom;
    }

    final double xSpan = math.max(longitudeSpan / 360, 1e-7).toDouble();
    final double topY = _mercatorY(maxLatitude);
    final double bottomY = _mercatorY(minLatitude);
    final double ySpan = math.max((bottomY - topY).abs(), 1e-7).toDouble();
    final double availableWidth = math.max(viewportWidth - 72, 1.0).toDouble();
    final double availableHeight = math.max(viewportHeight - 72, 1.0).toDouble();
    final double zoomX = math.log(availableWidth / (256 * xSpan)) / math.ln2;
    final double zoomY = math.log(availableHeight / (256 * ySpan)) / math.ln2;
    final double fitZoom = math.min(zoomX, zoomY).toDouble();

    if (!fitZoom.isFinite) return _defaultZoom;
    return fitZoom.clamp(_minZoom, 18.0).toDouble();
  }

  double _mercatorY(double latitude) {
    final double safeLatitude = latitude
        .clamp(-_maxMercatorLatitude, _maxMercatorLatitude)
        .toDouble();
    final double radians = safeLatitude * math.pi / 180;
    return (1 - math.log(math.tan(math.pi / 4 + radians / 2)) / math.pi) / 2;
  }

  List<RunPoint> _routeForRendering(List<RunPoint> route) {
    const int maxRenderedPoints = 1200;
    if (route.length <= maxRenderedPoints) return route;

    final int stride = (route.length / maxRenderedPoints).ceil();
    final List<RunPoint> result = <RunPoint>[];
    int segmentStart = 0;

    void appendSegment(int start, int end) {
      if (start > end || start < 0 || end >= route.length) return;
      result.add(route[start]);
      for (int index = start + stride; index < end; index += stride) {
        result.add(route[index]);
      }
      if (end > start) result.add(route[end]);
    }

    for (int index = 1; index <= route.length; index++) {
      final bool isEnd = index == route.length;
      final bool startsNewSegment = !isEnd && route[index].startsNewSegment;
      if (isEnd || startsNewSegment) {
        appendSegment(segmentStart, index - 1);
        segmentStart = index;
      }
    }

    return result;
  }

  Marker _lapMarker(RunLap100m lap) {
    final double? speedKmh = lap.speedKmh;
    final double? altitudeMeters = lap.altitudeMeters;
    final String speed = speedKmh != null && speedKmh.isFinite
        ? '${speedKmh.toStringAsFixed(1)} km/h'
        : '-- km/h';
    final String altitude = altitudeMeters == null || !altitudeMeters.isFinite
        ? 'alt --'
        : '${altitudeMeters.round()} m alt';
    return Marker(
      point: LatLng(lap.latitude, lap.longitude),
      width: 76,
      height: 56,
      child: GestureDetector(
        onTap: () => _showLapDetails(lap),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
          decoration: BoxDecoration(
            color: VoltWarna.kartu,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: VoltWarna.aksen, width: 1.5),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Colors.black26, blurRadius: 3),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${lap.distanceMeters.round()} m',
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(speed, style: const TextStyle(fontSize: 8)),
              Text(altitude, style: const TextStyle(fontSize: 7)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLapDetails(RunLap100m lap) async {
    final double? speedKmh = lap.speedKmh;
    final double? paceSecondsPerKm = lap.paceSecondsPerKm;
    final double? altitudeMeters = lap.altitudeMeters;
    final String speed = speedKmh != null && speedKmh.isFinite
        ? '${speedKmh.toStringAsFixed(2)} km/jam'
        : '--';
    final String pace = paceSecondsPerKm != null &&
            paceSecondsPerKm.isFinite
        ? _formatPace(paceSecondsPerKm)
        : '--';
    final String altitude = altitudeMeters == null || !altitudeMeters.isFinite
        ? 'Tidak tersedia'
        : '${altitudeMeters.toStringAsFixed(1)} m di atas permukaan laut';
    final double? startAltitude = widget.route.isNotEmpty
        ? widget.route.first.altitudeMeters
        : null;
    final double? riseFromStart = startAltitude != null &&
            startAltitude.isFinite &&
            altitudeMeters != null &&
            altitudeMeters.isFinite
        ? altitudeMeters - startAltitude
        : null;
    final String riseText = riseFromStart == null
        ? 'Tidak tersedia'
        : '${riseFromStart >= 0 ? '+' : ''}'
            '${riseFromStart.toStringAsFixed(1)} m';

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('Titik ${lap.distanceMeters.round()} meter'),
        content: Text(
          'Waktu segmen 100 m: ${lap.durationSeconds.toStringAsFixed(1)} detik\n'
          'Kecepatan rata-rata: $speed\n'
          'Pace ekuivalen: $pace/km\n'
          'Elevasi titik: $altitude\n'
          'Perubahan dari titik awal: $riseText\n\n'
          'Kecepatan dan elevasi adalah perkiraan dari data GPS.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  static String _formatPace(double secondsPerKm) {
    if (!secondsPerKm.isFinite || secondsPerKm <= 0 || secondsPerKm > 3600) {
      return '--:--';
    }
    final int seconds = secondsPerKm.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
