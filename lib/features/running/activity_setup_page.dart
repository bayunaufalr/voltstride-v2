// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../services/app_language_service.dart';

import '../../services/lokasi_service.dart';
import 'services/heart_rate_service.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';
import 'services/run_history_repository.dart';
import 'services/training_recommendation_service.dart';

class ActivityStartConfig {
  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? intervalPlan;
  final double? targetDistanceKm;
  final double? targetPaceSecondsPerKm;
  final bool paceNotificationsEnabled;
  final String? activityDetails;
  final int? targetDurationMinutes;
  final String? plannedWorkoutTitle;
  final String? plannedWorkoutDescription;

  const ActivityStartConfig({
    required this.activityType,
    required this.environment,
    required this.intervalPlan,
    this.targetDistanceKm,
    this.targetPaceSecondsPerKm,
    this.paceNotificationsEnabled = true,
    this.activityDetails,
    this.targetDurationMinutes,
    this.plannedWorkoutTitle,
    this.plannedWorkoutDescription,
  });
}

enum _ActivityMode { run, interval, walk, cycle, hiit }

class ActivitySetupPage extends StatefulWidget {
  const ActivitySetupPage({
    super.key,
    required this.onStart,
    this.sessionAlreadyActive = false,
  });

  final ValueChanged<ActivityStartConfig> onStart;
  final bool sessionAlreadyActive;

  @override
  State<ActivitySetupPage> createState() => ActivitySetupPageState();
}

class ActivitySetupPageState extends State<ActivitySetupPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);
  RunEnvironment _environment = RunEnvironment.outdoor;
  _ActivityMode _mode = _ActivityMode.run;
  IntervalMeasure _intervalMeasure = IntervalMeasure.time;
  RunPoint? _currentLocation;
  bool _loadingLocation = false;
  String? _locationMessage;

  final TextEditingController _workSeconds = TextEditingController(text: '60');
  final TextEditingController _recoverySeconds = TextEditingController(text: '90');
  final TextEditingController _repetitions = TextEditingController(text: '6');
  final TextEditingController _workDistance = TextEditingController(text: '400');
  final TextEditingController _recoveryDistance = TextEditingController(text: '200');
  final TextEditingController _targetDistanceKm = TextEditingController();
  final TextEditingController _targetPace = TextEditingController();
  final TextEditingController _hiitDetails = TextEditingController();
  bool _paceNotificationsEnabled = true;
  bool _searchingHeartRate = false;
  String? _heartRateDeviceName;
  bool _showTrainingPlanner = false;
  bool _loadingRecommendations = false;
  TrainingGoal _selectedTrainingGoal = TrainingGoal.endurance;
  final TextEditingController _trainingDuration =
      TextEditingController(text: '30');
  TrainingRecommendationOverview? _recommendationOverview;

  @override
  void initState() {
    super.initState();
    _heartRateDeviceName = HeartRateService.instance.connectedDeviceName.value;
  }

  @override
  void dispose() {
    _workSeconds.dispose();
    _recoverySeconds.dispose();
    _repetitions.dispose();
    _workDistance.dispose();
    _recoveryDistance.dispose();
    _targetDistanceKm.dispose();
    _targetPace.dispose();
    _hiitDetails.dispose();
    _trainingDuration.dispose();
    super.dispose();
  }

  Future<void> loadLocation() async {
    if (_environment == RunEnvironment.indoor || _loadingLocation) return;
    setState(() {
      _loadingLocation = true;
      _locationMessage = null;
    });
    try {
      final bool enabled = await LokasiService.cekLayananAktif();
      if (!enabled) {
        if (mounted) setState(() => _locationMessage = _text('Aktifkan lokasi perangkat untuk melihat posisi saat ini.', 'Turn on your device location to see your current position.'));
        await Geolocator.openLocationSettings();
        return;
      }
      final bool permission = await LokasiService.mintaIzin();
      if (!permission) {
        if (mounted) setState(() => _locationMessage = _text('Izin lokasi diperlukan untuk aktivitas luar ruangan.', 'Location permission is required for outdoor activities.'));
        await permissions.openAppSettings();
        return;
      }
      final Position? position = await LokasiService.ambilSatuTitik();
      if (!mounted) return;
      if (position == null || !position.latitude.isFinite || !position.longitude.isFinite) {
        setState(() => _locationMessage = _text('Posisi belum tersedia. Coba di area terbuka.', 'Your position is unavailable. Try an open area.'));
        return;
      }
      setState(() {
        _currentLocation = RunPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: position.timestamp,
          accuracyMeters: position.accuracy,
          altitudeMeters: position.altitude.isFinite ? position.altitude : null,
          startsNewSegment: true,
        );
        _locationMessage = _text('Lokasi ditemukan • akurasi ±${position.accuracy.round()} m', 'Location found • accuracy ±${position.accuracy.round()} m');
      });
    } catch (_) {
      if (mounted) setState(() => _locationMessage = _text('Tidak dapat membaca lokasi. Coba lagi.', 'Unable to read location. Try again.'));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void closeTrainingPlanner() {
    if (!_showTrainingPlanner || !mounted) return;
    setState(() => _showTrainingPlanner = false);
  }

  void _openTrainingPlanner() {
    setState(() {
      _showTrainingPlanner = true;
      _recommendationOverview = null;
      _selectedTrainingGoal = TrainingGoal.endurance;
    });
  }

  Future<void> _generateRecommendations() async {
    final int? duration = int.tryParse(_trainingDuration.text.trim());
    if (duration == null || duration < 10 || duration > 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Masukkan durasi antara 10 sampai 60 menit.',
            'Enter a duration between 10 and 60 minutes.',
          )),
        ),
      );
      return;
    }

    setState(() {
      _loadingRecommendations = true;
      _recommendationOverview = null;
    });
    try {
      final List<RunSession> history =
          await RunHistoryRepository.instance.getAll(limit: 100);
      final TrainingRecommendationOverview result =
          TrainingRecommendationService.generate(
        history: history,
        goal: _selectedTrainingGoal,
        durationMinutes: duration,
      );
      if (!mounted) return;
      setState(() => _recommendationOverview = result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_text(
              'Data latihan belum dapat dibaca. Coba lagi.',
              'Training data could not be loaded. Try again.',
            )),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingRecommendations = false);
    }
  }

  String _trainingGoalLabel(TrainingGoal goal) => switch (goal) {
        TrainingGoal.endurance => _text('Daya tahan', 'Endurance'),
        TrainingGoal.pace => _text('Pace', 'Pace'),
        TrainingGoal.consistency => _text('Konsistensi', 'Consistency'),
        TrainingGoal.generalFitness =>
          _text('Kebugaran umum', 'General fitness'),
      };

  String _recommendationTitle(TrainingPlanKind kind) => switch (kind) {
        TrainingPlanKind.easyRunWalk =>
          _text('Lari-jalan ringan', 'Easy run-walk'),
        TrainingPlanKind.controlledIntervals =>
          _text('Interval terkontrol', 'Controlled intervals'),
        TrainingPlanKind.steadyRun =>
          _text('Lari stabil', 'Steady run'),
        TrainingPlanKind.comfortableWalk =>
          _text('Jalan nyaman', 'Comfortable walk'),
        TrainingPlanKind.easyCycling =>
          _text('Sepeda santai', 'Easy cycling'),
        TrainingPlanKind.lowImpactHiit =>
          _text('HIIT berdampak rendah', 'Low-impact HIIT'),
      };

  String _recommendationDescription(TrainingRecommendation recommendation) {
    switch (recommendation.kind) {
      case TrainingPlanKind.easyRunWalk:
        return _text(
          'Jogging ringan pada fase kerja, lalu berjalan pada fase pemulihan.',
          'Jog easily during work phases, then walk during recovery phases.',
        );
      case TrainingPlanKind.controlledIntervals:
        return _text(
          'Lari singkat dengan usaha terkendali, diselingi pemulihan berjalan.',
          'Short controlled running efforts separated by walking recovery.',
        );
      case TrainingPlanKind.steadyRun:
        return _text(
          'Pertahankan usaha nyaman dan ritme yang masih memungkinkan berbicara.',
          'Keep a comfortable effort and a pace that still allows conversation.',
        );
      case TrainingPlanKind.comfortableWalk:
        return _text(
          'Berjalan dengan langkah nyaman dan ritme stabil.',
          'Walk at a comfortable, steady rhythm.',
        );
      case TrainingPlanKind.easyCycling:
        return _text(
          'Bersepeda santai dengan kayuhan stabil dan rute yang aman.',
          'Cycle at an easy, steady effort on a safe route.',
        );
      case TrainingPlanKind.lowImpactHiit:
        return _text(
          'Gunakan gerakan berdampak rendah yang sudah dikuasai, dengan pemulihan penuh.',
          'Use familiar low-impact movements and take the full recovery periods.',
        );
    }
  }

  String _intensityDescription(TrainingLoadLevel level) => switch (level) {
        TrainingLoadLevel.recovery => _text(
            'Intensitas diturunkan karena sesi terakhir masih dekat atau aktivitas 7 hari terakhir cukup banyak.',
            'Intensity is reduced because the last session was recent or activity over the last 7 days was substantial.',
          ),
        TrainingLoadLevel.starter => _text(
            'Data masih terbatas atau belum cukup konsisten. Rekomendasi dimulai dari intensitas ringan.',
            'Data is limited or not yet consistent. Recommendations start at an easy intensity.',
          ),
        TrainingLoadLevel.building => _text(
            'Riwayat latihan menunjukkan pola yang cukup konsisten. Menu tetap dibatasi pada usaha ringan hingga sedang.',
            'Your recent history is fairly consistent. Sessions remain limited to easy-to-moderate effort.',
          ),
      };

  void _startRecommendedTraining(TrainingRecommendation recommendation) {
    if (widget.sessionAlreadyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Selesaikan sesi aktif sebelum memulai latihan baru.',
            'Finish the active session before starting a new workout.',
          )),
        ),
      );
      return;
    }

    final String title = _recommendationTitle(recommendation.kind);
    final String description = _recommendationDescription(recommendation);
    setState(() => _showTrainingPlanner = false);
    widget.onStart(
      ActivityStartConfig(
        activityType: recommendation.activityType,
        environment: recommendation.activityType == RunActivityType.hiit
            ? RunEnvironment.indoor
            : _environment,
        intervalPlan: recommendation.intervalPlan,
        paceNotificationsEnabled: false,
        activityDetails: '$title. ${recommendation.activityDetails}',
        targetDurationMinutes: recommendation.durationMinutes,
        plannedWorkoutTitle: title,
        plannedWorkoutDescription: description,
      ),
    );
  }

  Widget _buildTrainingPlanner() {
    final TrainingRecommendationOverview? overview = _recommendationOverview;
    final Color secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _text('Kembali', 'Back'),
          onPressed: closeTrainingPlanner,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_text('Latihan personal', 'Personal workout')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: <Widget>[
            Text(
              _text('Apa tujuan latihanmu?', 'What is your training goal?'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TrainingGoal.values.map((TrainingGoal goal) {
                return ChoiceChip(
                  label: Text(_trainingGoalLabel(goal)),
                  selected: _selectedTrainingGoal == goal,
                  onSelected: (bool selected) {
                    if (selected) {
                      setState(() {
                        _selectedTrainingGoal = goal;
                        _recommendationOverview = null;
                      });
                    }
                  },
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 22),
            Text(
              _text('Ingin latihan berapa menit?', 'How many minutes do you want to train?'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _trainingDuration,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                labelText: _text('Durasi (10–60 menit)', 'Duration (10–60 minutes)'),
                suffixText: _text('menit', 'min'),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _recommendationOverview = null),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadingRecommendations ? null : _generateRecommendations,
              icon: _loadingRecommendations
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_text('Buat menu latihan', 'Create workout options')),
            ),
            if (overview != null) ...<Widget>[
              const SizedBox(height: 22),
              Text(
                _text('Menu latihan yang disarankan', 'Recommended workouts'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                overview.hasRecentData
                    ? _text(
                        'Berdasarkan ${overview.recentSessionCount} sesi dalam 30 hari dan ${overview.minutesLastSevenDays} menit aktivitas dalam 7 hari terakhir.',
                        'Based on ${overview.recentSessionCount} sessions in 30 days and ${overview.minutesLastSevenDays} active minutes in the last 7 days.',
                      )
                    : _text(
                        'Belum ada riwayat latihan terbaru. Menu awal dibuat ringan dan akan lebih personal setelah beberapa sesi tersimpan.',
                        'There is no recent training history yet. Starter options are kept easy and become more personal after sessions are saved.',
                      ),
                style: TextStyle(color: secondary, height: 1.4),
              ),
              const SizedBox(height: 6),
              Text(
                _intensityDescription(overview.loadLevel),
                style: TextStyle(color: secondary, fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 12),
              ...overview.options.map(_recommendationCard),
              const SizedBox(height: 8),
              Text(
                _text(
                  'Gunakan intensitas yang terasa nyaman. Menu ini merupakan panduan umum, bukan penilaian medis. Hentikan latihan bila merasa nyeri, pusing, atau tidak enak badan.',
                  'Keep the effort comfortable. These options are general guidance, not a medical assessment. Stop if you feel pain, dizzy, or unwell.',
                ),
                style: TextStyle(color: secondary, fontSize: 11, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _recommendationCard(TrainingRecommendation recommendation) {
    final Color secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final IntervalRunPlan? interval = recommendation.intervalPlan;
    final String intervalLabel = interval == null
        ? ''
        : _text(
            '${interval.workSeconds} dtk kerja • ${interval.recoverySeconds} dtk pulih • ${interval.repetitions} ulangan',
            '${interval.workSeconds}s work • ${interval.recoverySeconds}s recovery • ${interval.repetitions} rounds',
          );
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _recommendationTitle(recommendation.kind),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${recommendation.durationMinutes} ${_text('menit', 'minutes')} • ${recommendation.intensity}',
              style: TextStyle(color: secondary, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(_recommendationDescription(recommendation)),
            if (intervalLabel.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(intervalLabel, style: TextStyle(color: secondary, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: widget.sessionAlreadyActive
                    ? null
                    : () => _startRecommendedTraining(recommendation),
                child: Text(_text('Pilih dan mulai', 'Choose and start')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showTrainingPlanner) return _buildTrainingPlanner();
    final bool indoor = _environment == RunEnvironment.indoor;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(_text('Rekam aktivitas', 'Record activity'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            Text(
              _text('Pilih aktivitas', 'Choose an activity'),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            if (indoor)
              _indoorMapCard()
            else ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.zero,
                child: RunRouteMapView(
                  key: ValueKey<String>('activity-start-${_currentLocation?.timestamp.toIso8601String() ?? 'empty'}'),
                  route: _currentLocation == null ? const <RunPoint>[] : <RunPoint>[_currentLocation!],
                  laps: const <RunLap100m>[],
                  height: 240,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: Text(_locationMessage ?? _text('Peta dan posisi GPS sebelum mulai.', 'Map and GPS position before you start.'), style: TextStyle(color: teksSekunder, fontSize: 12))),
                  IconButton(
                    tooltip: _text('Perbarui lokasi', 'Refresh location'),
                    onPressed: _loadingLocation ? null : loadLocation,
                    icon: _loadingLocation
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _sectionTitle(_text('Lokasi aktivitas', 'Activity location')),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.outdoor,
                  title: _text('Luar ruangan', 'Outdoor'),
                  subtitle: 'GPS',
                  onTap: () {
                    setState(() => _environment = RunEnvironment.outdoor);
                    loadLocation();
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.indoor,
                  title: _text('Dalam ruangan', 'Indoor'),
                  subtitle: _text('Jarak manual', 'Manual distance'),
                  onTap: () => setState(() {
                    _environment = RunEnvironment.indoor;
                    _currentLocation = null;
                    _locationMessage = null;
                  }),
                )),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle(_text('Jenis aktivitas', 'Activity type')),
            const SizedBox(height: 10),
            _choiceCard(
              selected: _mode == _ActivityMode.run,
              title: _text('Lari biasa', 'Run'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.run),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.interval,
              title: _text('Lari interval', 'Interval run'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.interval),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.walk,
              title: _text('Berjalan', 'Walk'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.walk),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.cycle,
              title: _text('Bersepeda', 'Cycling'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.cycle),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.hiit,
              title: 'HIIT',
              horizontal: true,
              onTap: () => setState(() {
                _mode = _ActivityMode.hiit;
                _intervalMeasure = IntervalMeasure.time;
              }),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: widget.sessionAlreadyActive ? null : _openTrainingPlanner,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(_text(
                'Susun latihan dari data saya',
                'Build a workout from my data',
              )),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            if (_mode == _ActivityMode.run || _mode == _ActivityMode.interval)
              _sectionTitle(_text('Target aktivitas (opsional)', 'Activity targets (optional)')),
            const SizedBox(height: 8),
            if (_mode == _ActivityMode.run || _mode == _ActivityMode.interval)
              Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _targetDistanceKm,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: _text('Jarak target (km)', 'Target distance (km)'),
                            hintText: '5,0',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _targetPace,
                          keyboardType: TextInputType.text,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                          ],
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: _text('Target pace rata-rata (m:ss/km)', 'Target average pace (m:ss/km)'),
                            hintText: '6:00',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _paceNotificationsEnabled,
                    onChanged: (bool value) => setState(
                      () => _paceNotificationsEnabled = value,
                    ),
                    title: Text(_text('Pacer setiap menit', 'Minute-by-minute pacer')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _searchingHeartRate ? null : _toggleHeartRateDevice,
              icon: _searchingHeartRate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      HeartRateService.instance.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.favorite_border_rounded,
                    ),
              label: Text(
                _searchingHeartRate
                    ? _text('Mencari perangkat HR...', 'Scanning for HR devices...')
                    : HeartRateService.instance.isConnected
                        ? _text('Putuskan ${_heartRateDeviceName ?? 'sensor HR'}', 'Disconnect ${_heartRateDeviceName ?? 'HR sensor'}')
                        : _text('Sambungkan sensor HR Bluetooth', 'Connect a Bluetooth HR sensor'),
              ),
            ),
            Text(
              _text(
                'Mendukung sensor Bluetooth yang menyediakan layanan Heart Rate standar. Sebagian jam pintar perlu menyalakan fitur siaran detak jantung.',
                'Supports Bluetooth sensors exposing the standard Heart Rate service. Some smartwatches require heart-rate broadcast to be enabled.',
              ),
              style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.35),
            ),
            if (_mode == _ActivityMode.hiit) ...<Widget>[
              const SizedBox(height: 14),
              TextField(
                controller: _hiitDetails,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _text('Detail latihan HIIT', 'HIIT workout details'),
                  hintText: _text('Contoh: squat jump, burpee, mountain climber', 'Example: squat jump, burpee, mountain climber'),
                ),
              ),
            ],
            if (_mode == _ActivityMode.interval || _mode == _ActivityMode.hiit) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _text('Pengaturan interval', 'Interval settings'),
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    if (_mode == _ActivityMode.interval) SegmentedButton<IntervalMeasure>(
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            return states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface;
                          },
                        ),
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            return states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surface;
                          },
                        ),
                        side: WidgetStatePropertyAll<BorderSide?>(
                          BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        shape: const WidgetStatePropertyAll<OutlinedBorder?>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      segments: <ButtonSegment<IntervalMeasure>>[
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.time,
                          label: Text(_text('Berdasarkan waktu', 'By time')),
                        ),
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.distance,
                          label: Text(_text('Berdasarkan jarak', 'By distance')),
                        ),
                      ],
                      selected: <IntervalMeasure>{_intervalMeasure},
                      onSelectionChanged: (Set<IntervalMeasure> value) {
                        setState(() => _intervalMeasure = value.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_mode == _ActivityMode.hiit || _intervalMeasure == IntervalMeasure.time) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: _numberField(_text('Kerja (detik)', 'Work (seconds)'), _workSeconds)),
                          const SizedBox(width: 10),
                          Expanded(child: _numberField(_text('Pulih (detik)', 'Recovery (seconds)'), _recoverySeconds)),
                        ],
                      ),
                    ] else ...<Widget>[
                      if (indoor)
                        Text(
                          _text('Interval berbasis jarak membutuhkan jarak GPS selama sesi. Pilih Luar ruangan untuk memakai mode ini.', 'Distance-based intervals need GPS distance during the session. Select Outdoor to use this mode.'),
                          style: TextStyle(color: teksSekunder, fontSize: 12),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(child: _numberField(_text('Kerja (meter)', 'Work (meters)'), _workDistance)),
                            const SizedBox(width: 10),
                            Expanded(child: _numberField(_text('Pulih (meter)', 'Recovery (meters)'), _recoveryDistance)),
                          ],
                        ),
                    ],
                    const SizedBox(height: 10),
                    _numberField(_text('Jumlah ulangan', 'Repetitions'), _repetitions),
                  ],
                ),
              ),
            ],
            if (indoor) ...<Widget>[
              const SizedBox(height: 12),
              Text(_text('Mode dalam ruangan tidak meminta GPS. Saat selesai, masukkan jarak dari treadmill atau alat yang digunakan.', 'Indoor mode does not use GPS. Enter the distance from your treadmill or equipment when you finish.'), style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4)),
            ],
            const SizedBox(height: 20),
            if (widget.sessionAlreadyActive) ...<Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border.all(color: Theme.of(context).colorScheme.outline),
                ),
                child: Text(
                  _text(
                    'Aktivitas lain tidak dapat dimulai sebelum sesi aktif selesai.',
                    'Another activity cannot start until the active session is finished.',
                  ),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: widget.sessionAlreadyActive ? null : _start,
              child: Text(widget.sessionAlreadyActive
                  ? _text('Sesi sedang berjalan', 'Session in progress')
                  : _text('Mulai aktivitas', 'Start activity')),
            ),
            const SizedBox(height: 8),
            Text(_text('Untuk GPS yang lebih akurat, mulai di area terbuka.', 'For better GPS accuracy, start in an open area.'), textAlign: TextAlign.center, style: TextStyle(color: teksSekunder, fontSize: 11, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _indoorMapCard() {
    final Color teks = Theme.of(context).colorScheme.onSurface;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: 210,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            _text('Mode dalam ruangan', 'Indoor mode'),
            style: TextStyle(
              color: teks,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _text('GPS dinonaktifkan. Waktu tetap direkam; jarak dapat dimasukkan saat selesai.', 'GPS is disabled. Time is still recorded; distance can be entered when you finish.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool horizontal = false,
  }) {
    final Color teks = Theme.of(context).colorScheme.onSurface;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    final Color warnaBorder = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: warnaBorder, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: teks,
                      fontWeight: FontWeight.w800,
                      fontSize: horizontal ? 14 : 13,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: teksSekunder, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16));

  double? _parsePace(String raw) {
    final Match? match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(raw.trim());
    if (match == null) return null;
    final int minutes = int.parse(match.group(1)!);
    final int seconds = int.parse(match.group(2)!);
    final int totalSeconds = minutes * 60 + seconds;
    if (totalSeconds < 120 || totalSeconds > 3600) return null;
    return totalSeconds.toDouble();
  }

  Future<void> _toggleHeartRateDevice() async {
    final HeartRateService service = HeartRateService.instance;
    if (service.isConnected) {
      await service.disconnect();
      if (mounted) {
        setState(() => _heartRateDeviceName = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Sensor HR terputus.', 'HR sensor disconnected.'))),
        );
      }
      return;
    }

    setState(() => _searchingHeartRate = true);
    try {
      final List<HeartRateDevice> devices = await service.scanForDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                'Sensor tidak ditemukan. Pastikan sensor aktif dan menyiarkan Heart Rate Bluetooth.',
                'No sensor found. Make sure it is on and advertising Bluetooth Heart Rate.',
              ),
            ),
          ),
        );
        return;
      }

      final HeartRateDevice? selected = await showModalBottomSheet<HeartRateDevice>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                _text('Pilih sensor detak jantung', 'Choose a heart-rate sensor'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...devices.map(
                (HeartRateDevice device) => ListTile(
                  leading: const Icon(Icons.bluetooth_rounded),
                  title: Text(device.name),
                  subtitle: Text('Signal ${device.rssi} dBm'),
                  onTap: () => Navigator.of(sheetContext).pop(device),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;

      await service.connect(selected);
      if (!mounted) return;
      setState(() => _heartRateDeviceName = selected.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Terhubung ke ${selected.name}.', 'Connected to ${selected.name}.'),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('Sensor HR gagal disambungkan: $error', 'Could not connect to the HR sensor: $error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searchingHeartRate = false);
    }
  }

  void _start() {
    if (widget.sessionAlreadyActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Sesi masih berlangsung. Kembali ke sesi aktif atau selesaikan dulu.',
            'A session is already active. Resume it or finish it first.',
          )),
        ),
      );
      return;
    }
    double? targetDistanceKm;
    double? targetPaceSecondsPerKm;
    final bool supportsRunTargets =
        _mode == _ActivityMode.run || _mode == _ActivityMode.interval;
    final String targetDistanceText = supportsRunTargets
        ? _targetDistanceKm.text.trim()
        : '';
    final String targetPaceText = supportsRunTargets
        ? _targetPace.text.trim()
        : '';
    if (targetDistanceText.isNotEmpty || targetPaceText.isNotEmpty) {
      if (targetDistanceText.isEmpty || targetPaceText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Isi jarak dan pace target, atau kosongkan keduanya.', 'Enter both target distance and pace, or leave both empty.'))),
        );
        return;
      }
      targetDistanceKm = double.tryParse(targetDistanceText.replaceAll(',', '.'));
      targetPaceSecondsPerKm = _parsePace(targetPaceText);
      if (targetDistanceKm == null ||
          !targetDistanceKm.isFinite ||
          targetDistanceKm < 0.1 ||
          targetDistanceKm > 100 ||
          targetPaceSecondsPerKm == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Jarak target harus 0,1–100 km dan pace gunakan format m:ss/km, misalnya 6:00.', 'Target distance must be 0.1–100 km and pace must use m:ss/km, for example 6:00.'))),
        );
        return;
      }
    }

    if ((_mode == _ActivityMode.run || _mode == _ActivityMode.interval) &&
        _paceNotificationsEnabled && targetPaceSecondsPerKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Isi jarak dan target pace rata-rata untuk mengaktifkan pacer.',
              'Enter the target distance and average pace to enable the pacer.',
            ),
          ),
        ),
      );
      return;
    }

    IntervalRunPlan? plan;
    if (_mode == _ActivityMode.interval || _mode == _ActivityMode.hiit) {
      final int? repetitions = int.tryParse(_repetitions.text.trim());
      if (repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Jumlah ulangan harus 1–30.', 'Repetitions must be between 1 and 30.'))),
        );
        return;
      }

      if (_mode == _ActivityMode.hiit || _intervalMeasure == IntervalMeasure.time) {
        final int? work = int.tryParse(_workSeconds.text.trim());
        final int? recovery = int.tryParse(_recoverySeconds.text.trim());
        if (work == null || work < 10 || work > 3600 ||
            recovery == null || recovery < 5 || recovery > 3600) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_text('Kerja harus 10–3600 detik, pemulihan 5–3600 detik.', 'Work must be 10–3600 seconds and recovery 5–3600 seconds.')),
            ),
          );
          return;
        }
        plan = IntervalRunPlan(
          workSeconds: work,
          recoverySeconds: recovery,
          repetitions: repetitions,
          measure: IntervalMeasure.time,
        );
      } else {
        final double? workMeters = double.tryParse(_workDistance.text.trim());
        final double? recoveryMeters = double.tryParse(_recoveryDistance.text.trim());
        if (_environment == RunEnvironment.indoor) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_text('Interval berbasis jarak saat ini membutuhkan GPS luar ruangan.', 'Distance-based intervals require outdoor GPS.')),
            ),
          );
          return;
        }
        if (workMeters == null || workMeters < 50 || workMeters > 20000 ||
            recoveryMeters == null || recoveryMeters < 0 || recoveryMeters > 20000) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_text('Jarak kerja 50–20.000 m dan pemulihan 0–20.000 m.', 'Work distance must be 50–20,000 m and recovery distance 0–20,000 m.')),
            ),
          );
          return;
        }
        plan = IntervalRunPlan(
          workSeconds: 60,
          recoverySeconds: 90,
          repetitions: repetitions,
          measure: IntervalMeasure.distance,
          workDistanceMeters: workMeters,
          recoveryDistanceMeters: recoveryMeters,
        );
      }
    }
    widget.onStart(ActivityStartConfig(
      activityType: _mode == _ActivityMode.walk
          ? RunActivityType.walk
          : _mode == _ActivityMode.cycle
              ? RunActivityType.cycle
              : _mode == _ActivityMode.hiit
                  ? RunActivityType.hiit
                  : RunActivityType.run,
      environment: _environment,
      intervalPlan: plan,
      targetDistanceKm: targetDistanceKm,
      targetPaceSecondsPerKm: targetPaceSecondsPerKm,
      paceNotificationsEnabled: _mode == _ActivityMode.run || _mode == _ActivityMode.interval
          ? _paceNotificationsEnabled
          : false,
      activityDetails: _mode == _ActivityMode.hiit ? _hiitDetails.text.trim() : null,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lokasi baru dimuat ketika pengguna membuka alur rekam, bukan saat aplikasi
    // pertama kali diluncurkan. RootShell memanggil loadLocation secara eksplisit.
  }
}
