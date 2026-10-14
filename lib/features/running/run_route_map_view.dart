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

  void _followLatestPoint() {
    if (!widget.followLastPoint || widget.route.isEmpty) return;
    _lastFollowLength = widget.route.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || widget.route.isEmpty) return;
      final RunPoint point = widget.route.last;
      try {
        _mapController.move(
          LatLng(point.latitude, point.longitude),
          _mapController.camera.zoom,
        );
      } catch (_) {
        // Map mungkin belum siap diinisialisasi oleh flutter_map.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.route.isEmpty) {
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
                  'Menunggu titik GPS yang valid untuk menggambar rute.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final List<LatLng> coordinates = widget.route
        .map((RunPoint point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final LatLng center = coordinates.last;
    final List<List<LatLng>> groups = <List<LatLng>>[];
    for (int i = 0; i < widget.route.length; i++) {
      final RunPoint point = widget.route[i];
      if (groups.isEmpty || point.startsNewSegment) {
        groups.add(<LatLng>[]);
      }
      groups.last.add(coordinates[i]);
    }
    final List<Polyline> polylines = groups
        .where((List<LatLng> points) => points.length >= 2)
        .map((List<LatLng> points) => Polyline(
              points: points,
              strokeWidth: 4.5,
              color: VoltWarna.aksen,
            ))
        .toList(growable: false);

    final List<Marker> markers = <Marker>[
      Marker(
        point: coordinates.first,
        width: 30,
        height: 30,
        child: const Icon(Icons.flag_circle, color: Colors.green, size: 28),
      ),
      if (coordinates.length > 1)
        Marker(
          point: coordinates.last,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        ),
      ...widget.laps.map(_lapMarker),
    ];

    final MapOptions mapOptions = MapOptions(
      initialCenter: center,
      initialZoom: 16,
      initialCameraFit: !widget.followLastPoint && coordinates.length >= 2
          ? CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(coordinates),
              padding: const EdgeInsets.all(36),
            )
          : null,
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
                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const <String>['a', 'b', 'c', 'd'],
              userAgentPackageName: 'com.example.voltstride',
            ),
            if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: <SourceAttribution>[
                TextSourceAttribution('© OpenStreetMap contributors © CARTO'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Marker _lapMarker(RunLap100m lap) {
    final String speed = lap.speedKmh != null && lap.speedKmh!.isFinite
        ? '${lap.speedKmh!.toStringAsFixed(1)} km/h'
        : '-- km/h';
    final String altitude = lap.altitudeMeters == null
        ? 'alt --'
        : '${lap.altitudeMeters!.round()} m alt';
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
    final String speed = lap.speedKmh != null
        ? '${lap.speedKmh!.toStringAsFixed(2)} km/jam'
        : '--';
    final String pace = lap.paceSecondsPerKm != null
        ? _formatPace(lap.paceSecondsPerKm!)
        : '--';
    final String altitude = lap.altitudeMeters == null
        ? 'Tidak tersedia'
        : '${lap.altitudeMeters!.toStringAsFixed(1)} m di atas permukaan laut';
    final double? startAltitude = widget.route.isNotEmpty
        ? widget.route.first.altitudeMeters
        : null;
    final double? riseFromStart = startAltitude != null &&
            lap.altitudeMeters != null
        ? lap.altitudeMeters! - startAltitude
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
