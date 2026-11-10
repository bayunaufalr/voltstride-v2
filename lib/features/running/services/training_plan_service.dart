import 'dart:math' as math;

import '../models/run_session.dart';

enum TrainingGoal { endurance, pace, vo2max }
enum TrainingEffort { tooEasy, normal, tooHard }
enum TrainingStrategy { progressive, balanced, lowImpact }

class TrainingPlanRequest {
  const TrainingPlanRequest({
    required this.goal,
    required this.durationDays,
    required this.startDate,
    required this.trainingWeekdays,
    required this.sessionMinutes,
    this.targetDistanceKm,
    this.targetPaceSecondsPerKm,
    this.targetFinishMinutes,
    this.targetVo2Max,
  });

  final TrainingGoal goal;
  final int durationDays;
  final DateTime startDate;
  final List<int> trainingWeekdays;
  final int sessionMinutes;
  final double? targetDistanceKm;
  final int? targetPaceSecondsPerKm;
  final int? targetFinishMinutes;
  final double? targetVo2Max;
}

class TrainingPlanDay {
  const TrainingPlanDay({
    required this.id,
    required this.date,
    required this.title,
    required this.description,
    required this.activityType,
    required this.durationMinutes,
    required this.intensity,
    required this.isRestDay,
    this.intervalPlan,
    this.completed = false,
    this.effort,
  });

  final String id;
  final DateTime date;
  final String title;
  final String description;
  final RunActivityType activityType;
  final int durationMinutes;
  final String intensity;
  final bool isRestDay;
  final IntervalRunPlan? intervalPlan;
  final bool completed;
  final TrainingEffort? effort;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'date': _dateKey(date),
        'title': title,
        'description': description,
        'activityType': activityType.name,
        'durationMinutes': durationMinutes,
        'intensity': intensity,
        'isRestDay': isRestDay,
        'intervalPlan': intervalPlan?.toJson(),
        'completed': completed,
        'effort': effort?.name,
      };

  factory TrainingPlanDay.fromJson(Map<String, dynamic> json) {
    final Object? intervalValue = json['intervalPlan'];
    final String? effortName = json['effort'] as String?;
    TrainingEffort? effort;
    for (final TrainingEffort value in TrainingEffort.values) {
      if (value.name == effortName) {
        effort = value;
        break;
      }
    }
    return TrainingPlanDay(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      activityType: RunActivityType.values.firstWhere(
        (RunActivityType value) => value.name == json['activityType'],
        orElse: () => RunActivityType.run,
      ),
      durationMinutes: (json['durationMinutes'] as num? ?? 0).toInt(),
      intensity: json['intensity'] as String? ?? 'Ringan',
      isRestDay: json['isRestDay'] == true,
      intervalPlan: intervalValue is Map
          ? IntervalRunPlan.fromJson(Map<String, dynamic>.from(intervalValue))
          : null,
      completed: json['completed'] == true,
      effort: effort,
    );
  }

  TrainingPlanDay copyWith({
    String? title,
    String? description,
    RunActivityType? activityType,
    int? durationMinutes,
    String? intensity,
    bool? completed,
    TrainingEffort? effort,
    bool clearInterval = false,
    IntervalRunPlan? intervalPlan,
  }) =>
      TrainingPlanDay(
        id: id,
        date: date,
        title: title ?? this.title,
        description: description ?? this.description,
        activityType: activityType ?? this.activityType,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        intensity: intensity ?? this.intensity,
        isRestDay: isRestDay,
        intervalPlan: clearInterval ? null : intervalPlan ?? this.intervalPlan,
        completed: completed ?? this.completed,
        effort: effort ?? this.effort,
      );
}

class TrainingPlanOption {
  const TrainingPlanOption({
    required this.strategy,
    required this.title,
    required this.summary,
    required this.advantages,
    required this.disadvantages,
    required this.days,
    required this.loadDescription,
  });

  final TrainingStrategy strategy;
  final String title;
  final String summary;
  final List<String> advantages;
  final List<String> disadvantages;
  final List<TrainingPlanDay> days;
  final String loadDescription;
}

class TrainingPlanService {
  TrainingPlanService._();

  static List<TrainingPlanOption> buildOptions({
    required TrainingPlanRequest request,
    required List<RunSession> history,
    List<TrainingEffort> recentEfforts = const <TrainingEffort>[],
    DateTime? now,
  }) {
    if (![7, 14, 21, 28].contains(request.durationDays)) {
      throw ArgumentError.value(request.durationDays, 'durationDays');
    }
    if (request.trainingWeekdays.length < 2 ||
        request.trainingWeekdays.length > 5 ||
        request.trainingWeekdays.toSet().length != request.trainingWeekdays.length ||
        request.trainingWeekdays.any((int day) => day < 1 || day > 7)) {
      throw ArgumentError.value(request.trainingWeekdays, 'trainingWeekdays');
    }
    if (request.sessionMinutes < 15 || request.sessionMinutes > 90) {
      throw RangeError.range(request.sessionMinutes, 15, 90, 'sessionMinutes');
    }
    _validateTarget(request);

    final DateTime reference = now ?? DateTime.now();
    final DateTime startDay = DateTime(
      request.startDate.year,
      request.startDate.month,
      request.startDate.day,
    );
    final DateTime currentDay = DateTime(reference.year, reference.month, reference.day);
    if (startDay.isBefore(currentDay)) {
      throw ArgumentError.value(request.startDate, 'startDate');
    }
    final DateTime thirtyDaysAgo = reference.subtract(const Duration(days: 30));
    final DateTime sevenDaysAgo = reference.subtract(const Duration(days: 7));
    final List<RunSession> recent = history.where((RunSession session) {
      return session.finishedAt != null &&
          !session.startedAt.isBefore(thirtyDaysAgo) &&
          !session.startedAt.isAfter(reference);
    }).toList(growable: false);
    final List<RunSession> recentRuns = recent.where((RunSession session) {
      return session.activityType == RunActivityType.run &&
          session.distanceKm >= 0.5;
    }).toList(growable: false);

    final int minutesSevenDays = recent
        .where((RunSession session) => !session.startedAt.isBefore(sevenDaysAgo))
        .fold<int>(0, (int sum, RunSession item) => sum + _sessionMinutes(item));
    final int minutesThirtyDays = recent.fold<int>(
      0,
      (int sum, RunSession item) => sum + _sessionMinutes(item),
    );
    final double averageWeeklyMinutes = minutesThirtyDays * 7 / 30;
    final double baselineWeeklyMinutes = math
        .max(minutesSevenDays.toDouble(), averageWeeklyMinutes)
        .toDouble();
    final double dataBasedSessionLimit = recentRuns.length < 2
        ? math.min(request.sessionMinutes.toDouble(), 30.0).toDouble()
        : math.max(
            15.0,
            baselineWeeklyMinutes / request.trainingWeekdays.length * 1.15,
          ).toDouble();
    final int effectiveSessionMinutes = math.min(
      request.sessionMinutes.toDouble(),
      dataBasedSessionLimit,
    ).round().clamp(15, 90).toInt();
    final double distanceSevenDays = recent
        .where((RunSession session) => !session.startedAt.isBefore(sevenDaysAgo))
        .fold<double>(0, (double sum, RunSession item) => sum + item.distanceKm);
    final double totalRunKm = recentRuns.fold<double>(
      0,
      (double sum, RunSession item) => sum + item.distanceKm,
    );
    final double longestRunKm = recentRuns.isEmpty
        ? 0
        : recentRuns.map((RunSession item) => item.distanceKm).reduce(
            (double first, double second) => first > second ? first : second,
          );
    final double? averagePace = _averageRunPace(recentRuns);
    final double? estimatedVo2Max = _estimatedVo2Max(recentRuns);
    final int? averageHeartRate = _averageHeartRate(recentRuns);
    final RunSession? latest = recent.isEmpty
        ? null
        : (List<RunSession>.of(recent)
              ..sort((RunSession a, RunSession b) =>
                  b.startedAt.compareTo(a.startedAt)))
            .first;
    final int? hoursSince = latest?.finishedAt == null
        ? null
        : reference.difference(latest!.finishedAt!).inHours;
    final List<TrainingEffort> latestEfforts = recentEfforts.take(3).toList();
    final int hardFeedback = latestEfforts
        .where((TrainingEffort value) => value == TrainingEffort.tooHard)
        .length;
    final int easyFeedback = latestEfforts
        .where((TrainingEffort value) => value == TrainingEffort.tooEasy)
        .length;
    final bool recovery =
        (hoursSince != null && hoursSince < 14) || minutesSevenDays >= 240 || hardFeedback >= 2;
    final bool building = !recovery && recent.length >= 4 &&
        minutesSevenDays >= 75 && (easyFeedback >= 1 || latestEfforts.isEmpty);
    final bool hasTrainingBase = recentRuns.length >= 3 && minutesSevenDays >= 45;
    final bool targetMatchesCurrentBase = switch (request.goal) {
      TrainingGoal.endurance => longestRunKm <= 0 ||
          request.targetDistanceKm! <= longestRunKm * 3,
      TrainingGoal.pace => averagePace != null &&
          request.targetPaceSecondsPerKm! >= averagePace * 0.8,
      TrainingGoal.vo2max => estimatedVo2Max != null &&
          request.targetVo2Max! <= estimatedVo2Max + 10,
    };
    final bool allowQualitySessions = hasTrainingBase && targetMatchesCurrentBase;
    final String feedbackText = latestEfforts.isEmpty
        ? 'Belum ada evaluasi sesi.'
        : 'Evaluasi terbaru: ${_effortLabel(latestEfforts.first)}.';
    final String paceText = averagePace == null ? 'belum cukup data pace' : 'pace lari rata-rata ${_paceText(averagePace)} /km';
    final String vo2Text = estimatedVo2Max == null
        ? 'estimasi VO₂max belum tersedia'
        : 'perkiraan VO₂max berbasis performa ${estimatedVo2Max.toStringAsFixed(1)}, bukan hasil tes laboratorium';
    final String heartRateText = averageHeartRate == null
        ? 'detak jantung belum cukup tercatat'
        : 'detak jantung rata-rata ${averageHeartRate} bpm';
    final String targetFit = _targetFitDescription(
      request: request,
      longestRunKm: longestRunKm,
      averagePace: averagePace,
      estimatedVo2Max: estimatedVo2Max,
    );
    final String qualityNote = allowQualitySessions
        ? 'Riwayat mendukung satu sesi kualitas terkontrol dalam opsi seimbang.'
        : request.goal == TrainingGoal.endurance
            ? 'Rencana daya tahan memprioritaskan durasi ringan dan pemulihan.'
            : 'Sesi interval ditahan karena data atau target belum cukup mendukung.';
    final String loadDescription =
        'Data 30 hari: ${recent.length} sesi, ${totalRunKm.toStringAsFixed(1)} km lari, jarak terjauh ${longestRunKm.toStringAsFixed(1)} km. '
        '7 hari terakhir: $minutesSevenDays menit dan ${distanceSevenDays.toStringAsFixed(1)} km. '
        '$paceText; $vo2Text; $heartRateText. $feedbackText $targetFit $qualityNote '
        'Batas sesi dari permintaan ${request.sessionMinutes} menit, durasi awal yang disesuaikan maksimal $effectiveSessionMinutes menit. '
        '${recovery ? 'Beban awal dikurangi untuk memberi ruang pemulihan.' : building ? 'Volume dapat dinaikkan perlahan berdasarkan konsistensi terbaru.' : 'Program dimulai dari beban ringan sampai sedang karena data dasar masih terbatas.'}';

    return <TrainingPlanOption>[
      _buildOption(
        request: request,
        effectiveSessionMinutes: effectiveSessionMinutes,
        strategy: TrainingStrategy.progressive,
        recovery: recovery,
        building: building,
        hasTrainingBase: hasTrainingBase,
        allowQualitySessions: allowQualitySessions,
        loadDescription: loadDescription,
      ),
      _buildOption(
        request: request,
        effectiveSessionMinutes: effectiveSessionMinutes,
        strategy: TrainingStrategy.balanced,
        recovery: recovery,
        building: building,
        hasTrainingBase: hasTrainingBase,
        allowQualitySessions: allowQualitySessions,
        loadDescription: loadDescription,
      ),
      _buildOption(
        request: request,
        effectiveSessionMinutes: effectiveSessionMinutes,
        strategy: TrainingStrategy.lowImpact,
        recovery: recovery,
        building: building,
        hasTrainingBase: hasTrainingBase,
        allowQualitySessions: allowQualitySessions,
        loadDescription: loadDescription,
      ),
    ];
  }

  static void _validateTarget(TrainingPlanRequest request) {
    switch (request.goal) {
      case TrainingGoal.endurance:
        if (request.targetDistanceKm == null ||
            !request.targetDistanceKm!.isFinite ||
            request.targetDistanceKm! < 1 || request.targetDistanceKm! > 42.2) {
          throw ArgumentError('Target jarak harus 1–42,2 km.');
        }
        break;
      case TrainingGoal.pace:
        if (request.targetDistanceKm == null ||
            !request.targetDistanceKm!.isFinite ||
            request.targetDistanceKm! < 1 || request.targetDistanceKm! > 42.2 ||
            request.targetPaceSecondsPerKm == null ||
            request.targetPaceSecondsPerKm! < 180 ||
            request.targetPaceSecondsPerKm! > 1200 ||
            request.targetFinishMinutes == null ||
            request.targetFinishMinutes! < 3 ||
            request.targetFinishMinutes! > 600) {
          throw ArgumentError('Target pace, jarak, atau waktu tidak valid.');
        }
        final int expectedMinutes =
            (request.targetDistanceKm! * request.targetPaceSecondsPerKm! / 60).round();
        final int differenceLimit =
            math.max(1, (expectedMinutes * 0.15).round()).toInt();
        if ((request.targetFinishMinutes! - expectedMinutes).abs() >
            differenceLimit) {
          throw ArgumentError('Target waktu harus selaras dengan pace dan jarak.');
        }
        break;
      case TrainingGoal.vo2max:
        if (request.targetVo2Max == null ||
            !request.targetVo2Max!.isFinite ||
            request.targetVo2Max! < 20 || request.targetVo2Max! > 80) {
          throw ArgumentError('Target VO₂max harus 20–80 ml/kg/menit.');
        }
        break;
    }
  }

  static TrainingPlanOption _buildOption({
    required TrainingPlanRequest request,
    required int effectiveSessionMinutes,
    required TrainingStrategy strategy,
    required bool recovery,
    required bool building,
    required bool hasTrainingBase,
    required bool allowQualitySessions,
    required String loadDescription,
  }) {
    final List<String> advantages;
    final List<String> disadvantages;
    final String title;
    final String summary;
    switch (strategy) {
      case TrainingStrategy.progressive:
        title = 'Progresif';
        summary = 'Latihan mudah menjadi dasar, lalu durasi bertambah sedikit demi sedikit.';
        advantages = <String>[
          'Lebih mudah diikuti saat membangun kebiasaan.',
          'Peningkatan beban dilakukan bertahap.',
          'Sesi pemulihan tetap tersedia setiap minggu.',
        ];
        disadvantages = <String>[
          'Perubahan pace biasanya lebih lambat terlihat.',
          'Membutuhkan konsistensi pada sesi ringan.',
        ];
        break;
      case TrainingStrategy.balanced:
        title = 'Seimbang';
        summary = 'Menggabungkan sesi ringan, sesi terstruktur sesuai tujuan, dan pemulihan.';
        advantages = <String>[
          'Variasi latihan lebih beragam.',
          'Ada sesi khusus untuk pace atau VO₂max jika riwayat mendukung.',
          'Jadwal pemulihan tetap diperhitungkan.',
        ];
        disadvantages = <String>[
          'Sesi terstruktur membutuhkan pemanasan dan pendinginan.',
          'Latihan kualitas dapat diganti sesi ringan bila beban terbaru tinggi.',
        ];
        break;
      case TrainingStrategy.lowImpact:
        title = 'Dampak rendah';
        summary = 'Memadukan jalan dan bersepeda untuk membatasi beban benturan saat membangun kebugaran.';
        advantages = <String>[
          'Lebih banyak pilihan sesi tanpa lari.',
          'Beban benturan lebih rendah.',
          'Berguna ketika riwayat menunjukkan kebutuhan pemulihan.',
        ];
        disadvantages = <String>[
          'Adaptasi yang khusus untuk lari berkembang lebih lambat.',
          'Sesi bersepeda membutuhkan akses ke sepeda.',
        ];
        break;
    }

    final Set<int> weekdays = request.trainingWeekdays.toSet();
    final List<int> sortedWeekdays = weekdays.toList()..sort();
    final List<TrainingPlanDay> days = <TrainingPlanDay>[];
    int trainingIndex = 0;
    String? calendarWeekKey;
    for (int offset = 0; offset < request.durationDays; offset++) {
      final DateTime date = DateTime(
        request.startDate.year,
        request.startDate.month,
        request.startDate.day + offset,
      );
      final int elapsedWeeks = offset ~/ 7;
      final DateTime weekStart = date.subtract(Duration(days: date.weekday - 1));
      final String nextWeekKey = _dateKey(weekStart);
      if (nextWeekKey != calendarWeekKey) {
        trainingIndex = 0;
        calendarWeekKey = nextWeekKey;
      }
      final String id = '${_dateKey(date)}_${strategy.name}';
      if (!weekdays.contains(date.weekday)) {
        days.add(TrainingPlanDay(
          id: id,
          date: date,
          title: 'Istirahat',
          description: 'Tidak ada sesi terjadwal. Gunakan waktu ini untuk pemulihan.',
          activityType: RunActivityType.walk,
          durationMinutes: 0,
          intensity: 'Pemulihan',
          isRestDay: true,
        ));
        continue;
      }
      final double weekProgress = math.min(elapsedWeeks * 0.04, 0.12).toDouble();
      final double strategyFactor = switch (strategy) {
        TrainingStrategy.progressive => 0.82,
        TrainingStrategy.balanced => 0.86,
        TrainingStrategy.lowImpact => 0.80,
      };
      final double baseFactor = recovery ? 0.72 : building ? 0.94 : strategyFactor;
      final int duration =
          (effectiveSessionMinutes * baseFactor * (1 + weekProgress))
              .round()
              .clamp(15, 90)
              .toInt();
      days.add(_makeWorkout(
        request: request,
        strategy: strategy,
        indexInWeek: trainingIndex,
        sessionsThisWeek: sortedWeekdays.length,
        duration: duration,
        recovery: recovery,
        hasTrainingBase: hasTrainingBase,
        allowQualitySessions: allowQualitySessions,
        id: id,
        date: date,
      ));
      trainingIndex++;
    }
    return TrainingPlanOption(
      strategy: strategy,
      title: title,
      summary: summary,
      advantages: advantages,
      disadvantages: disadvantages,
      days: days,
      loadDescription: loadDescription,
    );
  }

  static TrainingPlanDay _makeWorkout({
    required TrainingPlanRequest request,
    required TrainingStrategy strategy,
    required int indexInWeek,
    required int sessionsThisWeek,
    required int duration,
    required bool recovery,
    required bool hasTrainingBase,
    required bool allowQualitySessions,
    required String id,
    required DateTime date,
  }) {
    final bool useCycle = strategy == TrainingStrategy.lowImpact && indexInWeek.isOdd;
    final bool useWalk = (recovery && indexInWeek == 0) ||
        (!hasTrainingBase && strategy != TrainingStrategy.lowImpact && indexInWeek.isOdd) ||
        (strategy == TrainingStrategy.lowImpact && indexInWeek % 3 == 2);
    final int workSeconds = request.goal == TrainingGoal.vo2max ? 60 : 120;
    const int recoverySeconds = 120;
    final int minimumIntervalDuration =
        request.goal == TrainingGoal.vo2max ? 22 : 25;
    final bool qualitySession = !recovery && hasTrainingBase &&
        allowQualitySessions && strategy == TrainingStrategy.balanced &&
        indexInWeek == 1 && duration >= minimumIntervalDuration;
    final int intervalBudgetSeconds = math.max(0, (duration - 13) * 60).toInt();
    final int repetitions = math.max(
      1,
      math.min(5, intervalBudgetSeconds ~/ (workSeconds + recoverySeconds)),
    ).toInt();
    final IntervalRunPlan? intervalPlan = qualitySession &&
            request.goal != TrainingGoal.endurance
        ? IntervalRunPlan(
            workSeconds: workSeconds,
            recoverySeconds: recoverySeconds,
            repetitions: repetitions,
          )
        : null;

    final String targetDescription = _workoutTargetDescription(request);
    if (useCycle) {
      return TrainingPlanDay(
        id: id,
        date: date,
        title: 'Bersepeda santai',
        description: 'Awali dengan kayuhan ringan 5 menit, lanjutkan kayuhan stabil selama ${math.max(5, duration - 10)} menit, lalu akhiri dengan 5 menit ringan. $targetDescription',
        activityType: RunActivityType.cycle,
        durationMinutes: duration,
        intensity: 'Ringan',
        isRestDay: false,
      );
    }
    if (useWalk) {
      return TrainingPlanDay(
        id: id,
        date: date,
        title: 'Jalan pemulihan',
        description: 'Berjalan dengan ritme nyaman. Mulai perlahan dan akhiri dengan jalan santai. $targetDescription',
        activityType: RunActivityType.walk,
        durationMinutes: duration,
        intensity: 'Ringan',
        isRestDay: false,
      );
    }
    if (qualitySession && request.goal == TrainingGoal.endurance) {
      final int steadyMinutes = math.max(5, duration - 15).toInt();
      return TrainingPlanDay(
        id: id,
        date: date,
        title: 'Lari stabil',
        description: 'Pemanasan berjalan 8 menit, lanjutkan lari stabil selama $steadyMinutes menit pada usaha sedang yang masih terkendali, lalu pendinginan 5 menit. $targetDescription',
        activityType: RunActivityType.run,
        durationMinutes: duration,
        intensity: 'Sedang dan stabil',
        isRestDay: false,
      );
    }
    if (intervalPlan != null) {
      final String focus = request.goal == TrainingGoal.vo2max
          ? 'Fase kerja dilakukan pada usaha kuat yang masih terkendali, bukan sprint maksimal.'
          : 'Fase kerja mendekati ritme sasaran hanya selama masih terasa terkendali, bukan sprint maksimal.';
      return TrainingPlanDay(
        id: id,
        date: date,
        title: request.goal == TrainingGoal.vo2max ? 'Interval aerobik' : 'Interval pace',
        description: 'Pemanasan 8 menit, ${intervalPlan.repetitions} ulangan kerja ${intervalPlan.workSeconds} detik dan pemulihan ${intervalPlan.recoverySeconds} detik dengan berjalan atau joging ringan, lalu pendinginan 5 menit. $focus $targetDescription',
        activityType: RunActivityType.run,
        durationMinutes: duration,
        intensity: 'Sedang dan terkendali',
        isRestDay: false,
        intervalPlan: intervalPlan,
      );
    }

    final bool longRun = request.goal == TrainingGoal.endurance &&
        sessionsThisWeek >= 3 && indexInWeek == sessionsThisWeek - 1;
    final String title = longRun ? 'Lari jarak bertahap' : 'Lari mudah';
    final String description = longRun
        ? 'Lari dengan usaha percakapan dan ritme stabil. Bila perlu, selingi jalan singkat. Jangan mengejar seluruh jarak target dalam satu sesi. $targetDescription'
        : 'Pemanasan berjalan 5 menit, lari ringan dengan usaha yang masih memungkinkan berbicara, lalu pendinginan 5 menit. $targetDescription';
    return TrainingPlanDay(
      id: id,
      date: date,
      title: title,
      description: description,
      activityType: RunActivityType.run,
      durationMinutes: duration,
      intensity: 'Ringan dan stabil',
      isRestDay: false,
    );
  }

  static String _workoutTargetDescription(TrainingPlanRequest request) {
    switch (request.goal) {
      case TrainingGoal.endurance:
        return 'Arah program: membangun daya tahan menuju jarak ${request.targetDistanceKm!.toStringAsFixed(1)} km.';
      case TrainingGoal.pace:
        return 'Arah program: pace ${_paceText(request.targetPaceSecondsPerKm!.toDouble())}/km untuk ${request.targetDistanceKm!.toStringAsFixed(1)} km dengan target waktu ${request.targetFinishMinutes} menit.';
      case TrainingGoal.vo2max:
        return 'Arah program: meningkatkan kapasitas aerobik menuju estimasi VO₂max ${request.targetVo2Max!.toStringAsFixed(1)} ml/kg/menit.';
    }
  }

  static String _targetFitDescription({
    required TrainingPlanRequest request,
    required double longestRunKm,
    required double? averagePace,
    required double? estimatedVo2Max,
  }) {
    switch (request.goal) {
      case TrainingGoal.endurance:
        if (longestRunKm <= 0) return 'Belum ada jarak lari pembanding; target dimulai dengan sesi ringan.';
        final double ratio = request.targetDistanceKm! / longestRunKm;
        if (ratio >= 2.5) return 'Jarak target jauh di atas lari terjauh terbaru; opsi diprioritaskan pada progres bertahap.';
        if (ratio >= 1.5) return 'Jarak target lebih panjang dari lari terjauh terbaru; volume dijaga bertahap.';
        return 'Jarak target masih dekat dengan lari terjauh terbaru.';
      case TrainingGoal.pace:
        if (averagePace == null) return 'Belum ada pace historis yang cukup untuk membandingkan sasaran.';
        final double difference = averagePace - request.targetPaceSecondsPerKm!;
        final double percent = difference / averagePace * 100;
        if (difference > 0) return 'Sasaran pace sekitar ${percent.toStringAsFixed(0)}% lebih cepat dari pace rata-rata terbaru.';
        return 'Pace sasaran berada pada atau di bawah kecepatan rata-rata terbaru.';
      case TrainingGoal.vo2max:
        if (estimatedVo2Max == null) return 'Belum ada sesi lari yang cukup untuk memperkirakan VO₂max saat ini.';
        final double difference = request.targetVo2Max! - estimatedVo2Max;
        return difference > 0
            ? 'Target berada ${difference.toStringAsFixed(1)} poin di atas estimasi terkini.'
            : 'Target berada pada atau di bawah estimasi terkini.';
    }
  }

  static int _sessionMinutes(RunSession session) {
    final Duration duration = session.movingTime > Duration.zero
        ? session.movingTime
        : session.elapsed;
    return duration.inMinutes;
  }

  static double? _averageRunPace(List<RunSession> sessions) {
    double totalSeconds = 0;
    double totalKm = 0;
    for (final RunSession session in sessions) {
      final Duration time = session.movingTime > Duration.zero
          ? session.movingTime
          : session.elapsed;
      if (session.distanceKm <= 0 || time.inSeconds <= 0) continue;
      final double pace = time.inSeconds / session.distanceKm;
      if (!pace.isFinite || pace < 120 || pace > 3600) continue;
      totalSeconds += time.inSeconds;
      totalKm += session.distanceKm;
    }
    if (totalKm <= 0) return null;
    return totalSeconds / totalKm;
  }

  static int? _averageHeartRate(List<RunSession> sessions) {
    final List<int> values = sessions
        .map((RunSession session) => session.averageHeartRateBpm)
        .whereType<int>()
        .where((int value) => value >= 40 && value <= 220)
        .toList(growable: false);
    if (values.isEmpty) return null;
    return (values.reduce((int a, int b) => a + b) / values.length).round();
  }

  static double? _estimatedVo2Max(List<RunSession> sessions) {
    final List<double> values = sessions
        .map(_estimateVo2FromSession)
        .whereType<double>()
        .toList(growable: false)
      ..sort();
    if (values.isEmpty) return null;
    return values[values.length ~/ 2];
  }

  static double? _estimateVo2FromSession(RunSession session) {
    final double distanceMeters = session.distanceKm * 1000;
    final Duration duration = session.movingTime > Duration.zero
        ? session.movingTime
        : session.elapsed;
    final double minutes = duration.inSeconds / 60;
    if (!distanceMeters.isFinite || distanceMeters < 1500 ||
        !minutes.isFinite || minutes < 8 || minutes > 120) {
      return null;
    }
    final double velocity = distanceMeters / minutes;
    if (velocity < 50 || velocity > 450) return null;
    final double oxygenDemand = -4.60 +
        0.182258 * velocity +
        0.000104 * velocity * velocity;
    final double sustainableFraction = 0.8 +
        0.1894393 * math.exp(-0.012778 * minutes) +
        0.2989558 * math.exp(-0.1932605 * minutes);
    if (sustainableFraction <= 0) return null;
    final double estimate = oxygenDemand / sustainableFraction;
    if (!estimate.isFinite || estimate < 15 || estimate > 90) return null;
    return estimate;
  }

  static String _effortLabel(TrainingEffort effort) => switch (effort) {
        TrainingEffort.tooEasy => 'terlalu mudah',
        TrainingEffort.normal => 'normal',
        TrainingEffort.tooHard => 'terlalu berat',
      };

  static String _paceText(double pace) {
    final int seconds = pace.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
