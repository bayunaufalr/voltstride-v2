import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../../services/app_language_service.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';
import 'run_activity_charts.dart';
import 'run_share_page.dart';
import 'run_segment_data.dart';

class RunDetailPage extends StatefulWidget {
  const RunDetailPage({super.key, required this.session});

  final RunSession session;

  @override
  State<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends State<RunDetailPage> {
  RunSession get session => widget.session;

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  String _activityLabel(RunSession item) {
    if (item.activityType == RunActivityType.walk) return _text('Berjalan', 'Walk');
    if (item.intervalPlan != null) return _text('Lari interval', 'Interval run');
    return _text('Lari', 'Run');
  }

  String _environmentLabel(RunSession item) =>
      item.environment == RunEnvironment.outdoor
          ? _text('Luar ruangan', 'Outdoor')
          : _text('Dalam ruangan', 'Indoor');

  int _selectedIntervalMeters = 100;

  @override
  Widget build(BuildContext context) {
    final DateTime start = session.startedAt.toLocal();
    final DateTime? finish = session.finishedAt?.toLocal();
    final RunElevationStats elevation = session.elevationStats;
    final String routeActivityLabel = session.activityType == RunActivityType.walk
        ? _text('BERJALAN', 'WALK')
        : session.intervalPlan != null
            ? _text('LARI INTERVAL', 'INTERVAL RUN')
            : _text('LARI', 'RUN');

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('Detail aktivitas', 'Activity details')),
        actions: <Widget>[
          IconButton(
            tooltip: _text('Bagikan aktivitas', 'Share activity'),
            icon: const Icon(Icons.share_rounded),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => RunSharePage(session: session)),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: <Widget>[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${session.distanceText} km',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${_environmentLabel(session)} • ${_dateText(start)}', style: TextStyle(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        _heroMetric(_text('WAKTU', 'TIME'), session.elapsedText),
                        _heroMetric(_text('WAKTU GERAK', 'MOVING'), session.movingTimeText),
                        _heroMetric('PACE', '${session.averagePaceText}/km'),
                      ],
                    ),
                    if (finish != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _text('Selesai ${_dateText(finish)}', 'Finished ${_dateText(finish)}'),
                        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (session.environment == RunEnvironment.outdoor) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        _text('PETA RUTE $routeActivityLabel • TITIK KECEPATAN', 'ROUTE MAP $routeActivityLabel • PACE POINTS'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: RunRouteMapView(
                        route: session.route,
                        laps: session.hundredMeterLaps,
                        height: 300,
                        showIntervalSelector: true,
                        selectedIntervalMeters: _selectedIntervalMeters,
                        onIntervalMetersChanged: (int meters) {
                          setState(() => _selectedIntervalMeters = meters);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _text('Pilih rentang split di peta. Garis berwarna mengikuti pace; ketuk titik untuk melihat detail segmen. Peta dasar memerlukan internet.', 'Choose a split interval on the map. Line colours represent pace; tap a point to inspect a segment. The base map requires internet access.'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.directions_run_rounded, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_text('Sesi dalam ruangan. Jarak dicatat dari nilai yang dimasukkan saat selesai; peta dan elevasi GPS tidak tersedia.', 'Indoor session. Distance comes from the value entered at the end; GPS maps and elevation are unavailable.'))),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _elevationCard(elevation),
            const SizedBox(height: 12),
            _sectionCard(
              title: _text('LANGKAH, CADENCE, DAN KALORI', 'STEPS, CADENCE, AND CALORIES'),
              child: Column(
                children: <Widget>[
                  _dataRow(_text('Jumlah langkah', 'Steps'), session.totalSteps?.toString() ?? _text('Tidak tersedia', 'Unavailable')),
                  _dataRow(_text('Cadence rata-rata', 'Average cadence'), session.averageCadenceSpm == null ? _text('Tidak tersedia', 'Unavailable') : '${session.averageCadenceSpm!.round()} langkah/menit'),
                  _dataRow(_text('Cadence maksimum', 'Maximum cadence'), session.maxCadenceSpm == null ? _text('Tidak tersedia', 'Unavailable') : '${session.maxCadenceSpm!.round()} langkah/menit'),
                  _dataRow(_text('Kalori terbakar (perkiraan)', 'Estimated calories'), '${session.estimatedCalories.round()} kcal'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _ChartsTitle(),
            RunActivityCharts(session: session),
            const SizedBox(height: 12),
            _sectionCard(
              title: _text('DATA SESI', 'SESSION DATA'),
              child: Column(
                children: <Widget>[
                  _dataRow(_text('Jenis aktivitas', 'Activity type'), _activityLabel(session)),
                  _dataRow(_text('Lokasi', 'Location'), _environmentLabel(session)),
                  _dataRow(_text('Jarak', 'Distance'), '${session.distanceMeters.toStringAsFixed(0)} m'),
                  _dataRow(_text('Waktu total', 'Elapsed time'), session.elapsedText),
                  _dataRow(_text('Waktu bergerak', 'Moving time'), session.movingTimeText),
                  _dataRow(_text('Pace rata-rata', 'Average pace'), '${session.averagePaceText}/km'),
                  _dataRow(_text('Pace saat disimpan', 'Pace at save'), session.currentPaceText),
                  _dataRow(_text('Akurasi GPS terakhir', 'Last GPS accuracy'), session.gpsAccuracyText),
                  _dataRow(_text('Titik diterima', 'Accepted GPS points'), '${session.acceptedPoints}'),
                  _dataRow(_text('Titik ditolak', 'Rejected GPS points'), '${session.rejectedPoints}'),
                  if (session.intervalPlan != null)
                    _dataRow(
                      _text('Rencana interval', 'Interval plan'),
                      session.intervalPlan!.measure == IntervalMeasure.time
                          ? '${session.intervalPlan!.workSeconds}s kerja / '
                              '${session.intervalPlan!.recoverySeconds}s pulih × '
                              '${session.intervalPlan!.repetitions}'
                          : '${session.intervalPlan!.workDistanceMeters.round()} m kerja / '
                              '${session.intervalPlan!.recoveryDistanceMeters.round()} m pulih × '
                              '${session.intervalPlan!.repetitions}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _segmentDetailsCard(),
            const SizedBox(height: 12),
            _sectionCard(
              title: _text('SPLIT PER KM', 'SPLITS PER KM'),
              child: session.splits.isEmpty
                  ? Text(_text('Belum mencapai satu kilometer penuh.', 'No full kilometre completed yet.'))
                  : Column(
                      children: session.splits.map((RunSplit split) => _dataRow(
                        'KM ${split.kilometer}',
                        '${split.durationSeconds} ${_text('dtk', 's')} • ${split.paceText}',
                      )).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _segmentDetailsCard() {
    final List<RunDistanceSegment> segments = buildRunDistanceSegments(
      session.hundredMeterLaps,
      _selectedIntervalMeters,
    );
    return _sectionCard(
      title: _text('KECEPATAN PER SEGMEN', 'PACE BY SEGMENT'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _text('Panjang segmen', 'Segment length'),
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 12,
                  ),
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedIntervalMeters,
                  isDense: true,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  items: runSegmentIntervalOptions.map((int meters) {
                    final String label = meters >= 1000
                        ? '${meters ~/ 1000} km'
                        : '$meters m';
                    return DropdownMenuItem<int>(
                      value: meters,
                      child: Text(label),
                    );
                  }).toList(growable: false),
                  onChanged: (int? meters) {
                    if (meters == null || meters == _selectedIntervalMeters) {
                      return;
                    }
                    setState(() => _selectedIntervalMeters = meters);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (segments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(_text('Belum ada segmen jarak yang cukup untuk ditampilkan.', 'Not enough distance segments to display yet.')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 520,
                child: Column(
                  children: <Widget>[
                    _segmentTableRow(
                      segmentLabel: _text('Rentang', 'Range'),
                      durationLabel: _text('Waktu', 'Time'),
                      speedLabel: 'km/jam',
                      paceLabel: 'Pace',
                      altitudeLabel: _text('Elev. relatif', 'Rel. elev.'),
                      header: true,
                    ),
                    const Divider(height: 14),
                    ...segments.map((RunDistanceSegment segment) {
                      return _segmentTableRow(
                        segmentLabel: _formatSegmentRange(segment),
                        durationLabel: '${segment.durationSeconds.toStringAsFixed(1)} dtk',
                        speedLabel: segment.speedKmh == null
                            ? '--'
                            : segment.speedKmh!.toStringAsFixed(1),
                        paceLabel: segment.paceSecondsPerKm == null
                            ? '--:--'
                            : '${_formatPace(segment.paceSecondsPerKm!)}/km',
                        altitudeLabel: segment.relativeElevationMeters == null
                            ? '--'
                            : '${segment.relativeElevationMeters! >= 0 ? '+' : ''}${segment.relativeElevationMeters!.round()} m',
                      );
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            _text('Waktu dan pace adalah rata-rata segmen; elevasi memakai data GPS.', 'Time and pace are segment averages; elevation uses GPS data.'),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).hintColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segmentTableRow({
    required String segmentLabel,
    required String durationLabel,
    required String speedLabel,
    required String paceLabel,
    required String altitudeLabel,
    bool header = false,
  }) {
    final TextStyle style = TextStyle(
      color: header ? Theme.of(context).hintColor : null,
      fontSize: header ? 11 : 12,
      fontWeight: header ? FontWeight.w700 : FontWeight.w500,
    );
    Widget cell(String text, double width, {TextAlign align = TextAlign.start}) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: header ? 2 : 7),
          child: Text(
            text,
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      );
    }

    return Row(
      children: <Widget>[
        cell(segmentLabel, 122),
        cell(durationLabel, 86, align: TextAlign.end),
        cell(speedLabel, 78, align: TextAlign.end),
        cell(paceLabel, 104, align: TextAlign.end),
        cell(altitudeLabel, 80, align: TextAlign.end),
      ],
    );
  }

  String _formatSegmentRange(RunDistanceSegment segment) {
    if (_selectedIntervalMeters >= 1000) {
      return '${(segment.startMeters / 1000).toStringAsFixed(2)}–'
          '${(segment.endMeters / 1000).toStringAsFixed(2)} km';
    }
    return '${segment.startMeters.round()}–${segment.endMeters.round()} m';
  }

  Widget _elevationCard(RunElevationStats stats) {
    return _sectionCard(
      title: _text('ELEVASI', 'ELEVATION'),
      child: !stats.hasAltitudeData
          ? Text(_text('Data elevasi GPS tidak tersedia.', 'GPS elevation data is unavailable.'))
          : Row(
              children: <Widget>[
                _heroMetric(
                  _text('ELEVASI +', 'ASCENT'),
                  '+${stats.totalAscentMeters.round()} m',
                ),
                _heroMetric(
                  _text('ELEVASI −', 'DESCENT'),
                  '−${stats.totalDescentMeters.round()} m',
                ),
              ],
            ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _dataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: TextStyle(color: Theme.of(context).hintColor))),
          const SizedBox(width: 10),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _heroMetric(String label, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).hintColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  static String _dateText(DateTime value) =>
      '${_twoDigits(value.day)}/${_twoDigits(value.month)}/${value.year} '
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  static String _formatPace(double secondsPerKm) {
    final int seconds = secondsPerKm.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
class _ChartsTitle extends StatelessWidget {
  const _ChartsTitle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
    child: Text(
      AppLanguageService.text(context, 'GRAFIK AKTIVITAS', 'ACTIVITY CHARTS'),
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
    ),
  );
}

