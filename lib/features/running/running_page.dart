import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pedometer/pedometer.dart';

import '../../theme/volt_theme.dart';
import '../../services/app_language_service.dart';
import 'models/run_session.dart';
import 'running_controller.dart';
import 'services/run_history_repository.dart';
import 'run_route_map_view.dart';
import 'services/personal_records_service.dart';
import 'run_activity_charts.dart';
import 'run_share_page.dart';

/// Perekaman aktivitas dan ringkasan sesi pengguna.
class RunningPage extends StatefulWidget {
  const RunningPage({
    super.key,
    this.activityType = RunActivityType.run,
    this.environment = RunEnvironment.outdoor,
    this.initialIntervalPlan,
    this.targetDistanceKm,
    this.targetPaceSecondsPerKm,
    this.autoStart = false,
    this.onExit,
  });

  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? initialIntervalPlan;
  final double? targetDistanceKm;
  final double? targetPaceSecondsPerKm;
  final bool autoStart;
  final VoidCallback? onExit;

  @override
  State<RunningPage> createState() => _RunningPageState();
}

class _RunningPageState extends State<RunningPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

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
  final ValueNotifier<int> _liveMetricsRevision = ValueNotifier<int>(0);
  final ValueNotifier<List<RunPoint>> _liveMapRoute =
      ValueNotifier<List<RunPoint>>(const <RunPoint>[]);
  final ValueNotifier<RunElevationStats> _liveElevationStats =
      ValueNotifier<RunElevationStats>(calculateRunElevation(const <RunPoint>[]));
  Timer? _mapRefreshTimer;
  RunStatus? _lastObservedStatus;
  int _lastObservedRouteLength = 0;
  int? _countdownValue;
  bool _isStarting = false;
  StreamSubscription<StepCount>? _stepSubscription;
  bool _requestingStepStream = false;
  int? _lastSystemStepCount;
  DateTime? _lastStepTimestamp;
  DateTime? _lastCadenceSampleAt;
  int _stepsThisActivity = 0;
  double _maxCadenceSpm = 0;
  final List<RunCadenceSample> _cadenceSamples = <RunCadenceSample>[];

  @override
  void initState() {
    super.initState();
    _controller = RunningController();
    _lastObservedStatus = _controller.status;
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
    unawaited(_stepSubscription?.cancel() ?? Future<void>.value());
    _mapRefreshTimer?.cancel();
    _liveMetricsRevision.dispose();
    _liveMapRoute.dispose();
    _liveElevationStats.dispose();
    _controller.dispose();
    _workSecondsController.dispose();
    _recoverySecondsController.dispose();
    _repetitionsController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final RunStatus currentStatus = _controller.status;
    final bool statusChanged = currentStatus != _lastObservedStatus;
    _lastObservedStatus = currentStatus;

    final IntervalRunPlan? plan = _activeIntervalPlan;
    if (plan != null && currentStatus == RunStatus.running) {
      final IntervalPhase phase = plan.phaseAtProgress(
        elapsed: _controller.elapsed,
        distanceMeters: _controller.distanceKm * 1000,
      );
      final String phaseKey = '${phase.stage.name}-${phase.repetition}';
      final String? previousKey = _lastIntervalPhaseKey;
      if (previousKey != null && previousKey != phaseKey) {
        unawaited(HapticFeedback.heavyImpact());
      }
      _lastIntervalPhaseKey = phaseKey;
    }

    if (currentStatus == RunStatus.idle || currentStatus == RunStatus.error) {
      _lastIntervalPhaseKey = null;
      _activeIntervalPlan = null;
    }
    if (statusChanged && currentStatus == RunStatus.running) {
      unawaited(_ensureStepTracking());
    }

    final int routeLength = _controller.routeLength;
    if (routeLength != _lastObservedRouteLength) {
      _lastObservedRouteLength = routeLength;
      _scheduleMapRouteRefresh(immediate: statusChanged);
    } else if (statusChanged &&
        (currentStatus == RunStatus.running ||
            currentStatus == RunStatus.paused ||
            currentStatus == RunStatus.finished)) {
      _scheduleMapRouteRefresh(immediate: true);
    }

    // Jam/pace/angka statistik diperbarui lewat notifier kecil. Jangan setState
    // seluruh halaman setiap detik karena itu ikut membangun ulang widget peta.
    _liveMetricsRevision.value++;
    if (statusChanged && mounted) setState(() {});
  }

  Future<void> _ensureStepTracking() async {
    if (_stepSubscription != null || _requestingStepStream || !mounted) return;
    _requestingStepStream = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final PermissionStatus status = await Permission.activityRecognition.request();
        if (!status.isGranted) return;
      }
      _stepSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: (Object _) {
          // Aplikasi tetap merekam GPS jika sensor langkah tidak tersedia.
        },
        cancelOnError: false,
      );
    } catch (_) {
      // Sensor cadence bersifat opsional; kegagalannya tidak menghentikan sesi.
    } finally {
      _requestingStepStream = false;
    }
  }

  void _onStepCount(StepCount event) {
    final DateTime timestamp = event.timeStamp;
    final int systemSteps = event.steps;
    final int? previousSteps = _lastSystemStepCount;
    final DateTime? previousTimestamp = _lastStepTimestamp;
    _lastSystemStepCount = systemSteps;
    _lastStepTimestamp = timestamp;

    // Pedometer mengirim penghitung sistem kumulatif. Ambil baseline ketika
    // stream dimulai agar langkah dari sebelum sesi tidak ikut dihitung.
    if (previousSteps == null || previousTimestamp == null) return;
    final int deltaSteps = systemSteps - previousSteps;
    final double elapsedSeconds = timestamp.difference(previousTimestamp).inMilliseconds / 1000.0;
    if (deltaSteps < 0 || deltaSteps > 300 || !elapsedSeconds.isFinite || elapsedSeconds <= 0) return;

    // Saat jeda, baseline tetap maju tetapi langkah jeda tidak ditambahkan.
    if (_controller.status != RunStatus.running) return;
    _stepsThisActivity += deltaSteps;
    if (deltaSteps > 0 && elapsedSeconds >= 1 && elapsedSeconds <= 30) {
      final double cadence = deltaSteps * 60.0 / elapsedSeconds;
      if (cadence.isFinite && cadence >= 30 && cadence <= 240) {
        final DateTime? previousSample = _lastCadenceSampleAt;
        if (previousSample == null || timestamp.difference(previousSample).inSeconds >= 5) {
          _lastCadenceSampleAt = timestamp;
          _maxCadenceSpm = math.max(_maxCadenceSpm, cadence).toDouble();
          _cadenceSamples.add(RunCadenceSample(
            distanceMeters: _controller.distanceKm * 1000,
            cadenceSpm: cadence,
          ));
        }
      }
    }
    final double? averageCadence = _cadenceSamples.isEmpty
        ? null
        : _cadenceSamples.map((RunCadenceSample item) => item.cadenceSpm).reduce((double a, double b) => a + b) / _cadenceSamples.length;
    _controller.updateCadenceMetrics(
      totalSteps: _stepsThisActivity,
      averageCadenceSpm: averageCadence,
      maxCadenceSpm: _maxCadenceSpm > 0 ? _maxCadenceSpm : null,
      samples: List<RunCadenceSample>.unmodifiable(_cadenceSamples),
    );
  }

  void _scheduleMapRouteRefresh({bool immediate = false}) {
    if (!mounted) return;
    if (immediate) {
      _mapRefreshTimer?.cancel();
      _mapRefreshTimer = null;
      final List<RunPoint> latestRoute = _controller.route;
      _liveMapRoute.value = latestRoute;
      _liveElevationStats.value = calculateRunElevation(latestRoute);
      return;
    }
    // Peta diperbarui berkala, bukan untuk setiap tick statistik. Rute penuh
    // tetap disimpan oleh engine dan dipakai saat hasil sesi dibuat.
    _mapRefreshTimer ??= Timer(const Duration(seconds: 2), () {
      _mapRefreshTimer = null;
      if (!mounted) return;
      final List<RunPoint> latestRoute = _controller.route;
      _liveMapRoute.value = latestRoute;
      _liveElevationStats.value = calculateRunElevation(latestRoute);
    });
  }

  Widget _liveMetricsBuilder(Widget Function() builder) {
    return ValueListenableBuilder<int>(
      valueListenable: _liveMetricsRevision,
      builder: (BuildContext context, int revision, Widget? child) => builder(),
    );
  }

  Future<void> _runStartCountdown() async {
    for (int value = 5; value >= 1; value--) {
      if (!mounted) return;
      setState(() => _countdownValue = value);
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (mounted) setState(() => _countdownValue = null);
  }

  Future<void> _startRun() async {
    if (_isStarting) return;

    IntervalRunPlan? plan;
    if (_intervalModeSelected) {
      final int? work = int.tryParse(_workSecondsController.text.trim());
      final int? recovery = int.tryParse(_recoverySecondsController.text.trim());
      final int? repetitions = int.tryParse(_repetitionsController.text.trim());
      if (work == null || work < 10 || work > 3600 ||
          recovery == null || recovery < 5 || recovery > 3600 ||
          repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text(
              'Atur kerja 10–3600 detik, pemulihan 5–3600 detik, dan ulangan 1–30.',
              'Set work intervals to 10–3600 seconds, rest to 5–3600 seconds, and repetitions to 1–30.',
            )),
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

    setState(() => _isStarting = true);
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          final PermissionStatus notificationStatus =
              await Permission.notification.request();
          if (!mounted) return;
          if (!notificationStatus.isGranted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_text(
                  'Izin notifikasi ditolak. Pelacakan tetap berjalan, tetapi notifikasi mungkin tidak muncul.',
                  'Notification permission was denied. Tracking can continue, but notifications may not appear.',
                )),
              ),
            );
          }
        } catch (_) {
          // GPS masih dapat dimulai jika dialog notifikasi tidak tersedia.
        }
      }
      if (!mounted) return;

      final IntervalRunPlan? effectivePlan =
          widget.initialIntervalPlan ?? plan;
      _activeIntervalPlan = effectivePlan;
      _lastIntervalPhaseKey = null;
      _liveMapExpanded = true;
      _countdownValue = null;
      _stepsThisActivity = 0;
      _lastSystemStepCount = null;
      _lastStepTimestamp = null;
      _lastCadenceSampleAt = null;
      _maxCadenceSpm = 0;
      _cadenceSamples.clear();
      await _controller.startRun(
        intervalPlan: effectivePlan,
        useGps: widget.environment == RunEnvironment.outdoor,
        activityType: widget.activityType,
        environment: widget.environment,
        onGpsReady: _runStartCountdown,
      );
      if (!mounted) return;
      if (_controller.status == RunStatus.error) {
        _activeIntervalPlan = null;
        _countdownValue = null;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _countdownValue = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text(
              'VoltStride tidak dapat memulai aktivitas. Coba lagi setelah lokasi siap.',
              'VoltStride could not start the activity. Try again when your location is ready.',
            )),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
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
      appBar: AppBar(title: Text(_text('Rekam aktivitas', 'Record activity'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: <Widget>[
            Icon(Icons.directions_run_rounded, size: 54, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              _text('Siap untuk bergerak?', 'Ready to move?'),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              widget.environment == RunEnvironment.indoor
                  ? _text('Waktu direkam tanpa GPS. Jarak bisa dimasukkan saat sesi selesai.', 'Time is tracked without GPS. You can enter the distance when the session ends.')
                  : _text('Pastikan izin lokasi aktif sebelum mulai di luar ruangan.', 'Make sure location permission is enabled before starting outdoors.'),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 18),
            if (widget.initialIntervalPlan == null) _buildIntervalSettings(),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _isStarting ? null : _startRun,
              icon: _isStarting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(_isStarting
                  ? _text('Menyiapkan aktivitas...', 'Preparing activity...')
                  : (_intervalModeSelected
                      ? _text('Mulai interval', 'Start intervals')
                      : _text('Mulai aktivitas', 'Start activity'))),
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
            Text(
              _text('MODE LATIHAN', 'WORKOUT MODE'),
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.9),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(_text('Lari interval', 'Interval run')),
              subtitle: Text(_text('Atur waktu lari cepat, pemulihan, dan jumlah ulangan.', 'Set the work interval, recovery time, and number of repetitions.')),
              value: _intervalModeSelected,
              onChanged: (bool value) => setState(() => _intervalModeSelected = value),
            ),
            if (_intervalModeSelected) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: _numberSettingField(_text('Kerja (detik)', 'Work (sec)'), _workSecondsController)),
                  const SizedBox(width: 10),
                  Expanded(child: _numberSettingField(_text('Pemulihan (detik)', 'Recovery (sec)'), _recoverySecondsController)),
                ],
              ),
              const SizedBox(height: 10),
              _numberSettingField(_text('Jumlah ulangan (1–30)', 'Repetitions (1–30)'), _repetitionsController),
              const SizedBox(height: 8),
              Text(
                _text('Contoh: 60 detik lari + 90 detik pemulihan, diulang 6 kali. Timer dimulai setelah GPS siap.', 'Example: 60 seconds of running + 90 seconds of recovery, repeated 6 times. The timer starts when GPS is ready.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4),
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

  String get _activityDisplayLabel => _activeIntervalPlan != null
      ? _text('Lari interval', 'Interval run')
      : widget.activityType == RunActivityType.walk
          ? _text('Berjalan', 'Walk')
          : _text('Lari', 'Run');

  Widget _buildAcquiringGps() {
    final bool countingDown = _countdownValue != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(countingDown ? _text('Mulai', 'Start') : _text('Bersiap', 'Get ready')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: countingDown
                    ? Container(
                        key: ValueKey<int>(_countdownValue!),
                        width: 160,
                        height: 160,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3,
                          ),
                        ),
                        child: Text(
                          '$_countdownValue',
                          style: TextStyle(
                            fontSize: 92,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    : const SizedBox(
                        key: ValueKey<String>('activity-preparing'),
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(strokeWidth: 5),
                      ),
              ),
              const SizedBox(height: 24),
              Text(
                countingDown ? _text('MULAI DALAM', 'STARTING IN') : _text('BERSIAP', 'GET READY'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: VoltWarna.teksPutih,
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
        title: Text('$_activityDisplayLabel • ${_text('Dalam ruangan', 'Indoor')}'),
        leading: IconButton(
          tooltip: _text('Keluar dari aktivitas', 'Exit activity'),
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
                child: _liveMetricsBuilder(() => Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.zero,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.directions_run_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(_formatDuration(_controller.elapsed), style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(paused ? _text('Dijeda', 'Paused') : _text('Aktivitas berlangsung', 'Activity in progress'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 22),
                      Text('${_controller.distanceKm.toStringAsFixed(2)} km', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(_text('Jarak dimasukkan setelah selesai', 'Distance can be entered when you finish'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                      if (_activeIntervalPlan != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _intervalPhaseCard(_activeIntervalPlan!, _controller.elapsed),
                      ],
                    ],
                  ),
                )),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: paused ? _controller.resumeRun : _controller.pauseRun,
                      icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                      label: Text(paused ? _text('Lanjutkan', 'Resume') : _text('Jeda', 'Pause')),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _finishRun,
                      icon: const Icon(Icons.stop_rounded),
                      label: Text(_text('Selesai', 'Finish')),
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
        title: Text(_text('Akhiri aktivitas?', 'End activity?')),
        content: Text(_text('Aktivitas yang belum diselesaikan tidak akan disimpan ke riwayat.', 'An unfinished activity will not be saved to your history.')),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(_text('Kembali', 'Keep going'))),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(_text('Akhiri', 'End activity'))),
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: ValueListenableBuilder<List<RunPoint>>(
              valueListenable: _liveMapRoute,
              builder: (BuildContext context, List<RunPoint> route, Widget? child) =>
                  RunRouteMapView(
                key: const ValueKey<String>('live-run-route-map-fullscreen'),
                route: route,
                laps: _controller.hundredMeterLaps,
                height: MediaQuery.sizeOf(context).height,
                followLastPoint: !paused,
                showIntervalSelector: true,
              ),
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
                          tooltip: _text('Tutup peta', 'Close map'),
                          onPressed: () => setState(() => _liveMapExpanded = false),
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _liveMetricsBuilder(() {
                        final String gpsAccuracy =
                            _formatAccuracy(_controller.gpsAccuracyMeters);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.84),
                            borderRadius: BorderRadius.zero,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                paused ? Icons.pause_circle : Icons.gps_fixed,
                                size: 16,
                                color: paused ? Colors.white70 : Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                paused ? 'AKTIVITAS DIJEDA' : 'AKURASI GPS • $gpsAccuracy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const Spacer(),
                _liveMetricsBuilder(() {
                  final double? pace = _controller.currentPaceSecondsPerKm ??
                      _controller.averagePaceSecondsPerKm;
                  final double? speedKmh =
                      pace != null && pace > 0 ? 3600.0 / pace : null;
                  final RunElevationStats elevation = _liveElevationStats.value;
                  final String netElevation =
                      '${elevation.netChangeMeters > 0 ? '+' : ''}'
                      '${elevation.netChangeMeters.toStringAsFixed(0)} m';
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 15, 12, 12),
                      decoration: BoxDecoration(
                        color: const Color(0xED101010),
                        borderRadius: BorderRadius.zero,
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
                              const Icon(Icons.speed, color: Colors.white70, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                speedKmh != null && speedKmh.isFinite && speedKmh >= 0.5 && speedKmh <= 35
                                    ? '${speedKmh.toStringAsFixed(1)} km/jam'
                                    : '-- km/jam',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.terrain, color: Colors.white70, size: 18),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  elevation.hasAltitudeData
                                      ? 'Selisih $netElevation'
                                      : 'Perubahan --',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
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
                                'Elevasi +${elevation.totalAscentMeters.toStringAsFixed(0)} m'
                                ' • Elevasi −${elevation.totalDescentMeters.toStringAsFixed(0)} m',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              _liveMapMiniMetric(
                                'LANGKAH',
                                _stepsThisActivity.toString(),
                              ),
                              _liveMapMiniMetric(
                                'CADENCE',
                                _cadenceSamples.isEmpty
                                    ? '--'
                                    : '${(_cadenceSamples.map((RunCadenceSample item) => item.cadenceSpm).reduce((double a, double b) => a + b) / _cadenceSamples.length).round()} spm',
                              ),
                              _liveMapMiniMetric(
                                'KALORI*',
                                '${(_controller.distanceKm * (widget.activityType == RunActivityType.walk ? 40 : 60)).round()} kcal',
                              ),
                            ],
                          ),
                          if (widget.environment == RunEnvironment.outdoor &&
                              widget.activityType == RunActivityType.run) ...<Widget>[
                            const SizedBox(height: 10),
                            _estimatedFinishCard(),
                            if (widget.targetDistanceKm != null) ...<Widget>[
                              const SizedBox(height: 8),
                              _customTargetEstimateCard(),
                            ],
                            if (widget.targetPaceSecondsPerKm != null) ...<Widget>[
                              const SizedBox(height: 8),
                              _targetPaceAdviceCard(),
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                }),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    10,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF101010),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white38,
                          borderRadius: BorderRadius.zero,
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
                              label: Text(paused ? _text('Lanjut', 'Resume') : _text('Jeda', 'Pause')),
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
                              label: Text(_text('Selesai', 'Finish')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Pilih interval split di peta; ketuk penanda untuk pace, kecepatan, dan elevasi.',
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
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMapMiniMetric(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _estimatedFinishCard() {
    final double distance = _controller.distanceKm;
    final double? pace = _controller.currentPaceSecondsPerKm ??
        _controller.averagePaceSecondsPerKm;
    if (distance < 0.3 ||
        pace == null ||
        !pace.isFinite ||
        pace <= 0 ||
        pace > 3600) {
      return const SizedBox.shrink();
    }

    const List<({double km, String label})> targets =
        <({double km, String label})>[
      (km: 1, label: '1 km'),
      (km: 10, label: '10 km'),
      (km: 20, label: '20 km'),
      (km: 21.0975, label: 'Half marathon'),
      (km: 42.195, label: 'Marathon'),
    ];
    // Hilangkan jarak yang sudah tercapai. Urutan estimasi berikutnya menjadi
    // 1 km, 10 km, 20 km, half marathon, lalu marathon.
    final List<({double km, String label})> upcoming = targets
        .where((target) => distance < target.km)
        .toList(growable: false);
    if (upcoming.isEmpty) return const SizedBox.shrink();

    final int slot =
        (DateTime.now().millisecondsSinceEpoch ~/ 6500) % upcoming.length;
    final ({double km, String label}) target = upcoming[slot];
    final int totalSeconds = (pace * target.km).round();
    final double remainingKm = math.max(0, target.km - distance).toDouble();
    final int remainingSeconds = (pace * remainingKm).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _text('ESTIMASI PADA PACE SEKARANG', 'ESTIMATE AT CURRENT PACE'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_targetLabel(target.km)} • ${_text('sekitar', 'about')} ${_formatDuration(Duration(seconds: totalSeconds))}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _text('Pace ${_formatPace(pace)}/km • sisa ${remainingKm.toStringAsFixed(2)} km atau ${_formatDuration(Duration(seconds: remainingSeconds))} perkiraan', 'Pace ${_formatPace(pace)}/km • ${remainingKm.toStringAsFixed(2)} km remaining, about ${_formatDuration(Duration(seconds: remainingSeconds))}'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _targetLabel(double distanceKm) {
    if (distanceKm == 21.0975) return _text('Setengah maraton', 'Half marathon');
    if (distanceKm == 42.195) return _text('Maraton', 'Marathon');
    return '${distanceKm == distanceKm.roundToDouble() ? distanceKm.toInt() : distanceKm} km';
  }

  Widget _customTargetEstimateCard() {
    final double? targetKm = widget.targetDistanceKm;
    if (targetKm == null) return const SizedBox.shrink();
    final double? pace = _controller.currentPaceSecondsPerKm ?? _controller.averagePaceSecondsPerKm;
    if (_controller.distanceKm < 0.3 || pace == null || !pace.isFinite || pace <= 0 || pace > 3600) {
      return const SizedBox.shrink();
    }
    final double remainingKm = math.max(0, targetKm - _controller.distanceKm).toDouble();
    final int finishSeconds = (pace * targetKm).round();
    final bool achieved = _controller.distanceKm >= targetKm;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: achieved
            ? VoltWarna.hijau.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: achieved ? VoltWarna.hijau : Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(achieved ? _text('TARGET HARI INI TERCAPAI', "TODAY'S TARGET REACHED") : _text('TARGET HARI INI', "TODAY'S TARGET"), style: TextStyle(color: achieved ? VoltWarna.hijau : Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
          const SizedBox(height: 5),
          Text(
            achieved
                ? _text('Jarak ${targetKm.toStringAsFixed(2)} km tercapai.', 'Target distance of ${targetKm.toStringAsFixed(2)} km reached.')
                : _text('Perkiraan total ${_formatDuration(Duration(seconds: finishSeconds))} • sisa ${remainingKm.toStringAsFixed(2)} km', 'Estimated finish ${_formatDuration(Duration(seconds: finishSeconds))} • ${remainingKm.toStringAsFixed(2)} km remaining'),
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _targetPaceAdviceCard() {
    final double? targetPace = widget.targetPaceSecondsPerKm;
    if (targetPace == null) return const SizedBox.shrink();

    final double? currentPace = _controller.currentPaceSecondsPerKm ??
        _controller.averagePaceSecondsPerKm;
    final bool enoughData = currentPace != null &&
        currentPace.isFinite &&
        currentPace > 0 &&
        currentPace <= 3600;
    final bool onTarget = enoughData && currentPace <= targetPace;
    final Color statusColor = !enoughData
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : onTarget
            ? VoltWarna.hijau
            : VoltWarna.merah;
    final String currentPaceText = enoughData ? _formatPace(currentPace) : '--:--';
    final String advice = onTarget
        ? _text('Pace memenuhi target. Pertahankan ritme selama masih terasa nyaman.', 'You are meeting your pace target. Keep it comfortable.')
        : _text('Pace saat ini lebih lambat dari target. Sesuaikan bertahap jika masih nyaman.', 'Your current pace is slower than the target. Adjust gradually only if it still feels comfortable.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: statusColor.withValues(alpha: 0.75)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            enoughData
                ? (onTarget
                    ? _text('PACE SESUAI TARGET', 'ON-TARGET PACE')
                    : _text('PERHATIKAN PACE', 'PACE CHECK'))
                : _text('TARGET PACE', 'TARGET PACE'),
            style: TextStyle(
              color: statusColor,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            enoughData
                ? _text('Target ${_formatPace(targetPace)}/km  •  Saat ini $currentPaceText/km', 'Target ${_formatPace(targetPace)}/km  •  Current $currentPaceText/km')
                : '${_text('Target', 'Target')} ${_formatPace(targetPace)}/km',
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          if (enoughData) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              advice,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveRunDetails({required bool paused}) {
    return Scaffold(
      appBar: AppBar(
        title: Text(paused ? '$_activityDisplayLabel ${_text('dijeda', 'paused')}' : '$_activityDisplayLabel ${_text('berlangsung', 'in progress')}'),
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
            _liveMetricsBuilder(() => _heroMetricCard()),
            if (_activeIntervalPlan != null) ...<Widget>[
              const SizedBox(height: 12),
              _liveMetricsBuilder(() =>
                  _intervalPhaseCard(_activeIntervalPlan!, _controller.elapsed)),
            ],
            if (widget.environment == RunEnvironment.outdoor &&
                widget.activityType == RunActivityType.run) ...<Widget>[
              const SizedBox(height: 10),
              _liveMetricsBuilder(() => _estimatedFinishCard()),
              if (widget.targetDistanceKm != null) ...<Widget>[
                const SizedBox(height: 8),
                _liveMetricsBuilder(() => _customTargetEstimateCard()),
              ],
              if (widget.targetPaceSecondsPerKm != null) ...<Widget>[
                const SizedBox(height: 8),
                _liveMetricsBuilder(() => _targetPaceAdviceCard()),
              ],
            ],
            const SizedBox(height: 12),
            _liveMetricsBuilder(() => Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: _text('WAKTU', 'TIME'),
                    value: _formatDuration(_controller.elapsed),
                    icon: Icons.timer_outlined,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: _text('PACE RATA-RATA', 'AVG PACE'),
                    value: _formatPace(_controller.averagePaceSecondsPerKm),
                    icon: Icons.speed,
                  ),
                ),
              ],
            )),
            const SizedBox(height: 10),
            _liveMetricsBuilder(() => Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: 'GPS',
                    value: _formatAccuracy(_controller.gpsAccuracyMeters),
                    icon: Icons.gps_fixed,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: _text('TITIK BERSIH', 'VALID GPS POINTS'),
                    value: '${(_controller.gpsCleanRatio * 100).round()}%',
                    icon: Icons.filter_alt,
                  ),
                ),
              ],
            )),
            const SizedBox(height: 10),
            _liveMetricsBuilder(() => Row(
              children: <Widget>[
                Expanded(child: _metricCard(label: _text('LANGKAH', 'STEPS'), value: _stepsThisActivity.toString(), icon: Icons.directions_walk_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(label: 'CADENCE', value: _cadenceSamples.isEmpty ? '--' : '${(_cadenceSamples.map((RunCadenceSample item) => item.cadenceSpm).reduce((double a, double b) => a + b) / _cadenceSamples.length).round()} spm', icon: Icons.speed_rounded)),
                const SizedBox(width: 10),
                Expanded(child: _metricCard(label: _text('KALORI*', 'CALORIES*'), value: '${(_controller.distanceKm * (widget.activityType == RunActivityType.walk ? 40 : 60)).round()}', icon: Icons.local_fire_department_outlined)),
              ],
            )),
            const SizedBox(height: 12),
            _liveMetricsBuilder(() => Column(
              children: <Widget>[
                _elevationStatsCard(_liveElevationStats.value),
                const SizedBox(height: 12),
                _splitCard(),
              ],
            )),
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
                    label: Text(paused ? _text('Lanjut', 'Resume') : _text('Jeda', 'Pause')),
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
                    label: Text(_text('Selesai', 'Finish')),
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

    final String routeActivityLabel = session.activityType == RunActivityType.walk
        ? _text('Berjalan', 'Walk')
        : session.intervalPlan != null
            ? _text('Lari interval', 'Interval run')
            : _text('Lari', 'Run');

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('Hasil aktivitas', 'Activity summary')),
        automaticallyImplyLeading: false,
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
              _routeMapCard(session.route, session.hundredMeterLaps, activityLabel: routeActivityLabel),
            ] else ...<Widget>[
              const SizedBox(height: 12),
              _infoCard(
                icon: Icons.directions_run_rounded,
                title: _text('Aktivitas dalam ruangan', 'Indoor activity'),
                text: _text('Jarak dicatat dari nilai yang dimasukkan saat sesi selesai. Peta dan elevasi GPS tidak tersedia untuk sesi ini.', 'Distance is based on the value entered at the end of the session. GPS maps and elevation are unavailable indoors.'),
              ),
            ],
            const SizedBox(height: 12),
            _elevationStatsCard(session.elevationStats),
            const SizedBox(height: 12),
            _metricCard(label: _text('JUMLAH LANGKAH', 'TOTAL STEPS'), value: session.totalSteps?.toString() ?? _text('Tidak tersedia', 'Unavailable'), icon: Icons.directions_walk_rounded),
            const SizedBox(height: 8),
            Row(children: <Widget>[
              Expanded(child: _metricCard(label: _text('CADENCE RATA-RATA', 'AVERAGE CADENCE'), value: session.averageCadenceSpm == null ? '--' : '${session.averageCadenceSpm!.round()} spm', icon: Icons.speed_rounded)),
              const SizedBox(width: 10),
              Expanded(child: _metricCard(label: _text('KALORI*', 'CALORIES*'), value: '${session.estimatedCalories.round()} kcal', icon: Icons.local_fire_department_outlined)),
            ]),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.only(left: 4), child: Text(_text('GRAFIK AKTIVITAS', 'ACTIVITY CHARTS'), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
            RunActivityCharts(session: session),
            const SizedBox(height: 12),
            _hundredMeterLapsCard(session),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _metricCard(
                    label: _text('WAKTU GERAK', 'MOVING TIME'),
                    value: session.movingTimeText,
                    icon: Icons.directions_run,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metricCard(
                    label: _text('PACE RATA-RATA', 'AVG PACE'),
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
                label: Text(_text('COBA SIMPAN LAGI', 'TRY SAVING AGAIN')),
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
        title: Text(_text('Rekam aktivitas', 'Record activity')),
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
              Text(
                _text('AKTIVITAS TIDAK DAPAT DIMULAI', 'ACTIVITY COULD NOT START'),
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
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (allowReset) ...<Widget>[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _controller.resetRun,
                  icon: const Icon(Icons.arrow_back),
                  label: Text(_text('KEMBALI', 'BACK')),
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
          title: Text(_text('Jarak aktivitas dalam ruangan', 'Indoor activity distance')),
          content: TextField(
            controller: distanceController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _text('Jarak (km)', 'Distance (km)'),
              hintText: _text('Contoh: 3,50', 'Example: 3.50'),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text('Lanjutkan sesi', 'Continue session')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(distanceController.text.trim()),
              child: Text(_text('Selesai', 'Finish')),
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
            SnackBar(content: Text(_text('Masukkan jarak 0 sampai 300 km.', 'Enter a distance between 0 and 300 km.'))),
          );
        }
        return;
      }
      indoorDistanceMeters = km * 1000;
    }

    final double distanceForValidation =
        indoorDistanceMeters ?? (_controller.distanceKm * 1000);
    final bool terlaluSingkat =
        _controller.elapsed < const Duration(seconds: 30) ||
        distanceForValidation < 100;

    if (terlaluSingkat) {
      if (_controller.status == RunStatus.running) {
        _controller.pauseRun();
      }
      final bool? tetapHentikan = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_text('Aktivitas terlalu singkat', 'Activity is too short')),
          content: const Text(
            'Aktivitas ini terlalu singkat dan tidak akan disimpan. '
            'Tetap hentikan aktivitas?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_text('Lanjutkan aktivitas', 'Continue activity')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_text('Hentikan tanpa menyimpan', 'Stop without saving')),
            ),
          ],
        ),
      );

      if (tetapHentikan != true) {
        if (shouldResumeOnCancel && mounted) _controller.resumeRun();
        return;
      }

      await _stepSubscription?.cancel();
      _stepSubscription = null;
      _controller.resetRun();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('Aktivitas dihentikan tanpa disimpan.', 'Activity stopped without saving.'))),
      );
      final VoidCallback? keluar = widget.onExit;
      if (keluar != null) keluar();
      return;
    }

    setState(() {
      _isSavingSession = true;
      _saveError = null;
      _personalRecordAchievements = <String>[];
    });

    final double? averageCadence = _cadenceSamples.isEmpty
        ? null
        : _cadenceSamples.map((RunCadenceSample sample) => sample.cadenceSpm).reduce((double a, double b) => a + b) / _cadenceSamples.length;
    _controller.updateCadenceMetrics(
      totalSteps: _stepsThisActivity > 0 ? _stepsThisActivity : null,
      averageCadenceSpm: averageCadence,
      maxCadenceSpm: _maxCadenceSpm > 0 ? _maxCadenceSpm : null,
      samples: List<RunCadenceSample>.unmodifiable(_cadenceSamples),
    );
    await _stepSubscription?.cancel();
    _stepSubscription = null;
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
        borderRadius: BorderRadius.zero,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border.all(color: VoltWarna.hijau.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'REKOR BARU',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 10),
          ..._personalRecordAchievements.map((String achievement) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('•  ', style: TextStyle(color: VoltWarna.hijau, fontWeight: FontWeight.w900)),
                    Expanded(child: Text(achievement, style: TextStyle(fontWeight: FontWeight.w700))),
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
    } catch (error) {
      if (mounted) {
        setState(() {
          _saveError = error is RunSyncException
              ? error.message
              : 'Aktivitas belum tersimpan. Periksa ruang penyimpanan lalu coba lagi.';
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
        ? 'Menyimpan aktivitas ke akun...'
        : _saveError ?? 'Aktivitas tersimpan di perangkat dan akun.';

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
            Text(
              _text('JARAK', 'DISTANCE'),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _controller.distanceKm.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 64,
                height: 0.95,
                fontWeight: FontWeight.w900,
              ),
            ),
            Text(
              'km',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    'PACE  ${_formatPace(_controller.currentPaceSecondsPerKm)} / km',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
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
                    color: VoltWarna.hijau.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.zero,
                  ),
                  child: Text(
                    'SPEED  ${_formatCurrentSpeed(_controller.currentPaceSecondsPerKm)} km/jam',
                    style: TextStyle(
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
            ? VoltWarna.kuning.withValues(alpha: 0.12)
            : VoltWarna.hijau.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: paused
              ? VoltWarna.kuning.withValues(alpha: 0.4)
              : VoltWarna.hijau.withValues(alpha: 0.4),
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
              style: TextStyle(
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
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              style: TextStyle(
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
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.zero,
              ),
              child: Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                Icon(
                  Icons.flag_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  _text('SPLIT PER KILOMETER', 'KILOMETER SPLITS'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (splits.isEmpty)
              Text(
                _text('Belum menyelesaikan 1 km.', 'No full kilometre split yet.'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: 1,
                            minHeight: 7,
                            backgroundColor:
                                Theme.of(context).colorScheme.surfaceContainerHighest,
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius:
                                BorderRadius.zero,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          split.paceText,
                          style: TextStyle(
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
              style: TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.w900,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              session.elapsedText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _intervalPhaseCard(IntervalRunPlan plan, Duration elapsed) {
    final IntervalPhase phase = plan.phaseAtProgress(
      elapsed: elapsed,
      distanceMeters: _controller.distanceKm * 1000,
    );
    final bool work = phase.stage == IntervalStage.work;
    final bool complete = phase.stage == IntervalStage.complete;
    final String title = complete
        ? 'INTERVAL SELESAI'
        : work
            ? 'FASE KERJA / LARI'
            : 'FASE PEMULIHAN';
    final int mins = phase.secondsRemaining ~/ 60;
    final int secs = phase.secondsRemaining % 60;
    final String remainingLabel = plan.measure == IntervalMeasure.time
        ? '$mins:${secs.toString().padLeft(2, '0')}'
        : '${(phase.distanceRemainingMeters ?? 0).round()} m';
    return Card(
      color: complete
          ? VoltWarna.hijau.withValues(alpha: 0.12)
          : work
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : VoltWarna.kuning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(
              complete ? Icons.check_circle : work ? Icons.directions_run : Icons.self_improvement,
              size: 30,
              color: complete ? VoltWarna.hijau : work ? Theme.of(context).colorScheme.primary : VoltWarna.kuning,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(complete
                      ? 'Selesai ${plan.repetitions} ulangan. Rekaman GPS tetap berjalan sampai kamu menekan Selesai.'
                      : 'Ulangan ${phase.repetition}/${plan.repetitions}'),
                ],
              ),
            ),
            if (!complete)
              Text(remainingLabel,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _routeMapCard(
    List<RunPoint> route,
    List<RunLap100m> laps, {
    required String activityLabel,
  }) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              _text('PETA RUTE ${activityLabel.toUpperCase()}', '${activityLabel.toUpperCase()} ROUTE MAP'),
              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: RunRouteMapView(
              route: route,
              laps: laps,
              height: 290,
              showIntervalSelector: true,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _text('Pilih jarak split melalui menu peta. Garis berwarna menunjukkan pace, sementara rute asli tetap tersimpan lokal.', 'Choose a split distance from the map menu. Colored segments show pace; the original route remains saved on this device.'),
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMapSection({required bool paused}) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          ListTile(
            leading: Icon(Icons.map_outlined, color: Theme.of(context).colorScheme.primary),
            title: Text(
              _text('PETA ${_activityDisplayLabel.toUpperCase()} • LIVE', '${_activityDisplayLabel.toUpperCase()} ROUTE • LIVE'),
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              paused
                  ? _text('Perekaman dijeda', 'Recording paused')
                  : _text('Rute dan titik kecepatan diperbarui saat GPS masuk', 'Route and pace points update as GPS data arrives'),
            ),
            trailing: IconButton(
              tooltip: _liveMapExpanded ? _text('Tutup peta', 'Close map') : _text('Buka peta', 'Open map'),
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
              child: ValueListenableBuilder<List<RunPoint>>(
                valueListenable: _liveMapRoute,
                builder: (BuildContext context, List<RunPoint> route, Widget? child) =>
                    RunRouteMapView(
                  key: const ValueKey<String>('live-run-route-map'),
                  route: route,
                  laps: _controller.hundredMeterLaps,
                  height: 300,
                  followLastPoint: !paused,
                  showIntervalSelector: true,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _elevationStatsCard(RunElevationStats stats) {
    String signed(double value) => '${value > 0 ? '+' : ''}${value.round()} m';

    Widget metric(String label, String value) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).hintColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
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
            Text(_text('ELEVASI', 'ELEVATION'), style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            if (!stats.hasAltitudeData)
              Text(
                'Data elevasi GPS tidak tersedia.',
                style: TextStyle(color: Theme.of(context).hintColor),
              )
            else
              Row(
                children: <Widget>[
                  metric('ELEVASI +', signed(stats.totalAscentMeters)),
                  metric(
                    'ELEVASI −',
                    '−${stats.totalDescentMeters.round()} m',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _hundredMeterLapsCard(RunSession session) {
    final List<RunLap100m> laps = session.hundredMeterLaps;
    double? elevasiAwal;
    for (final RunLap100m lap in laps) {
      if (lap.altitudeMeters != null && lap.altitudeMeters!.isFinite) {
        elevasiAwal = lap.altitudeMeters;
        break;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _text('PACE TIAP 100 METER', 'PACE EVERY 100 METRES'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _text('Pace, kecepatan, elevasi tiap 100 m.', 'Pace, speed, and elevation every 100 metres.'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (laps.isEmpty)
              Text(_text('Belum ada segmen 100 m yang valid.', 'No valid 100 m segments yet.'))
            else
              ...laps.map((RunLap100m lap) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: <Widget>[
                        SizedBox(width: 62, child: Text('${lap.distanceMeters.round()} m', style: TextStyle(fontWeight: FontWeight.w800))),
                        Expanded(child: Text(_formatDuration(Duration(milliseconds: lap.durationMilliseconds)))),
                        SizedBox(width: 76, child: Text(lap.speedKmh == null ? '--' : '${lap.speedKmh!.toStringAsFixed(1)} km/h', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.w900))),
                        const SizedBox(width: 10),
                        SizedBox(width: 55, child: Text(lap.paceSecondsPerKm == null ? '--' : _formatPace(lap.paceSecondsPerKm), textAlign: TextAlign.end, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                        const SizedBox(width: 6),
                        SizedBox(width: 48, child: Text(lap.altitudeMeters == null || elevasiAwal == null ? '--' : '${lap.altitudeMeters! - elevasiAwal >= 0 ? '+' : ''}${(lap.altitudeMeters! - elevasiAwal).round()} m', textAlign: TextAlign.end, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11))),
                      ],
                    ),
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
            Text(
              _text('SPLIT PER KM', 'KILOMETRE SPLITS'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            if (session.splits.isEmpty)
              Text(
                _text('Belum mencapai 1 km.', 'A full kilometre has not been completed yet.'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                            style: TextStyle(
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
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          split.paceText,
                          style: TextStyle(
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
