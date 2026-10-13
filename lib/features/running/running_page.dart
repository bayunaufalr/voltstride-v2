import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'running_controller.dart';
import 'services/run_history_repository.dart';
import 'services/run_evaluation.dart';

/// Halaman lari V2.
///
/// Untuk sprint pertama ini kita sengaja fokus pada satu hal:
/// start -> dapat GPS -> live metrics -> pause/resume -> finish -> summary.
/// Hasil yang selesai disimpan otomatis ke SQLite lokal. Peta rute masuk
/// sprint berikutnya setelah engine dan riwayat stabil.
class RunningPage extends StatefulWidget {
  const RunningPage({super.key});

  @override
  State<RunningPage> createState() => _RunningPageState();
}

class _RunningPageState extends State<RunningPage> {
  late final RunningController _controller;
  final TextEditingController _workSecondsController =
      TextEditingController(text: '60');
  final TextEditingController _recoverySecondsController =
      TextEditingController(text: '90');
  final TextEditingController _repetitionsController =
      TextEditingController(text: '6');
  bool _intervalModeSelected = false;
  IntervalRunPlan? _activeIntervalPlan;
  String? _lastIntervalPhaseKey;
  bool _isSavingSession = false;
  String? _saveError;

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
    _workSecondsController.dispose();
    _recoverySecondsController.dispose();
    _repetitionsController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final IntervalRunPlan? plan = _activeIntervalPlan;
    if (plan != null && _controller.status == RunStatus.running) {
      final IntervalPhase phase = plan.phaseAt(_controller.elapsed);
      final String phaseKey = '${phase.stage.name}-${phase.repetition}';
      final String? previousKey = _lastIntervalPhaseKey;
      if (previousKey != null && previousKey != phaseKey) {
        unawaited(HapticFeedback.mediumImpact());
      }
      _lastIntervalPhaseKey = phaseKey;
    }
    if (_controller.status == RunStatus.idle ||
        _controller.status == RunStatus.error) {
      _lastIntervalPhaseKey = null;
      _activeIntervalPlan = null;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _startRun() async {
    IntervalRunPlan? plan;
    if (_intervalModeSelected) {
      final int? work = int.tryParse(_workSecondsController.text.trim());
      final int? recovery = int.tryParse(_recoverySecondsController.text.trim());
      final int? repetitions = int.tryParse(_repetitionsController.text.trim());
      if (work == null || work < 10 || work > 3600 ||
          recovery == null || recovery < 5 || recovery > 3600 ||
          repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Atur kerja 10-3600 detik, pemulihan 5-3600 detik, dan ulangan 1-30.'),
          ),
        );
        return;
      }
      plan = IntervalRunPlan(
        workSeconds: work,
        recoverySeconds: recovery,
        repetitions: repetitions,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final PermissionStatus notificationStatus =
            await Permission.notification.request();
        if (!notificationStatus.isGranted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin notifikasi ditolak. Pelacakan tetap dicoba, tetapi notifikasi mungkin tidak tampil di panel.'),
            ),
          );
        }
      } catch (_) {
        // GPS masih dapat dimulai jika dialog notifikasi tidak tersedia.
      }
    }

    _activeIntervalPlan = plan;
    _lastIntervalPhaseKey = null;
    await _controller.startRun(intervalPlan: plan);
    if (_controller.status == RunStatus.error) {
      _activeIntervalPlan = null;
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
            _buildIntervalSettings(),
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
              onPressed: _startRun,
              icon: const Icon(Icons.play_arrow),
              label: Text(_intervalModeSelected ? 'MULAI LARI INTERVAL' : 'MULAI LARI'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'MODE LATIHAN',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.9),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lari interval'),
              subtitle: const Text('Atur waktu lari cepat, pemulihan, dan jumlah ulangan.'),
              value: _intervalModeSelected,
              onChanged: (bool value) => setState(() => _intervalModeSelected = value),
            ),
            if (_intervalModeSelected) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: _numberSettingField('Kerja (detik)', _workSecondsController)),
                  const SizedBox(width: 10),
                  Expanded(child: _numberSettingField('Pemulihan (detik)', _recoverySecondsController)),
                ],
              ),
              const SizedBox(height: 10),
              _numberSettingField('Jumlah ulangan (1-30)', _repetitionsController),
              const SizedBox(height: 8),
              Text(
                'Contoh: 60 detik lari + 90 detik pemulihan, diulang 6 kali. Timer dimulai setelah GPS siap.',
                style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _numberSettingField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
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
            if (_activeIntervalPlan != null) ...<Widget>[
              const SizedBox(height: 12),
              _intervalPhaseCard(_activeIntervalPlan!, _controller.elapsed),
            ],
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
            _saveStatusCard(),
            const SizedBox(height: 12),
            _routeMapCard(session.route, session.hundredMeterLaps),
            const SizedBox(height: 12),
            _hundredMeterLapsCard(session),
            const SizedBox(height: 12),
            _evaluationCard(session),
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
            if (_saveError != null) ...<Widget>[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSavingSession
                    ? null
                    : () => _persistSession(session),
                icon: const Icon(Icons.save_outlined),
                label: const Text('COBA SIMPAN LAGI'),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isSavingSession ? null : _backToRun,
              icon: Icon(_isSavingSession ? Icons.sync : Icons.refresh),
              label: Text(
                _isSavingSession ? 'MENYIMPAN HASIL...' : 'KEMBALI KE LARI',
              ),
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
    if (_isSavingSession) return;

    setState(() {
      _isSavingSession = true;
      _saveError = null;
    });

    final RunSession? session = _controller.finishRun();
    if (session == null) {
      if (mounted) setState(() => _isSavingSession = false);
      return;
    }

    await _persistSession(session, alreadySaving: true);
  }

  Future<void> _persistSession(
    RunSession session, {
    bool alreadySaving = false,
  }) async {
    if (!alreadySaving && mounted) {
      setState(() {
        _isSavingSession = true;
        _saveError = null;
      });
    }

    try {
      await RunHistoryRepository.instance.save(session);
      if (mounted) setState(() => _saveError = null);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saveError =
              'Hasil lari belum tersimpan. Periksa ruang penyimpanan lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSavingSession = false);
    }
  }

  void _backToRun() {
    if (_isSavingSession) return;
    setState(() {
      _saveError = null;
      _activeIntervalPlan = null;
      _lastIntervalPhaseKey = null;
    });
    _controller.resetRun();
  }

  Widget _saveStatusCard() {
    final bool hasError = _saveError != null;
    final String message = _isSavingSession
        ? 'Menyimpan hasil lari ke perangkat...'
        : _saveError ?? 'Hasil lari tersimpan lokal di perangkat ini.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Icon(
              _isSavingSession
                  ? Icons.sync
                  : hasError
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
              color: hasError ? VoltWarna.merah : VoltWarna.hijau,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
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

  Widget _intervalPhaseCard(IntervalRunPlan plan, Duration elapsed) {
    final IntervalPhase phase = plan.phaseAt(elapsed);
    final bool work = phase.stage == IntervalStage.work;
    final bool complete = phase.stage == IntervalStage.complete;
    final String title = complete
        ? 'INTERVAL SELESAI'
        : work
            ? 'FASE KERJA / LARI'
            : 'FASE PEMULIHAN';
    final int mins = phase.secondsRemaining ~/ 60;
    final int secs = phase.secondsRemaining % 60;
    return Card(
      color: complete
          ? VoltWarna.hijau.withOpacity(0.12)
          : work
              ? VoltWarna.aksen.withOpacity(0.12)
              : VoltWarna.kuning.withOpacity(0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(
              complete ? Icons.check_circle : work ? Icons.directions_run : Icons.self_improvement,
              size: 30,
              color: complete ? VoltWarna.hijau : work ? VoltWarna.aksen : VoltWarna.kuning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(complete
                      ? 'Selesai ${plan.repetitions} ulangan. Rekaman GPS tetap berjalan sampai kamu menekan Selesai.'
                      : 'Ulangan ${phase.repetition}/${plan.repetitions}'),
                ],
              ),
            ),
            if (!complete)
              Text('$mins:${secs.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _routeMapCard(List<RunPoint> route, List<RunLap100m> laps) {
    if (route.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Belum ada titik GPS untuk ditampilkan pada peta.'),
        ),
      );
    }

    final List<LatLng> allPoints = route
        .map((RunPoint point) => LatLng(point.latitude, point.longitude))
        .toList(growable: false);
    final LatLng center = allPoints.last;
    final List<List<LatLng>> groups = <List<LatLng>>[];
    for (int i = 0; i < route.length; i++) {
      final RunPoint point = route[i];
      if (groups.isEmpty || point.startsNewSegment) {
        groups.add(<LatLng>[]);
      }
      groups.last.add(allPoints[i]);
    }
    final List<Polyline> lines = groups
        .where((List<LatLng> points) => points.length >= 2)
        .map((List<LatLng> points) => Polyline(
              points: points,
              strokeWidth: 4.5,
              color: VoltWarna.aksen,
            ))
        .toList(growable: false);

    final List<Marker> markers = <Marker>[
      Marker(
        point: allPoints.first,
        width: 30,
        height: 30,
        child: const Icon(Icons.flag_circle, color: Colors.green, size: 28),
      ),
      if (allPoints.length > 1)
        Marker(
          point: allPoints.last,
          width: 30,
          height: 30,
          child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        ),
      ...laps.map((RunLap100m lap) => Marker(
            point: LatLng(lap.latitude, lap.longitude),
            width: 28,
            height: 28,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: VoltWarna.kartu,
                shape: BoxShape.circle,
                border: Border.all(color: VoltWarna.aksen, width: 1.5),
              ),
              child: Text(
                '${lap.distanceMeters.round()}',
                style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900),
              ),
            ),
          )),
    ];

    final MapOptions options = MapOptions(
      initialCenter: center,
      initialZoom: 16,
      initialCameraFit: allPoints.length >= 2
          ? CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(allPoints),
              padding: const EdgeInsets.all(28),
            )
          : null,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('PETA RUTE LARI', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          ),
          SizedBox(
            height: 260,
            child: FlutterMap(
              options: options,
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.voltstride',
                ),
                if (lines.isNotEmpty) PolylineLayer(polylines: lines),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Angka pada titik peta menunjukkan jarak kumulatif dalam meter. Peta dasar membutuhkan internet; rekaman koordinat tetap disimpan lokal.',
              style: TextStyle(fontSize: 11, color: VoltWarna.teksAbu),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Kontributor peta'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hundredMeterLapsCard(RunSession session) {
    final List<RunLap100m> laps = session.hundredMeterLaps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('KECEPATAN SETIAP 100 METER', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.6)),
            const SizedBox(height: 6),
            const Text('Kecepatan adalah rata-rata per segmen 100 m, bukan kecepatan instan GPS.', style: TextStyle(fontSize: 12, color: VoltWarna.teksAbu)),
            const SizedBox(height: 12),
            if (laps.isEmpty)
              const Text('Belum ada segmen 100 m yang valid.')
            else
              ...laps.map((RunLap100m lap) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 62, child: Text('${lap.distanceMeters.round()} m', style: const TextStyle(fontWeight: FontWeight.w800))),
                        Expanded(child: Text(_formatDuration(Duration(milliseconds: lap.durationMilliseconds)))),
                        SizedBox(width: 76, child: Text(lap.speedKmh == null ? '--' : '${lap.speedKmh!.toStringAsFixed(1)} km/h', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w900))),
                        const SizedBox(width: 10),
                        SizedBox(width: 55, child: Text(lap.paceSecondsPerKm == null ? '--' : _formatPace(lap.paceSecondsPerKm), textAlign: TextAlign.end, style: const TextStyle(color: VoltWarna.teksAbu))),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _evaluationCard(RunSession session) {
    final RunEvaluation evaluation = evaluateRun(session);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.insights, color: VoltWarna.aksen),
                const SizedBox(width: 8),
                Expanded(child: Text('EVALUASI AKHIR: ${evaluation.title.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.w900))),
              ],
            ),
            const SizedBox(height: 8),
            Text(evaluation.overview, style: const TextStyle(color: VoltWarna.teksAbu, height: 1.4)),
            const SizedBox(height: 12),
            const Text('PENGAMATAN', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...evaluation.observations.map((String text) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Text('•  '), Expanded(child: Text(text))]),
                )),
            const SizedBox(height: 8),
            const Text('SARAN SESI BERIKUTNYA', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            ...evaluation.recommendations.map((String text) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[const Icon(Icons.arrow_right, size: 18, color: VoltWarna.aksen), Expanded(child: Text(text))]),
                )),
          ],
        ),
      ),
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
