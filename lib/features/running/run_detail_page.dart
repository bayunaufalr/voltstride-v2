import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';
import 'services/run_evaluation.dart';

class RunDetailPage extends StatelessWidget {
  const RunDetailPage({super.key, required this.session});

  final RunSession session;

  @override
  Widget build(BuildContext context) {
    final DateTime start = session.startedAt.toLocal();
    final DateTime? finish = session.finishedAt?.toLocal();
    final RunElevationStats elevation = session.elevationStats;
    final RunEvaluation evaluation = evaluateRun(session);

    return Scaffold(
      appBar: AppBar(title: const Text('Detail Lari')),
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
                    Text(_dateText(start), style: const TextStyle(color: VoltWarna.teksAbu)),
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
                        style: const TextStyle(fontSize: 12, color: VoltWarna.teksAbu),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('PETA DAN TITIK KECEPATAN', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: RunRouteMapView(
                      route: session.route,
                      laps: session.hundredMeterLaps,
                      height: 300,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Ketuk penanda 100 m di peta untuk membuka kecepatan, pace, dan elevasi titik tersebut. Peta dasar memerlukan internet.',
                      style: TextStyle(fontSize: 11, color: VoltWarna.teksAbu),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _elevationCard(elevation),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'DATA SESI',
              child: Column(
                children: <Widget>[
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
                      '${session.intervalPlan!.workSeconds}s kerja / '
                      '${session.intervalPlan!.recoverySeconds}s pulih × '
                      '${session.intervalPlan!.repetitions}',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _sectionCard(
              title: 'KECEPATAN PER 100 METER',
              child: session.hundredMeterLaps.isEmpty
                  ? const Text('Belum ada segmen 100 meter lengkap.')
                  : Column(
                      children: <Widget>[
                        const Row(
                          children: <Widget>[
                            Expanded(flex: 2, child: Text('Jarak', style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
                            Expanded(flex: 2, child: Text('Waktu', textAlign: TextAlign.end, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
                            Expanded(flex: 2, child: Text('km/jam', textAlign: TextAlign.end, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
                            Expanded(flex: 2, child: Text('Pace', textAlign: TextAlign.end, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
                            Expanded(flex: 2, child: Text('Elevasi', textAlign: TextAlign.end, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
                          ],
                        ),
                        const Divider(),
                        ...session.hundredMeterLaps.map((RunLap100m lap) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: <Widget>[
                                  Expanded(flex: 2, child: Text('${lap.distanceMeters.round()} m')),
                                  Expanded(flex: 2, child: Text('${lap.durationSeconds.toStringAsFixed(1)} dtk', textAlign: TextAlign.end)),
                                  Expanded(flex: 2, child: Text(lap.speedKmh == null ? '--' : lap.speedKmh!.toStringAsFixed(1), textAlign: TextAlign.end)),
                                  Expanded(flex: 2, child: Text(lap.paceSecondsPerKm == null ? '--' : _formatPace(lap.paceSecondsPerKm!), textAlign: TextAlign.end)),
                                  Expanded(flex: 2, child: Text(lap.altitudeMeters == null ? '--' : '${lap.altitudeMeters!.round()} m', textAlign: TextAlign.end)),
                                ],
                              ),
                            )),
                      ],
                    ),
            ),
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
              title: 'EVALUASI AKHIR: ${evaluation.title.toUpperCase()}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(evaluation.overview),
                  const SizedBox(height: 10),
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
                          const Icon(Icons.arrow_right, size: 18, color: VoltWarna.aksen),
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

  Widget _elevationCard(RunElevationStats stats) {
    String signed(double value) => '${value > 0 ? '+' : ''}${value.toStringAsFixed(0)} m';
    String metres(double value) => '${value.toStringAsFixed(0)} m';
    return _sectionCard(
      title: 'ELEVASI GPS',
      child: !stats.hasAltitudeData
          ? const Text('Data elevasi tidak tersimpan untuk sesi ini.')
          : Column(
              children: <Widget>[
                Row(children: <Widget>[
                  _heroMetric('NAIK TOTAL', metres(stats.totalAscentMeters)),
                  _heroMetric('TURUN TOTAL', metres(stats.totalDescentMeters)),
                ]),
                const SizedBox(height: 10),
                Row(children: <Widget>[
                  _heroMetric('ELEVASI BERSIH', signed(stats.netChangeMeters)),
                  _heroMetric('KENAIKAN MAX', signed(stats.maxAboveStartMeters)),
                ]),
                const SizedBox(height: 8),
                const Text('Bersih = naik total dikurangi turun total. Kenaikan max adalah titik tertinggi relatif ke start. Nilai berasal dari GPS dan bersifat perkiraan.', style: TextStyle(fontSize: 11, color: VoltWarna.teksAbu)),
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
          Expanded(child: Text(label, style: const TextStyle(color: VoltWarna.teksAbu))),
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
            Text(label, style: const TextStyle(fontSize: 10, color: VoltWarna.teksAbu)),
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
