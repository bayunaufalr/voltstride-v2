import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'running_controller.dart';
import 'services/run_history_repository.dart';
import 'services/run_evaluation.dart';
import 'run_route_map_view.dart';
import 'services/personal_records_service.dart';

/// Perekaman aktivitas dan ringkasan sesi pengguna.
class RunningPage extends StatefulWidget {
  const RunningPage({
    super.key,
    this.activityType = RunActivityType.run,
    this.environment = RunEnvironment.outdoor,
    this.initialIntervalPlan,
    this.autoStart = false,
    this.onExit,
  });

  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? initialIntervalPlan;
  final bool autoStart;
  final VoidCallback? onExit;

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
  bool _liveMapExpanded = true;
  IntervalRunPlan? _activeIntervalPlan;
  String? _lastIntervalPhaseKey;
  bool _isSavingSession = false;
  String? _saveError;
  List<String> _personalRecordAchievements = <String>[];

  @override
  void initState() {
    super.initState();
    _controller = RunningController();
    _controller.addListener(_onControllerChanged);
    if (widget.initialIntervalPlan != null) {
      final IntervalRunPlan plan = widget.initialIntervalPlan!;
      _intervalModeSelected = true;
      _activeIntervalPlan = plan;
      _workSecondsController.text = plan.workSeconds.toString();
      _recoverySecondsController.text = plan.recoverySeconds.toString();
      _repetitionsController.text = plan.repetitions.toString();
    }
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRun();
      });
    }
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

    final IntervalRunPlan? effectivePlan =
        widget.initialIntervalPlan ?? plan;
    _activeIntervalPlan = effectivePlan;
    _lastIntervalPhaseKey = null;
    _liveMapExpanded = true;
    await _controller.startRun(
      intervalPlan: effectivePlan,
      useGps: widget.environment == RunEnvironment.outdoor,
      activityType: widget.activityType,
      environment: widget.environment,
    );
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
      appBar: AppBar(title: const Text('Rekam aktivitas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            const Icon(Icons.directions_run_rounded, size: 54, color: VoltWarna.aksen),
            const SizedBox(height: 14),
            const Text(
              'Siap untuk bergerak?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              widget.environment == RunEnvironment.indoor
                  ? 'Waktu direkam tanpa GPS. Jarak bisa dimasukkan saat sesi selesai.'
                  : 'Pastikan izin lokasi aktif sebelum mulai di luar ruangan.',
              style: const TextStyle(color: VoltWarna.teksAbu, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (widget.initialIntervalPlan == null) _buildIntervalSettings(),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _startRun,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(_intervalModeSelected ? 'Mulai interval' : 'Mulai aktivitas'),
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

  String get _activityDisplayLabel =>
      _activeIntervalPlan == null ? widget.activityType.label : 'Lari interval';

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
    if (widget.environment == RunEnvironment.indoor) {
      return _buildIndoorLiveRun(paused: paused);
    }
    if (_liveMapExpanded) {
      return _buildLiveMapExperience(paused: paused);
    }
    return _buildLiveRunDetails(paused: paused);
  }

  Widget _buildIndoorLiveRun({required bool paused}) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${_activityDisplayLabel} • Dalam ruangan'),
        leading: IconButton(
          tooltip: 'Keluar dari aktivitas',
          onPressed: () => _confirmExitIndoor(paused: paused),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      colors: <Color>[Color(0xFF18384A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.directions_run_rounded, size: 48, color: VoltWarna.aksen),
                      const SizedBox(height: 16),
                      Text(_formatDuration(_controller.elapsed), style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(paused ? 'Dijeda' : 'Aktivitas berlangsung', style: const TextStyle(color: VoltWarna.teksAbu)),
                      const SizedBox(height: 22),
                      Text('${_controller.distanceKm.toStringAsFixed(2)} km', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      const Text('Jarak dimasukkan setelah selesai', style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
                      if (_activeIntervalPlan != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _intervalPhaseCard(_activeIntervalPlan!, _controller.elapsed),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: paused ? _controller.resumeRun : _controller.pauseRun,
                      icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      label: Text(paused ? 'Lanjutkan' : 'Jeda'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _finishRun,
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Selesai'),
                      style: FilledButton.styleFrom(backgroundColor: VoltWarna.merah),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmExitIndoor({required bool paused}) async {
    final bool? exit = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Akhiri aktivitas?'),
        content: const Text('Aktivitas yang belum diselesaikan tidak akan disimpan ke riwayat.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Kembali')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Akhiri')),
        ],
      ),
    );
    if (exit == true && mounted) {
      _controller.resetRun();
      final VoidCallback? onExit = widget.onExit;
      if (onExit != null) onExit();
    } else if (paused && mounted) {
      // Tetap dijeda sesuai pilihan terakhir.
    }
  }

  /// Map-first live running layout, similar to dedicated running apps.
  /// The top-left control closes the map; the collapsed details screen keeps
  /// all existing metrics and offers a way to reopen it.
  Widget _buildLiveMapExperience({required bool paused}) {
    final double? pace = _controller.currentPaceSecondsPerKm ??
        _controller.averagePaceSecondsPerKm;
    final double? speedKmh = pace != null && pace > 0 ? 3600.0 / pace : null;
    final RunElevationStats elevation = calculateRunElevation(_controller.route);
    final String netElevation =
        '${elevation.netChangeMeters > 0 ? '+' : ''}'
        '${elevation.netChangeMeters.toStringAsFixed(0)} m';
    final String gpsAccuracy = _formatAccuracy(_controller.gpsAccuracyMeters);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: RunRouteMapView(
              key: const ValueKey<String>('live-run-route-map-fullscreen'),
              route: _controller.route,
              laps: _controller.hundredMeterLaps,
              height: MediaQuery.sizeOf(context).height,
              followLastPoint: !paused,
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: <Widget>[
                      Material(
                        color: Colors.black.withValues(alpha: 0.84),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Tutup peta',
                          onPressed: () => setState(() => _liveMapExpanded = false),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              paused ? Icons.pause_circle : Icons.gps_fixed,
                              size: 16,
                              color: paused ? Colors.orangeAccent : Colors.greenAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              paused ? 'AKTIVITAS DIJEDA' : 'AKURASI GPS • $gpsAccuracy',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 15, 12, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xED101010),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          _activityDisplayLabel.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            _liveMapMetric('WAKTU', _formatDuration(_controller.elapsed)),
                            _liveMapMetric('PACE', _formatPace(pace)),
                            _liveMapMetric('JARAK', '${_controller.distanceKm.toStringAsFixed(2)} km'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.speed, color: VoltWarna.aksen, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              speedKmh != null && speedKmh.isFinite && speedKmh >= 0.5 && speedKmh <= 35
                                  ? '${speedKmh.toStringAsFixed(1)} km/jam'
                                  : '-- km/jam',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.terrain, color: VoltWarna.aksen, size: 18),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                elevation.hasAltitudeData
                                    ? 'Bersih $netElevation'
                                    : 'Elevasi --',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (elevation.hasAltitudeData) ...<Widget>[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Naik ${elevation.totalAscentMeters.toStringAsFixed(0)} m'
                              ' • Turun ${elevation.totalDescentMeters.toStringAsFixed(0)} m'
                              ' • Puncak +${elevation.maxAboveStartMeters.toStringAsFixed(0)} m dari start',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    10,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF101010),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: paused
                                  ? _controller.resumeRun
                                  : _controller.pauseRun,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white30),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                              ),
                              icon: Icon(paused ? Icons.play_arrow : Icons.pause),
                              label: Text(paused ? 'Lanjut' : 'Jeda'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _finishRun,
                              style: FilledButton.styleFrom(
                                backgroundColor: VoltWarna.merah,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                              ),
                              icon: const Icon(Icons.stop),
                              label: const Text('Selesai'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Peta rute • ketuk penanda 100 m untuk detail kecepatan dan elevasi',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMapMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveRunDetails({required bool paused}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(paused ? '$_activityDisplayLabel dijeda' : '$_activityDisplayLabel berlangsung'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: <Widget>[
            _statusBanner(paused),
            const SizedBox(height: 10),
            _liveMapSection(paused: paused),
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
            _elevationStatsCard(calculateRunElevation(_controller.route)),
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
        'Data aktivitas tidak tersedia.',
        allowReset: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Hasil aktivitas'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _heroResultCard(session),
            if (_personalRecordAchievements.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _personalRecordCard(),
            ],
            const SizedBox(height: 12),
            _saveStatusCard(),
            if (session.environment == RunEnvironment.outdoor) ...<Widget>[
              const SizedBox(height: 12),
              _routeMapCard(session.route, session.hundredMeterLaps),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              _infoCard(
                icon: Icons.directions_run_rounded,
                title: 'Aktivitas dalam ruangan',
                text: 'Jarak dicatat dari nilai yang dimasukkan saat sesi selesai. Peta dan elevasi GPS tidak tersedia untuk sesi ini.',
              ),
            ],
            const SizedBox(height: 12),
            _elevationStatsCard(session.elevationStats),
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
            if (session.environment == RunEnvironment.outdoor) ...<Widget>[
              const SizedBox(height: 12),
              _gpsQualityCard(session),
            ],
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
                _isSavingSession
                    ? 'Menyimpan hasil...'
                    : (widget.onExit == null ? 'Kembali ke aktivitas' : 'Kembali ke beranda'),
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
        title: const Text('Rekam aktivitas'),
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
                'AKTIVITAS TIDAK DAPAT DIMULAI',
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

    double? indoorDistanceMeters;
    bool shouldResumeOnCancel = _controller.status == RunStatus.running;
    if (widget.environment == RunEnvironment.indoor) {
      if (shouldResumeOnCancel) _controller.pauseRun();
      final TextEditingController distanceController =
          TextEditingController(text: '0.00');
      final String? enteredKm = await showDialog<String>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Jarak aktivitas dalam ruangan'),
          content: TextField(
            controller: distanceController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Jarak (km)',
              hintText: 'Contoh: 3,50',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Lanjutkan sesi'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(distanceController.text.trim()),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
      distanceController.dispose();
      if (enteredKm == null) {
        if (shouldResumeOnCancel && mounted) _controller.resumeRun();
        return;
      }
      final double? km = double.tryParse(enteredKm.replaceAll(',', '.'));
      if (km == null || !km.isFinite || km < 0 || km > 300) {
        if (shouldResumeOnCancel && mounted) _controller.resumeRun();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Masukkan jarak 0 sampai 300 km.')),
          );
        }
        return;
      }
      indoorDistanceMeters = km * 1000;
    }

    setState(() {
      _isSavingSession = true;
      _saveError = null;
      _personalRecordAchievements = <String>[];
    });

    final RunSession? session =
        _controller.finishRun(indoorDistanceMeters: indoorDistanceMeters);
    if (session == null) {
      if (mounted) setState(() => _isSavingSession = false);
      return;
    }

    try {
      final List<RunSession> previous =
          await RunHistoryRepository.instance.getAll();
      final List<String> achievements =
          PersonalRecordsService.achievementsFor(session, previous);
      if (mounted) {
        setState(() => _personalRecordAchievements = achievements);
      }
    } catch (_) {
      // Sesi tetap disimpan bila pembacaan riwayat lama gagal.
    }
    await _persistSession(session, alreadySaving: true);
  }

  Widget _personalRecordCard() {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF173B31), Color(0xFF1E293B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: VoltWarna.hijau.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.emoji_events_rounded, color: VoltWarna.hijau, size: 25),
              SizedBox(width: 9),
              Expanded(
                child: Text('REKOR BARU!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._personalRecordAchievements.map((String achievement) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('•  ', style: TextStyle(color: VoltWarna.hijau, fontWeight: FontWeight.w900)),
                    Expanded(child: Text(achievement, style: const TextStyle(fontWeight: FontWeight.w700))),
                  ],
                ),
              )),
        ],
      ),
    );
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
              'Hasil aktivitas belum tersimpan. Periksa ruang penyimpanan lalu coba lagi.';
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
    final VoidCallback? exit = widget.onExit;
    if (exit != null) {
      exit();
    }
  }

  Widget _saveStatusCard() {
    final bool hasError = _saveError != null;
    final String message = _isSavingSession
        ? 'Menyimpan aktivitas ke perangkat...' 
        : _saveError ?? 'Aktivitas tersimpan di perangkat ini.';

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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
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
                      fontSize: 14,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: VoltWarna.hijau.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'SPEED  ${_formatCurrentSpeed(_controller.currentPaceSecondsPerKm)} km/jam',
                    style: const TextStyle(
                      color: VoltWarna.hijau,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatCurrentSpeed(double? paceSecondsPerKm) {
    if (paceSecondsPerKm == null ||
        !paceSecondsPerKm.isFinite ||
        paceSecondsPerKm <= 0 ||
        paceSecondsPerKm > 3600) {
      return '--';
    }
    final double speed = 3600 / paceSecondsPerKm;
    if (!speed.isFinite || speed > 35) return '--';
    return speed.toStringAsFixed(1);
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
                  ? 'Aktivitas dijeda. Lanjutkan saat siap.'
                  : 'Aktivitas sedang direkam.',
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
            Text(
              '${session.displayLabel.toUpperCase()} SELESAI',
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'PETA RUTE LARI',
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: RunRouteMapView(
              route: route,
              laps: laps,
              height: 290,
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Ketuk penanda 100 m untuk melihat kecepatan, pace, dan elevasi. Peta dasar membutuhkan internet; rute GPS tersimpan secara lokal.',
              style: TextStyle(fontSize: 11, color: VoltWarna.teksAbu),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMapSection({required bool paused}) {
    final List<RunPoint> route = _controller.route;
    final List<RunLap100m> laps = _controller.hundredMeterLaps;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.map_outlined, color: VoltWarna.aksen),
            title: const Text(
              'PETA RUTE LIVE',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              paused
                  ? 'Perekaman dijeda'
                  : 'Rute dan titik kecepatan diperbarui saat GPS masuk',
            ),
            trailing: IconButton(
              tooltip: _liveMapExpanded ? 'Tutup peta' : 'Buka peta',
              onPressed: () => setState(() => _liveMapExpanded = !_liveMapExpanded),
              icon: Icon(
                _liveMapExpanded ? Icons.expand_less : Icons.expand_more,
              ),
            ),
            onTap: () => setState(() => _liveMapExpanded = !_liveMapExpanded),
          ),
          if (_liveMapExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: RunRouteMapView(
                key: const ValueKey<String>('live-run-route-map'),
                route: route,
                laps: laps,
                height: 300,
                followLastPoint: !paused,
              ),
            ),
        ],
      ),
    );
  }

  Widget _elevationStatsCard(RunElevationStats stats) {
    String signed(double value) {
      final String prefix = value > 0 ? '+' : '';
      return '$prefix${value.toStringAsFixed(0)} m';
    }

    String format(double value) => '${value.toStringAsFixed(0)} m';

    Widget metric(String label, String value, String detail) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(fontSize: 11, color: VoltWarna.teksAbu)),
              const SizedBox(height: 3),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              Text(detail, style: const TextStyle(fontSize: 10, color: VoltWarna.teksAbu)),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.terrain, color: VoltWarna.aksen),
                SizedBox(width: 8),
                Text('ELEVASI GPS', style: TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 6),
            if (!stats.hasAltitudeData)
              const Text(
                'Data ketinggian belum tersedia dari GPS.',
                style: TextStyle(color: VoltWarna.teksAbu),
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  metric('NAIK TOTAL', format(stats.totalAscentMeters), 'Semua kenaikan'),
                  metric('TURUN TOTAL', format(stats.totalDescentMeters), 'Semua penurunan'),
                ],
              ),
              Row(
                children: <Widget>[
                  metric('ELEVASI BERSIH', signed(stats.netChangeMeters), 'Naik dikurangi turun'),
                  metric('PUNCAK REL. START', signed(stats.maxAboveStartMeters), 'Titik tertinggi di atas start'),
                ],
              ),
            ],
            const SizedBox(height: 4),
            const Text(
              'Elevasi berasal dari GPS dan dapat berfluktuasi. Perubahan kecil diabaikan untuk mengurangi noise.',
              style: TextStyle(fontSize: 10, color: VoltWarna.teksAbu),
            ),
          ],
        ),
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
            const Text('Kecepatan adalah rata-rata per segmen 100 m, bukan instan. Kolom terakhir menunjukkan elevasi GPS di titik tersebut.', style: TextStyle(fontSize: 12, color: VoltWarna.teksAbu)),
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
                        const SizedBox(width: 6),
                        SizedBox(width: 48, child: Text(lap.altitudeMeters == null ? '-- m' : '${lap.altitudeMeters!.round()} m', textAlign: TextAlign.end, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11))),
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
