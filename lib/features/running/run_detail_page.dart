import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';
import 'run_activity_charts.dart';
import 'run_share_page.dart';
import 'run_segment_data.dart';
import 'services/run_evaluation.dart';

class RunDetailPage extends StatefulWidget {
  const RunDetailPage({super.key, required this.session});

  final RunSession session;

  @override
  State<RunDetailPage> createState() => _RunDetailPageState();
}

class _RunDetailPageState extends State<RunDetailPage> {
  RunSession get session => widget.session;

  int _selectedIntervalMeters = 100;

  @override
  Widget build(BuildContext context) {
    final DateTime start = session.startedAt.toLocal();
    final DateTime? finish = session.finishedAt?.toLocal();
    final RunElevationStats elevation = session.elevationStats;
    final RunEvaluation evaluation = evaluateRun(session);
    final String routeActivityLabel = session.activityType == RunActivityType.walk
        ? 'BERJALAN'
        : session.intervalPlan != null
            ? 'LARI INTERVAL'
            : 'LARI';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail aktivitas'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Bagikan aktivitas',
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
                    Text('${session.environment.label} • ${_dateText(start)}', style: TextStyle(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        _heroMetric('WAKTU', session.elapsedText),
                        _heroMetric('MOVING', session.movingTimeText),
                        _heroMetric('PACE', '${session.averagePaceText}/km'),
                      ],
                    ),
                    if (finish != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        'Selesai ${_dateText(finish)}',
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
                        'PETA RUTE $routeActivityLabel • TITIK KECEPATAN',
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
                        'Pilih rentang split di peta. Garis berwarna mengikuti pace; ketuk titik untuk melihat detail segmen. Peta dasar memerlukan internet.',
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
                      Icon(Icons.directions_run_rounded, color: VoltWarna.aksen),
                      const SizedBox(width: 12),
                      Expanded(child: Text('Sesi dalam ruangan. Jarak dicatat dari nilai yang dimasukkan saat selesai; peta dan elevasi GPS tidak tersedia.')),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _elevationCard(elevation),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'LANGKAH, CADENCE, DAN KALORI',
              child: Column(
                children: <Widget>[
                  _dataRow('Jumlah langkah', session.totalSteps?.toString() ?? 'Tidak tersedia'),
                  _dataRow('Cadence rata-rata', session.averageCadenceSpm == null ? 'Tidak tersedia' : '${session.averageCadenceSpm!.round()} langkah/menit'),
                  _dataRow('Cadence maksimum', session.maxCadenceSpm == null ? 'Tidak tersedia' : '${session.maxCadenceSpm!.round()} langkah/menit'),
                  _dataRow('Kalori terbakar (perkiraan)', '${session.estimatedCalories.round()} kcal'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _ChartsTitle(),
            RunActivityCharts(session: session),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'DATA SESI',
              child: Column(
                children: <Widget>[
                  _dataRow('Jenis aktivitas', session.displayLabel),
                  _dataRow('Lokasi', session.environment.label),
                  _dataRow('Jarak', '${session.distanceMeters.toStringAsFixed(0)} m'),
                  _dataRow('Waktu total', session.elapsedText),
                  _dataRow('Waktu bergerak', session.movingTimeText),
                  _dataRow('Pace rata-rata', '${session.averagePaceText}/km'),
                  _dataRow('Pace saat disimpan', session.currentPaceText),
                  _dataRow('Akurasi GPS terakhir', session.gpsAccuracyText),
                  _dataRow('Titik diterima', '${session.acceptedPoints}'),
                  _dataRow('Titik ditolak', '${session.rejectedPoints}'),
                  if (session.intervalPlan != null)
                    _dataRow(
                      'Rencana interval',
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
              title: 'SPLIT PER KM',
              child: session.splits.isEmpty
                  ? const Text('Belum mencapai satu kilometer penuh.')
                  : Column(
                      children: session.splits.map((RunSplit split) => _dataRow(
                        'KM ${split.kilometer}',
                        '${split.durationSeconds} dtk • ${split.paceText}',
                      )).toList(growable: false),
                    ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'EVALUASI DAN SARAN',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('PENGAMATAN', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  ...evaluation.observations.map((String item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          const Text('•  '),
                          Expanded(child: Text(item)),
                        ]),
                      )),
                  const SizedBox(height: 8),
                  const Text('SARAN', style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  ...evaluation.recommendations.map((String item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Icon(Icons.arrow_right, size: 18, color: VoltWarna.aksen),
                          Expanded(child: Text(item)),
                        ]),
                      )),
                ],
              ),
            ),
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
      title: 'KECEPATAN PER SEGMEN',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Panjang segmen',
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('Belum ada segmen jarak yang cukup untuk ditampilkan.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 520,
                child: Column(
                  children: <Widget>[
                    _segmentTableRow(
                      segmentLabel: 'Rentang',
                      durationLabel: 'Waktu',
                      speedLabel: 'km/jam',
                      paceLabel: 'Pace',
                      altitudeLabel: 'Elev. relatif',
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
            'Waktu dan pace adalah rata-rata segmen; elevasi memakai data GPS.',
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
      title: 'ELEVASI',
      child: !stats.hasAltitudeData
          ? const Text('Data elevasi GPS tidak tersedia.')
          : Row(
              children: <Widget>[
                _heroMetric(
                  'ELEVASI +',
                  '+${stats.totalAscentMeters.round()} m',
                ),
                _heroMetric(
                  'ELEVASI −',
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
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
    child: Text('GRAFIK AKTIVITAS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
  );
}

