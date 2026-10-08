import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'running_controller.dart';

/// Halaman lari V2.
///
/// Untuk sprint pertama ini kita sengaja fokus pada satu hal:
/// start -> dapat GPS -> live metrics -> pause/resume -> finish -> summary.
/// Map dan penyimpanan lokal akan masuk sprint berikutnya setelah engine
/// benar-benar stabil.
class RunningPage extends StatefulWidget {
  const RunningPage({super.key});

  @override
  State<RunningPage> createState() => _RunningPageState();
}

class _RunningPageState extends State<RunningPage> {
  late final RunningController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RunningController();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_controller.status) {
      case RunStatus.idle:
        return _buildIdle();
      case RunStatus.acquiringGps:
        return _buildAcquiringGps();
      case RunStatus.running:
        return _buildLiveRun(paused: false);
      case RunStatus.paused:
        return _buildLiveRun(paused: true);
      case RunStatus.finished:
        return _buildSummary(
          _controller.lastFinishedSession,
        );
      case RunStatus.error:
        return _buildError();
    }
  }

  Widget _buildIdle() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoltStride Run'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _heroCard(),
            const SizedBox(height: 16),
            _infoCard(
              icon: Icons.gps_fixed,
              title: 'GPS real-time',
              text:
                  'VoltStride menyaring titik GPS yang buruk sebelum jarak dan pace dihitung.',
            ),
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.speed,
              title: 'Pace otomatis',
              text:
                  'Current pace dan average pace dihitung dari data gerak nyata, bukan timer buatan.',
            ),
            const SizedBox(height: 12),
            _infoCard(
              icon: Icons.route,
              title: 'Route data',
              text:
                  'Titik rute disiapkan sejak engine dimulai supaya nanti mudah dipetakan dan disinkronkan.',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _controller.startRun,
              icon: const Icon(Icons.play_arrow),
              label: const Text('MULAI LARI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcquiringGps() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mencari GPS'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(strokeWidth: 5),
              ),
              const SizedBox(height: 24),
              const Text(
                'MENCARI SINYAL GPS',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: VoltWarna.teksPutih,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tunggu sampai posisi cukup akurat sebelum timer lari dimulai.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: VoltWarna.teksAbu,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveRun({required bool paused}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(paused ? 'Lari Dijeda' : 'Lari Berlangsung'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            _statusBanner(paused),
            const SizedBox(height: 12),
            _heroMetricCard(),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: 'WAKTU',
                    value: _formatDuration(_controller.elapsed),
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: 'AVG PACE',
                    value: _formatPace(
                      _controller.averagePaceSecondsPerKm,
                    ),
                    icon: Icons.speed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: 'GPS',
                    value: _formatAccuracy(
                      _controller.gpsAccuracyMeters,
                    ),
                    icon: Icons.gps_fixed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: 'TITIK BERSIH',
                    value:
                        '${(_controller.gpsCleanRatio * 100).round()}%',
                    icon: Icons.filter_alt,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _splitCard(),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: paused
                        ? _controller.resumeRun
                        : _controller.pauseRun,
                    icon: Icon(
                      paused ? Icons.play_arrow : Icons.pause,
                    ),
                    label: Text(paused ? 'Lanjut' : 'Jeda'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _finishRun,
                    style: FilledButton.styleFrom(
                      backgroundColor: VoltWarna.merah,
                    ),
                    icon: const Icon(Icons.stop),
                    label: const Text('Selesai'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(RunSession? session) {
    if (session == null) {
      return _buildErrorCard(
        'Data hasil lari tidak tersedia.',
        allowReset: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hasil Lari'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _heroResultCard(session),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: 'MOVING',
                    value: session.movingTimeText,
                    icon: Icons.directions_run,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: 'AVG PACE',
                    value: session.averagePaceText,
                    icon: Icons.speed,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _gpsQualityCard(session),
            const SizedBox(height: 12),
            _summarySplitsCard(session),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _controller.resetRun,
              icon: const Icon(Icons.refresh),
              label: const Text('SIMPAN & KEMBALI KE LARI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return _buildErrorCard(
      _controller.errorMessage ??
          'Terjadi masalah saat memulai sesi lari.',
      allowReset: true,
    );
  }

  Widget _buildErrorCard(
    String message, {
    required bool allowReset,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoltStride Run'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(
                Icons.location_off,
                size: 64,
                color: VoltWarna.merah,
              ),
              const SizedBox(height: 16),
              const Text(
                'LARI TIDAK DAPAT DIMULAI',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VoltWarna.teksAbu,
                ),
              ),
              if (allowReset) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _controller.resetRun,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('KEMBALI'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finishRun() async {
    _controller.finishRun();
  }

  Widget _heroCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'RUNNING ENGINE V2',
              style: TextStyle(
                color: VoltWarna.aksen,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Lari menjadi pusat VoltStride.',
              style: TextStyle(
                fontSize: 28,
                height: 1.05,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'GPS, distance, pace, moving time, dan kilometer split dihitung dari sesi lari nyata.',
              style: TextStyle(
                color: VoltWarna.teksAbu,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroMetricCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          children: <Widget>[
            const Text(
              'JARAK',
              style: TextStyle(
                color: VoltWarna.teksAbu,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _controller.distanceKm.toStringAsFixed(2),
              style: const TextStyle(
                fontSize: 64,
                height: 0.95,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Text(
              'km',
              style: TextStyle(
                color: VoltWarna.aksen,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: VoltWarna.aksen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'PACE  ${_formatPace(_controller.currentPaceSecondsPerKm)} / km',
                style: const TextStyle(
                  color: VoltWarna.aksen,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBanner(bool paused) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: paused
            ? VoltWarna.kuning.withOpacity(0.12)
            : VoltWarna.hijau.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: paused
              ? VoltWarna.kuning.withOpacity(0.4)
              : VoltWarna.hijau.withOpacity(0.4),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            paused ? Icons.pause_circle : Icons.gps_fixed,
            color: paused ? VoltWarna.kuning : VoltWarna.hijau,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              paused
                  ? 'Sesi dijeda. GPS tetap tersedia untuk dilanjutkan.'
                  : 'GPS aktif. Data gerak sedang dihitung.',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: 18,
                  color: VoltWarna.aksen,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: VoltWarna.teksAbu,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: VoltWarna.aksen.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: VoltWarna.aksen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      color: VoltWarna.teksAbu,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _splitCard() {
    final List<RunSplit> splits = _controller.splits;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.flag_outlined,
                  color: VoltWarna.aksen,
                ),
                const SizedBox(width: 8),
                const Text(
                  'KILOMETER SPLIT',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (splits.isEmpty)
              const Text(
                'Belum menyelesaikan 1 km.',
                style: TextStyle(
                  color: VoltWarna.teksAbu,
                ),
              )
            else
              ...splits.reversed.take(5).map(
                (RunSplit split) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 56,
                          child: Text(
                            'KM ${split.kilometer}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: 1,
                            minHeight: 7,
                            backgroundColor:
                                VoltWarna.surface,
                            color: VoltWarna.aksen,
                            borderRadius:
                                BorderRadius.circular(20),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          split.paceText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _heroResultCard(RunSession session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: <Widget>[
            const Text(
              'RUN SELESAI',
              style: TextStyle(
                color: VoltWarna.hijau,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${session.distanceText} km',
              style: const TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              session.elapsedText,
              style: const TextStyle(
                color: VoltWarna.teksAbu,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsQualityCard(RunSession session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'KUALITAS GPS',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _qualityValue(
                    'Akurasi akhir',
                    session.gpsAccuracyText,
                  ),
                ),
                Expanded(
                  child: _qualityValue(
                    'Titik diterima',
                    '${session.acceptedPoints}',
                  ),
                ),
                Expanded(
                  child: _qualityValue(
                    'Ditolak',
                    '${session.rejectedPoints}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qualityValue(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: VoltWarna.teksAbu,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _summarySplitsCard(RunSession session) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'SPLIT PER KM',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            if (session.splits.isEmpty)
              const Text(
                'Belum mencapai 1 km.',
                style: TextStyle(
                  color: VoltWarna.teksAbu,
                ),
              )
            else
              ...session.splits.map(
                (RunSplit split) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 60,
                          child: Text(
                            'KM ${split.kilometer}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatDuration(
                              Duration(
                                seconds: split.durationSeconds,
                              ),
                            ),
                            style: const TextStyle(
                              color: VoltWarna.teksAbu,
                            ),
                          ),
                        ),
                        Text(
                          split.paceText,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatPace(double? paceSecondsPerKm) {
    if (paceSecondsPerKm == null ||
        !paceSecondsPerKm.isFinite ||
        paceSecondsPerKm <= 0 ||
        paceSecondsPerKm > 3600) {
      return '--:--';
    }

    final int rounded = paceSecondsPerKm.round();
    final int minutes = rounded ~/ 60;
    final int seconds = rounded % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatAccuracy(double? accuracy) {
    if (accuracy == null || !accuracy.isFinite) {
      return '--';
    }
    return '${accuracy.toStringAsFixed(0)} m';
  }
}
