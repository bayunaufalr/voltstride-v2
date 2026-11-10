// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'dart:math' as math;

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
import 'services/training_plan_service.dart';
import 'services/training_plan_repository.dart';
import '../reminders/reminder_service.dart';

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
  final String? trainingPlanId;
  final String? trainingPlanDayId;

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
    this.trainingPlanId,
    this.trainingPlanDayId,
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
  bool _showSavedPlan = false;
  bool _loadingPlanOptions = false;
  bool _savingPlan = false;
  bool _loadingSavedPlan = false;
  bool _planReviewDialogOpen = false;
  TrainingGoal _selectedTrainingGoal = TrainingGoal.endurance;
  final TextEditingController _planDistance = TextEditingController(text: '5');
  final TextEditingController _planPace = TextEditingController(text: '6:00');
  final TextEditingController _planFinishMinutes = TextEditingController();
  final TextEditingController _planVo2Max = TextEditingController(text: '40');
  final TextEditingController _planSessionMinutes = TextEditingController(text: '30');
  DateTime _planStartDate = DateTime.now().add(const Duration(days: 1));
  int _planDurationDays = 14;
  final Set<int> _planWeekdays = <int>{2, 4, 6};
  List<TrainingPlanOption> _planOptions = <TrainingPlanOption>[];
  TrainingPlanRequest? _planRequest;
  SavedTrainingPlan? _savedPlan;
  List<TrainingPlanDay> _savedPlanDays = <TrainingPlanDay>[];

  @override
  void initState() {
    super.initState();
    _heartRateDeviceName = HeartRateService.instance.connectedDeviceName.value;
    Future<void>.microtask(_loadSavedPlan);
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
    _planDistance.dispose();
    _planPace.dispose();
    _planFinishMinutes.dispose();
    _planVo2Max.dispose();
    _planSessionMinutes.dispose();
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
    if (!mounted) return;
    setState(() {
      _showTrainingPlanner = false;
      _showSavedPlan = false;
    });
  }

  Future<void> refreshTrainingPlan() async {
    await _loadSavedPlan();
    await _checkPlanReview();
  }

  Future<void> _loadSavedPlan() async {
    if (_loadingSavedPlan) return;
    _loadingSavedPlan = true;
    try {
      final SavedTrainingPlan? plan =
          await TrainingPlanRepository.instance.getCurrentPlan();
      final List<TrainingPlanDay> days = plan == null
          ? <TrainingPlanDay>[]
          : await TrainingPlanRepository.instance.getDays(plan.id);
      if (!mounted) return;
      setState(() {
        _savedPlan = plan;
        _savedPlanDays = days;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _savedPlan = null;
          _savedPlanDays = <TrainingPlanDay>[];
        });
      }
    } finally {
      _loadingSavedPlan = false;
    }
  }

  Future<void> _checkPlanReview() async {
    if (_planReviewDialogOpen || !mounted) return;
    SavedTrainingPlan? foundPlan;
    try {
      foundPlan = await TrainingPlanRepository.instance.getPlanNeedingReview();
    } catch (_) {
      return;
    }
    if (foundPlan == null || !mounted) return;
    final SavedTrainingPlan plan = foundPlan;
    _planReviewDialogOpen = true;
    final bool? createNext = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_text('Rencana latihan selesai', 'Training plan completed')),
        content: Text(_text(
          'Rencana ${plan.title} sudah mencapai hari terakhir. Apakah ingin menyusun rencana berikutnya?',
          'Your ${plan.title} plan has reached its final day. Would you like to create the next plan?',
        )),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(_text('Nanti', 'Later')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_text('Buat rencana', 'Create plan')),
          ),
        ],
      ),
    );
    _planReviewDialogOpen = false;
    try {
      await TrainingPlanRepository.instance.markReviewPrompted(plan.id);
    } catch (_) {}
    if (createNext == true && mounted) {
      setState(() {
        _selectedTrainingGoal = plan.goal;
        _planDurationDays = plan.durationDays;
        _planStartDate = DateTime.now().add(const Duration(days: 1));
        _planSessionMinutes.text = plan.sessionMinutes.toString();
        _planDistance.text = plan.targetDistanceKm?.toStringAsFixed(1) ?? '5';
        _planPace.text = plan.targetPaceSecondsPerKm == null
            ? '6:00'
            : _formatPace(plan.targetPaceSecondsPerKm!);
        _planFinishMinutes.text = plan.targetFinishMinutes?.toString() ?? '';
        _planVo2Max.text = plan.targetVo2Max?.toStringAsFixed(1) ?? '40';
        _planWeekdays
          ..clear()
          ..addAll(plan.trainingWeekdays);
        _showSavedPlan = false;
        _showTrainingPlanner = true;
        _planOptions = <TrainingPlanOption>[];
        _planRequest = null;
      });
    }
  }

  void _openTrainingPlanner() {
    setState(() {
      _showTrainingPlanner = true;
      _showSavedPlan = false;
      _planOptions = <TrainingPlanOption>[];
      _planRequest = null;
    });
  }

  Future<void> _pickPlanStartDate() async {
    final DateTime today = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _planStartDate.isBefore(today)
          ? DateTime(today.year, today.month, today.day)
          : _planStartDate,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year, today.month, today.day + 90),
    );
    if (picked != null && mounted) {
      setState(() {
        _planStartDate = picked;
        _planOptions = <TrainingPlanOption>[];
        _planRequest = null;
      });
    }
  }

  Future<void> _generatePlanOptions() async {
    final int? sessionMinutes = int.tryParse(_planSessionMinutes.text.trim());
    if (sessionMinutes == null || sessionMinutes < 15 || sessionMinutes > 90) {
      _showPlanMessage('Batas durasi sesi harus 15–90 menit.');
      return;
    }
    if (_planWeekdays.length < 2 || _planWeekdays.length > 5) {
      _showPlanMessage('Pilih 2–5 hari latihan dalam seminggu.');
      return;
    }

    double? distance;
    int? pace;
    int? finishMinutes;
    double? vo2;
    if (_selectedTrainingGoal != TrainingGoal.vo2max) {
      distance = double.tryParse(_planDistance.text.trim().replaceAll(',', '.'));
      if (distance == null || !distance.isFinite || distance < 1 ||
          distance > 42.2) {
        _showPlanMessage('Masukkan jarak target 1–42,2 km.');
        return;
      }
    }
    if (_selectedTrainingGoal == TrainingGoal.pace) {
      final double? parsedPace = _parsePace(_planPace.text);
      if (parsedPace == null) {
        _showPlanMessage('Gunakan format pace m:ss/km, misalnya 6:00.');
        return;
      }
      if (parsedPace < 180 || parsedPace > 1200) {
        _showPlanMessage('Target pace harus antara 3:00 dan 20:00 per km.');
        return;
      }
      pace = parsedPace.round();
      finishMinutes = _planFinishMinutes.text.trim().isEmpty
          ? (distance! * pace / 60).round()
          : int.tryParse(_planFinishMinutes.text.trim());
      if (finishMinutes == null || finishMinutes < 3 || finishMinutes > 600) {
        _showPlanMessage('Masukkan target waktu total 3–600 menit.');
        return;
      }
      final int estimatedFinishMinutes = (distance! * pace / 60).round();
      final int allowedDifference = math.max(1, (estimatedFinishMinutes * 0.15).round()).toInt();
      if ((finishMinutes - estimatedFinishMinutes).abs() > allowedDifference) {
        _showPlanMessage('Target waktu tidak selaras dengan pace dan jarak. Perkiraan waktunya $estimatedFinishMinutes menit.');
        return;
      }
    }
    if (_selectedTrainingGoal == TrainingGoal.vo2max) {
      vo2 = double.tryParse(_planVo2Max.text.trim().replaceAll(',', '.'));
      if (vo2 == null || !vo2.isFinite || vo2 < 20 || vo2 > 80) {
        _showPlanMessage('Target VO₂max harus 20–80 ml/kg/menit.');
        return;
      }
    }

    final TrainingPlanRequest request = TrainingPlanRequest(
      goal: _selectedTrainingGoal,
      durationDays: _planDurationDays,
      startDate: _planStartDate,
      trainingWeekdays: _planWeekdays.toList()..sort(),
      sessionMinutes: sessionMinutes,
      targetDistanceKm: distance,
      targetPaceSecondsPerKm: pace,
      targetFinishMinutes: finishMinutes,
      targetVo2Max: vo2,
    );

    setState(() {
      _loadingPlanOptions = true;
      _planOptions = <TrainingPlanOption>[];
      _planRequest = request;
    });
    try {
      final List<RunSession> history =
          await RunHistoryRepository.instance.getAll(limit: 100);
      final List<TrainingEffort> efforts =
          await TrainingPlanRepository.instance.getRecentEfforts();
      final List<TrainingPlanOption> options = TrainingPlanService.buildOptions(
        request: request,
        history: history,
        recentEfforts: efforts,
      );
      if (!mounted) return;
      setState(() => _planOptions = options);
    } catch (error) {
      _showPlanMessage('Rencana belum dapat dibuat: $error');
    } finally {
      if (mounted) setState(() => _loadingPlanOptions = false);
    }
  }

  Future<void> _savePlan(TrainingPlanOption option) async {
    final TrainingPlanRequest? request = _planRequest;
    if (request == null || _savingPlan) return;
    setState(() => _savingPlan = true);

    try {
      final SavedTrainingPlan? previousPlan =
          await TrainingPlanRepository.instance.getCurrentPlan();
      final SavedTrainingPlan? pendingReview =
          await TrainingPlanRepository.instance.getPlanNeedingReview();
      final String planId = await TrainingPlanRepository.instance.savePlan(
        request: request,
        option: option,
      );
      final Set<String> replacedPlanIds = <String>{
        if (previousPlan != null) previousPlan.id,
        if (pendingReview != null) pendingReview.id,
      };
      for (final String replacedId in replacedPlanIds) {
        try {
          await TrainingPlanRepository.instance.markReviewPrompted(replacedId);
          await ReminderService.cancelTrainingPlanReview(replacedId);
        } catch (_) {}
      }
      final DateTime endDate = DateTime(
        request.startDate.year,
        request.startDate.month,
        request.startDate.day + request.durationDays - 1,
      );
      bool reminderScheduled = false;
      try {
        final bool notificationsAllowed =
            await ReminderService.requestNotificationPermission();
        if (notificationsAllowed) {
          await ReminderService.scheduleTrainingPlanReview(
            planId: planId,
            endDate: endDate,
          );
          reminderScheduled = true;
        }
      } catch (_) {}
      await _loadSavedPlan();
      if (!mounted) return;
      setState(() {
        _showTrainingPlanner = false;
        _showSavedPlan = true;
        _planOptions = <TrainingPlanOption>[];
        _planRequest = null;
      });
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_text('Rencana ditambahkan', 'Plan added')),
          content: Text(_text(
            reminderScheduled
                ? 'Rencana ${option.title} tersimpan untuk ${request.durationDays} hari. Jadwal per tanggal sudah masuk ke database dan pengingat akhir rencana sudah dipasang.'
                : 'Rencana ${option.title} tersimpan untuk ${request.durationDays} hari. Jadwal per tanggal sudah masuk ke database, tetapi pengingat belum aktif karena izin notifikasi belum tersedia.',
            reminderScheduled
                ? '${option.title} has been saved for ${request.durationDays} days. Daily sessions are stored and the final-day reminder is scheduled.'
                : '${option.title} has been saved for ${request.durationDays} days. Daily sessions are stored, but notifications are not enabled for the final-day reminder.',
          )),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text('Lihat rencana', 'View plan')),
            ),
          ],
        ),
      );
    } catch (error) {
      _showPlanMessage('Rencana belum tersimpan: $error');
    } finally {
      if (mounted) setState(() => _savingPlan = false);
    }
  }

  void _showPlanMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _trainingGoalLabel(TrainingGoal goal) => switch (goal) {
        TrainingGoal.endurance => _text('Daya tahan', 'Endurance'),
        TrainingGoal.pace => _text('Pace', 'Pace'),
        TrainingGoal.vo2max => _text('VO₂max', 'VO₂max'),
      };

  String _formatPlanDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _formatPace(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _weekdayLabel(int weekday) => const <String>[
        'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min',
      ][weekday - 1];

  String _activityLabel(RunActivityType type) => switch (type) {
        RunActivityType.run => _text('Lari', 'Run'),
        RunActivityType.walk => _text('Berjalan', 'Walk'),
        RunActivityType.cycle => _text('Bersepeda', 'Cycling'),
        RunActivityType.hiit => 'HIIT',
      };

  Future<void> _startPlannedDay(TrainingPlanDay day) async {
    final SavedTrainingPlan? plan = _savedPlan;
    if (plan == null || day.isRestDay || day.completed) return;
    final DateTime today = DateTime.now();
    final bool isToday = day.date.year == today.year &&
        day.date.month == today.month && day.date.day == today.day;
    if (!isToday) {
      _showPlanMessage('Sesi ini dijadwalkan pada ${_formatPlanDate(day.date)}.');
      return;
    }
    if (widget.sessionAlreadyActive) {
      _showPlanMessage('Selesaikan sesi aktif sebelum memulai latihan baru.');
      return;
    }
    setState(() => _showSavedPlan = false);
    widget.onStart(ActivityStartConfig(
      activityType: day.activityType,
      environment: day.activityType == RunActivityType.hiit
          ? RunEnvironment.indoor
          : _environment,
      intervalPlan: day.intervalPlan,
      paceNotificationsEnabled: false,
      activityDetails: day.description,
      targetDurationMinutes: day.durationMinutes,
      plannedWorkoutTitle: day.title,
      plannedWorkoutDescription: day.description,
      trainingPlanId: plan.id,
      trainingPlanDayId: day.id,
    ));
  }

  Widget _planTargetFields() {
    if (_selectedTrainingGoal == TrainingGoal.endurance) {
      return _planTextField(
        _planDistance,
        'Jarak sasaran (km)',
        'Contoh: 10',
        decimal: true,
      );
    }
    if (_selectedTrainingGoal == TrainingGoal.pace) {
      return Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _planTextField(
                  _planPace,
                  'Target pace (m:ss/km)',
                  '6:00',
                  decimal: false,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _planTextField(
                  _planDistance,
                  'Jarak sasaran (km)',
                  '5',
                  decimal: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _planTextField(
            _planFinishMinutes,
            'Target waktu total (menit)',
            '30',
            decimal: false,
            requiredField: false,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Kosongkan waktu total untuk menghitungnya dari target pace dan jarak.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _planTextField(
          _planVo2Max,
          'Target VO₂max (ml/kg/menit)',
          '40',
          decimal: true,
        ),
        const SizedBox(height: 6),
        Text(
          'Pembanding dari aplikasi merupakan perkiraan berbasis pace dan durasi lari, bukan hasil tes laboratorium.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _planTextField(
    TextEditingController controller,
    String label,
    String hint, {
    required bool decimal,
    bool requiredField = true,
  }) =>
      TextField(
        controller: controller,
        keyboardType: identical(controller, _planPace)
            ? TextInputType.text
            : decimal
                ? const TextInputType.numberWithOptions(decimal: true)
                : TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          if (identical(controller, _planPace))
            FilteringTextInputFormatter.allow(RegExp(r'[0-9:]'))
          else if (decimal)
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
          else
            FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (_) {
          if (_planOptions.isNotEmpty || _planRequest != null) {
            setState(() {
              _planOptions = <TrainingPlanOption>[];
              _planRequest = null;
            });
          }
        },
        decoration: InputDecoration(
          labelText: requiredField ? label : '$label (opsional)',
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _buildTrainingPlanner() {
    final Color secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final DateTime endDate = DateTime(
      _planStartDate.year,
      _planStartDate.month,
      _planStartDate.day + _planDurationDays - 1,
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _text('Kembali', 'Back'),
          onPressed: closeTrainingPlanner,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_text('Susun rencana latihan', 'Build a training plan')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: <Widget>[
            Text(
              _text('Pilih tujuan utama', 'Choose your main goal'),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: TrainingGoal.values.map((TrainingGoal goal) {
                return ChoiceChip(
                  label: Text(_trainingGoalLabel(goal)),
                  selected: _selectedTrainingGoal == goal,
                  onSelected: (bool selected) {
                    if (!selected) return;
                    setState(() {
                      _selectedTrainingGoal = goal;
                      _planOptions = <TrainingPlanOption>[];
                      _planRequest = null;
                    });
                  },
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 18),
            Text(
              _text('Target yang ingin dicapai', 'Target to achieve'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _planTargetFields(),
            const SizedBox(height: 16),
            _planTextField(
              _planSessionMinutes,
              'Batas durasi sesi (15–90 menit)',
              '30',
              decimal: false,
            ),
            const SizedBox(height: 18),
            Text(
              _text('Lama rencana', 'Plan length'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 7, label: Text('7 hari')),
                ButtonSegment<int>(value: 14, label: Text('14 hari')),
                ButtonSegment<int>(value: 21, label: Text('21 hari')),
                ButtonSegment<int>(value: 28, label: Text('28 hari')),
              ],
              selected: <int>{_planDurationDays},
              onSelectionChanged: (Set<int> value) => setState(() {
                _planDurationDays = value.first;
                _planOptions = <TrainingPlanOption>[];
                _planRequest = null;
              }),
            ),
            const SizedBox(height: 18),
            Text(
              _text('Hari latihan setiap minggu (2–5 hari)', 'Training days each week (2–5 days)'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: List<Widget>.generate(7, (int index) {
                final int day = index + 1;
                return FilterChip(
                  label: Text(_weekdayLabel(day)),
                  selected: _planWeekdays.contains(day),
                  onSelected: (bool selected) {
                    if (selected && !_planWeekdays.contains(day) &&
                        _planWeekdays.length >= 5) {
                      _showPlanMessage('Pilih maksimal 5 hari latihan per minggu.');
                      return;
                    }
                    setState(() {
                      if (selected) {
                        _planWeekdays.add(day);
                      } else {
                        _planWeekdays.remove(day);
                      }
                      _planOptions = <TrainingPlanOption>[];
                      _planRequest = null;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _pickPlanStartDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                '${_text('Mulai', 'Starts')} ${_formatPlanDate(_planStartDate)} • ${_text('sampai', 'through')} ${_formatPlanDate(endDate)}',
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _loadingPlanOptions ? null : _generatePlanOptions,
              icon: _loadingPlanOptions
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.tune_rounded),
              label: Text(_text('Buat opsi rencana', 'Generate plan options')),
            ),
            if (_planOptions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 22),
              Text(
                _text('Pilih pendekatan latihan', 'Choose a training approach'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                _text(
                  'Opsi disusun dari riwayat latihan 30 hari, volume 7 hari terakhir, dan evaluasi sesi sebelumnya.',
                  'Options use your 30-day history, recent seven-day volume, and previous session feedback.',
                ),
                style: TextStyle(color: secondary, height: 1.4),
              ),
              const SizedBox(height: 12),
              ..._planOptions.map(_planOptionCard),
            ],
            const SizedBox(height: 10),
            Text(
              _text(
                'Target adalah arah latihan, bukan jaminan hasil. Tingkatkan beban secara bertahap dan beri waktu pemulihan.',
                'Targets guide the training plan; they do not guarantee a result. Increase workload gradually and allow recovery.',
              ),
              style: TextStyle(color: secondary, fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _planOptionCard(TrainingPlanOption option) {
    final Color secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final int workoutCount = option.days.where((TrainingPlanDay day) => !day.isRestDay).length;
    final int restCount = option.days.length - workoutCount;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(option.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(option.summary),
            const SizedBox(height: 8),
            Text('${option.days.length} hari • $workoutCount sesi • $restCount hari pemulihan', style: TextStyle(color: secondary, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(option.loadDescription, style: TextStyle(color: secondary, fontSize: 12)),
            const Divider(height: 20),
            Text(_text('Kelebihan', 'Advantages'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ...option.advantages.map((String item) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $item'),
                )),
            const SizedBox(height: 8),
            Text(_text('Kekurangan', 'Trade-offs'), style: const TextStyle(fontWeight: FontWeight.w800)),
            ...option.disadvantages.map((String item) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $item'),
                )),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(_text('Lihat rincian per tanggal', 'View daily schedule')),
              children: option.days.map((TrainingPlanDay day) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_formatPlanDate(day.date)} • ${day.title}'),
                    subtitle: Text(day.isRestDay
                        ? day.description
                        : '${day.durationMinutes} menit • ${day.intensity}\n${day.description}'),
                    isThreeLine: !day.isRestDay,
                  )).toList(growable: false),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _savingPlan ? null : () => _savePlan(option),
                child: _savingPlan
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_text('Gunakan rencana ini', 'Use this plan')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activePlanCard() {
    final SavedTrainingPlan? plan = _savedPlan;
    if (plan == null) return const SizedBox.shrink();
    final int remaining = _savedPlanDays.where((TrainingPlanDay day) =>
        !day.completed && !day.isRestDay).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.event_note_rounded),
                const SizedBox(width: 8),
                Expanded(child: Text(plan.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                Text('${plan.durationDays} hari', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(plan.targetDescription),
            const SizedBox(height: 4),
            Text('${_formatPlanDate(plan.startDate)} – ${_formatPlanDate(plan.endDate)} • $remaining sesi belum selesai', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => setState(() => _showSavedPlan = true),
              child: Text(_text('Lihat jadwal latihan', 'View training schedule')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSavedPlanPage() {
    final SavedTrainingPlan? plan = _savedPlan;
    if (plan == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(onPressed: closeTrainingPlanner, icon: const Icon(Icons.arrow_back_rounded)),
          title: Text(_text('Rencana latihan', 'Training plan')),
        ),
        body: Center(child: Text(_text('Belum ada rencana aktif.', 'There is no active plan.'))),
      );
    }
    final DateTime today = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => setState(() => _showSavedPlan = false),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(_text('Rencana latihan', 'Training plan')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(plan.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            Text(plan.summary),
            const SizedBox(height: 8),
            Text(plan.targetDescription, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${_formatPlanDate(plan.startDate)} – ${_formatPlanDate(plan.endDate)}'),
            if (plan.loadDescription.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(plan.loadDescription, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12, height: 1.4)),
            ],
            if (plan.advantages.isNotEmpty || plan.disadvantages.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              Text(_text('Kelebihan', 'Advantages'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ...plan.advantages.map((String item) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('• $item'),
                  )),
              const SizedBox(height: 8),
              Text(_text('Hal yang perlu diperhatikan', 'Trade-offs'), style: const TextStyle(fontWeight: FontWeight.w800)),
              ...plan.disadvantages.map((String item) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('• $item'),
                  )),
            ],
            const SizedBox(height: 16),
            ..._savedPlanDays.map((TrainingPlanDay day) {
              final bool isToday = day.date.year == today.year && day.date.month == today.month && day.date.day == today.day;
              final bool isFuture = day.date.isAfter(DateTime(today.year, today.month, today.day));
              final String status = day.isRestDay
                  ? _text('Pemulihan', 'Rest day')
                  : day.completed
                      ? _text('Selesai', 'Completed')
                      : isToday
                          ? _text('Jadwal hari ini', 'Today')
                          : isFuture
                              ? _text('Akan datang', 'Upcoming')
                              : _text('Belum diselesaikan', 'Not completed');
              return Card(
                margin: const EdgeInsets.only(bottom: 9),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: Text('${_formatPlanDate(day.date)} • ${day.title}', style: const TextStyle(fontWeight: FontWeight.w800))),
                          Text(status, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      if (!day.isRestDay) ...<Widget>[
                        const SizedBox(height: 5),
                        Text('${_activityLabel(day.activityType)} • ${day.durationMinutes} menit • ${day.intensity}'),
                      ],
                      const SizedBox(height: 5),
                      Text(day.description),
                      if (day.intervalPlan != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text('${day.intervalPlan!.workSeconds} detik kerja • ${day.intervalPlan!.recoverySeconds} detik pemulihan • ${day.intervalPlan!.repetitions} ulangan'),
                      ],
                      if (day.effort != null) ...<Widget>[
                        const SizedBox(height: 4),
                        Text('Evaluasi: ${switch (day.effort!) { TrainingEffort.tooEasy => 'Terlalu mudah', TrainingEffort.normal => 'Normal', TrainingEffort.tooHard => 'Terlalu berat' }}'),
                      ],
                      if (isToday && !day.isRestDay && !day.completed) ...<Widget>[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: widget.sessionAlreadyActive ? null : () => _startPlannedDay(day),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(_text('Mulai sesi hari ini', 'Start today’s session')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openTrainingPlanner,
              icon: const Icon(Icons.add_rounded),
              label: Text(_text('Susun rencana baru', 'Create a new plan')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showTrainingPlanner) return _buildTrainingPlanner();
    if (_showSavedPlan) return _buildSavedPlanPage();
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
            if (_savedPlan != null) ...<Widget>[
              const SizedBox(height: 12),
              _activePlanCard(),
            ],
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
    } catch (error) {
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
      trainingPlanId: _savedPlan?.id,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lokasi baru dimuat ketika pengguna membuka alur rekam, bukan saat aplikasi
    // pertama kali diluncurkan. RootShell memanggil loadLocation secara eksplisit.
  }
}
