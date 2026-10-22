// ignore_for_file: lines_longer_than_80_chars

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_language_service.dart';

class MusclePage extends StatefulWidget {
  const MusclePage({super.key});

  @override
  State<MusclePage> createState() => _MusclePageState();
}

class _MusclePageState extends State<MusclePage> {
  String _selectedGroup = 'all';
  String? _expandedExercise;

  String _text(String id, String en) =>
      AppLanguageService.text(context, id, en);

  List<_StrengthExercise> get _visibleExercises =>
      _selectedGroup == 'all'
          ? _strengthExercises
          : _strengthExercises
              .where((_StrengthExercise item) => item.groupId == _selectedGroup)
              .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final Set<String> groupIds = <String>{
      for (final _StrengthExercise item in _strengthExercises) item.groupId,
    };
    final List<_StrengthGroup> groups = groupIds.map((String id) {
      final _StrengthExercise first = _strengthExercises.firstWhere(
        (_StrengthExercise item) => item.groupId == id,
      );
      return _StrengthGroup(
        id: id,
        nameId: first.groupIdNameId,
        nameEn: first.groupIdNameEn,
      );
    }).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_text('Latihan kekuatan', 'Strength training')),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _text('PUSTAKA GERAKAN', 'EXERCISE LIBRARY'),
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _text(
                      'Pilih gerakan untuk melihat petunjuk, timer, dan tautan referensi. Tidak ada video yang diputar di aplikasi.',
                      'Choose an exercise to view cues, a timer, and reference links. No videos are embedded in the app.',
                    ),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 48,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(_text('Semua', 'All')),
                      selected: _selectedGroup == 'all',
                      onSelected: (_) => setState(() {
                        _selectedGroup = 'all';
                        _expandedExercise = null;
                      }),
                    ),
                  ),
                  ...groups.map((_StrengthGroup group) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(english ? group.nameEn : group.nameId),
                        selected: _selectedGroup == group.id,
                        onSelected: (_) => setState(() {
                          _selectedGroup = group.id;
                          _expandedExercise = null;
                        }),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                '${_visibleExercises.length} ${_text('gerakan', 'exercises')}',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: _visibleExercises.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (BuildContext context, int index) {
                  final _StrengthExercise exercise = _visibleExercises[index];
                  final bool expanded = _expandedExercise == exercise.id;
                  return _ExerciseCard(
                    key: ValueKey<String>(exercise.id),
                    exercise: exercise,
                    expanded: expanded,
                    onToggle: () => setState(() {
                      _expandedExercise = expanded ? null : exercise.id;
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    super.key,
    required this.exercise,
    required this.expanded,
    required this.onToggle,
  });

  final _StrengthExercise exercise;
  final bool expanded;
  final VoidCallback onToggle;

  String _text(BuildContext context, String id, String en) =>
      AppLanguageService.text(context, id, en);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final String name = english ? exercise.nameEn : exercise.nameId;
    final String target = english ? exercise.targetEn : exercise.targetId;
    final String equipment =
        english ? exercise.equipmentEn : exercise.equipmentId;
    final String instructions =
        english ? exercise.instructionsEn : exercise.instructionsId;
    final Uri reference = Uri.https(
      'www.google.com',
      '/search',
      <String, String>{
        'q': 'site:acefitness.org/resources/everyone/exercise-library ${exercise.nameEn} proper form',
      },
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHighest,
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Icon(Icons.fitness_center, color: colors.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          name,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$target · ${english ? exercise.setsEn : exercise.setsId} · ${english ? exercise.repsEn : exercise.repsId}',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Divider(color: colors.outlineVariant),
                        _DetailRow(
                          label: _text(context, 'Peralatan', 'Equipment'),
                          value: equipment,
                        ),
                        const SizedBox(height: 8),
                        _DetailRow(
                          label: _text(context, 'Tingkat', 'Level'),
                          value: english ? exercise.levelEn : exercise.levelId,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _text(context, 'Petunjuk gerakan', 'Movement cues'),
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          instructions,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final bool opened = await launchUrl(
                              reference,
                              mode: LaunchMode.externalApplication,
                            );
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_text(
                                    context,
                                    'Tautan referensi tidak dapat dibuka.',
                                    'Could not open the reference link.',
                                  )),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: Text(_text(
                            context,
                            'Buka referensi teknik',
                            'Open technique reference',
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ExerciseTimer(initialSeconds: exercise.timerSeconds),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExerciseTimer extends StatefulWidget {
  const _ExerciseTimer({required this.initialSeconds});

  final int initialSeconds;

  @override
  State<_ExerciseTimer> createState() => _ExerciseTimerState();
}

class _ExerciseTimerState extends State<_ExerciseTimer> {
  Timer? _ticker;
  late int _remaining;
  late int _duration;

  @override
  void initState() {
    super.initState();
    _duration = widget.initialSeconds;
    _remaining = widget.initialSeconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _format(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _start() {
    if (_ticker != null) return;
    if (_remaining == 0) setState(() => _remaining = _duration);
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remaining <= 1) {
        timer.cancel();
        setState(() {
          _remaining = 0;
          _ticker = null;
        });
        unawaited(HapticFeedback.mediumImpact());
      } else {
        setState(() => _remaining--);
      }
    });
    setState(() {});
  }

  void _pause() {
    _ticker?.cancel();
    setState(() => _ticker = null);
  }

  void _reset() {
    _ticker?.cancel();
    setState(() {
      _ticker = null;
      _remaining = _duration;
    });
  }

  void _adjust(int delta) {
    if (_ticker != null) return;
    setState(() {
      _duration = (_duration + delta).clamp(15, 600).toInt();
      _remaining = _duration;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final bool running = _ticker != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.timer_outlined, color: colors.onSurface),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  english ? 'Exercise timer' : 'Timer latihan',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _format(_remaining),
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              IconButton.outlined(
                tooltip: english ? 'Subtract 15 seconds' : 'Kurangi 15 detik',
                onPressed: running ? null : () => _adjust(-15),
                icon: const Icon(Icons.remove),
              ),
              Text(
                english ? '15-second steps' : 'Kelipatan 15 detik',
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
              ),
              IconButton.outlined(
                tooltip: english ? 'Add 15 seconds' : 'Tambah 15 detik',
                onPressed: running ? null : () => _adjust(15),
                icon: const Icon(Icons.add),
              ),
              FilledButton.icon(
                onPressed: running ? _pause : _start,
                icon: Icon(running ? Icons.pause : Icons.play_arrow),
                label: Text(running
                    ? (english ? 'Pause' : 'Jeda')
                    : (english ? 'Start' : 'Mulai')),
              ),
              IconButton(
                tooltip: english ? 'Reset timer' : 'Atur ulang timer',
                onPressed: _reset,
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          if (_remaining == 0)
            Text(
              english ? 'Time is up.' : 'Waktu selesai.',
              style: TextStyle(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _StrengthGroup {
  const _StrengthGroup({
    required this.id,
    required this.nameId,
    required this.nameEn,
  });

  final String id;
  final String nameId;
  final String nameEn;
}

class _StrengthExercise {
  const _StrengthExercise({
    required this.id,
    required this.groupId,
    required this.groupIdNameId,
    required this.groupIdNameEn,
    required this.nameId,
    required this.nameEn,
    required this.targetId,
    required this.targetEn,
    required this.repsId,
    required this.repsEn,
    required this.setsId,
    required this.setsEn,
    required this.equipmentId,
    required this.equipmentEn,
    required this.levelId,
    required this.levelEn,
    required this.instructionsId,
    required this.instructionsEn,
    required this.timerSeconds,
  });

  final String id;
  final String groupId;
  final String groupIdNameId;
  final String groupIdNameEn;
  final String nameId;
  final String nameEn;
  final String targetId;
  final String targetEn;
  final String repsId;
  final String repsEn;
  final String setsId;
  final String setsEn;
  final String equipmentId;
  final String equipmentEn;
  final String levelId;
  final String levelEn;
  final String instructionsId;
  final String instructionsEn;
  final int timerSeconds;
}

const List<_StrengthExercise> _strengthExercises = <_StrengthExercise>[
  // Legs and glutes
  _StrengthExercise(id: 'squat', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Bodyweight squat', nameEn: 'Bodyweight squat', targetId: 'Paha depan, glutes', targetEn: 'Quadriceps, glutes', repsId: '10–15 repetisi', repsEn: '10–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berdiri selebar bahu. Dorong pinggul ke belakang dan tekuk lutut dengan dada tetap terbuka. Dorong lantai untuk berdiri kembali.', instructionsEn: 'Stand with feet shoulder-width apart. Send hips back and bend the knees while keeping the chest open. Push through the floor to stand.', timerSeconds: 45),
  _StrengthExercise(id: 'reverse-lunge', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Reverse lunge', nameEn: 'Reverse lunge', targetId: 'Paha, glutes', targetEn: 'Thighs, glutes', repsId: '8–10 per kaki', repsEn: '8–10 per leg', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Langkahkan satu kaki ke belakang. Turunkan badan secara terkendali, jaga lutut depan searah jari kaki, lalu kembali berdiri.', instructionsEn: 'Step one foot backward. Lower with control, keep the front knee tracking over the toes, then return to standing.', timerSeconds: 45),
  _StrengthExercise(id: 'glute-bridge', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Glute bridge', nameEn: 'Glute bridge', targetId: 'Glutes, pinggul', targetEn: 'Glutes, hips', repsId: '12–15 repetisi', repsEn: '12–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras opsional', equipmentEn: 'Mat optional', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaring dengan lutut ditekuk dan telapak kaki rata. Angkat pinggul tanpa melengkungkan pinggang berlebihan, tahan sebentar, lalu turunkan.', instructionsEn: 'Lie on your back with knees bent and feet flat. Lift hips without over-arching the lower back, pause briefly, then lower.', timerSeconds: 45),
  _StrengthExercise(id: 'step-up', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Step-up', nameEn: 'Step-up', targetId: 'Paha, glutes', targetEn: 'Thighs, glutes', repsId: '8–10 per kaki', repsEn: '8–10 per leg', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Bangku kokoh rendah', equipmentEn: 'Stable low step', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Naik ke pijakan rendah dengan seluruh telapak kaki. Berdiri tegak, lalu turun perlahan. Gunakan pijakan yang tidak bergerak.', instructionsEn: 'Step onto a low, stable platform with the whole foot. Stand tall, then lower slowly. Use a platform that will not move.', timerSeconds: 45),
  _StrengthExercise(id: 'wall-sit', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Wall sit', nameEn: 'Wall sit', targetId: 'Paha depan', targetEn: 'Quadriceps', repsId: 'Tahan 20–45 detik', repsEn: 'Hold 20–45 seconds', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dinding', equipmentEn: 'Wall', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Sandarkan punggung ke dinding lalu geser turun hanya sejauh nyaman. Jaga lutut searah jari kaki dan bernapas normal.', instructionsEn: 'Keep your back against a wall and slide down only as far as comfortable. Keep knees aligned with toes and breathe normally.', timerSeconds: 30),
  _StrengthExercise(id: 'split-squat', groupId: 'legs', groupIdNameId: 'Kaki & glutes', groupIdNameEn: 'Legs & glutes', nameId: 'Split squat', nameEn: 'Split squat', targetId: 'Paha, glutes', targetEn: 'Thighs, glutes', repsId: '8–12 per kaki', repsEn: '8–12 per leg', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Ambil posisi langkah lebar dengan kedua kaki tetap di tempat. Turunkan pinggul lurus ke bawah dan dorong kembali tanpa terburu-buru.', instructionsEn: 'Use a long staggered stance with both feet planted. Lower hips vertically and push back up under control.', timerSeconds: 45),

  // Calves and ankles
  _StrengthExercise(id: 'calf-raise', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Standing calf raise', nameEn: 'Standing calf raise', targetId: 'Betis', targetEn: 'Calves', repsId: '15–20 repetisi', repsEn: '15–20 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dinding untuk keseimbangan', equipmentEn: 'Wall for balance', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Naikkan tumit perlahan, tahan satu detik, lalu turunkan sampai nyaman. Hindari memantul.', instructionsEn: 'Raise heels slowly, hold for a second, then lower comfortably. Avoid bouncing.', timerSeconds: 45),
  _StrengthExercise(id: 'single-calf-raise', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Single-leg calf raise', nameEn: 'Single-leg calf raise', targetId: 'Betis, keseimbangan', targetEn: 'Calves, balance', repsId: '8–12 per kaki', repsEn: '8–12 per leg', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Pegangan untuk keseimbangan', equipmentEn: 'Support for balance', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Berdiri pada satu kaki dekat pegangan. Angkat dan turunkan tumit secara perlahan dengan rentang gerak yang nyaman.', instructionsEn: 'Stand on one leg near a support. Raise and lower the heel slowly through a comfortable range.', timerSeconds: 40),
  _StrengthExercise(id: 'seated-calf', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Seated calf raise', nameEn: 'Seated calf raise', targetId: 'Betis bagian bawah', targetEn: 'Lower calf', repsId: '15–20 repetisi', repsEn: '15–20 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Kursi kokoh', equipmentEn: 'Stable chair', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Duduk dengan kaki rata, lalu angkat tumit sambil menjaga ujung kaki tetap menempel lantai.', instructionsEn: 'Sit with feet flat, then raise heels while keeping the balls of the feet on the floor.', timerSeconds: 45),
  _StrengthExercise(id: 'tibialis-raise', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Tibialis raise', nameEn: 'Tibialis raise', targetId: 'Otot depan tulang kering', targetEn: 'Front of shins', repsId: '12–20 repetisi', repsEn: '12–20 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Dinding', equipmentEn: 'Wall', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Sandarkan punggung ke dinding, tumit tetap di lantai, kemudian angkat ujung kaki ke arah tulang kering.', instructionsEn: 'Lean against a wall with heels on the floor, then lift toes toward the shins.', timerSeconds: 40),
  _StrengthExercise(id: 'toe-walk', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Toe walk', nameEn: 'Toe walk', targetId: 'Betis, pergelangan kaki', targetEn: 'Calves, ankles', repsId: '20–30 detik', repsEn: '20–30 seconds', setsId: '2 set', setsEn: '2 sets', equipmentId: 'Ruang berjalan datar', equipmentEn: 'Flat walking space', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berjalan perlahan dengan tumit terangkat. Jaga badan tegak dan gunakan jarak pendek di permukaan datar.', instructionsEn: 'Walk slowly with heels raised. Keep the torso upright and use a short distance on flat ground.', timerSeconds: 30),
  _StrengthExercise(id: 'ankle-rock', groupId: 'calves', groupIdNameId: 'Betis & pergelangan', groupIdNameEn: 'Calves & ankles', nameId: 'Knee-to-wall ankle rocks', nameEn: 'Knee-to-wall ankle rocks', targetId: 'Mobilitas pergelangan', targetEn: 'Ankle mobility', repsId: '8–12 per sisi', repsEn: '8–12 per side', setsId: '2 set', setsEn: '2 sets', equipmentId: 'Dinding', equipmentEn: 'Wall', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Hadap dinding dengan satu kaki di depan. Arahkan lutut ke dinding tanpa mengangkat tumit, lalu kembali.', instructionsEn: 'Face a wall with one foot forward. Move the knee toward the wall without lifting the heel, then return.', timerSeconds: 30),

  // Core
  _StrengthExercise(id: 'plank', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Forearm plank', nameEn: 'Forearm plank', targetId: 'Otot inti', targetEn: 'Core', repsId: 'Tahan 20–45 detik', repsEn: 'Hold 20–45 seconds', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras opsional', equipmentEn: 'Mat optional', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Siku di bawah bahu. Bentuk garis lurus dari kepala hingga tumit dan jangan biarkan pinggang turun.', instructionsEn: 'Place elbows below shoulders. Keep a straight line from head to heels and avoid letting hips sag.', timerSeconds: 30),
  _StrengthExercise(id: 'side-plank', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Side plank', nameEn: 'Side plank', targetId: 'Oblique, pinggul', targetEn: 'Obliques, hips', repsId: 'Tahan 15–30 detik per sisi', repsEn: 'Hold 15–30 seconds per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras opsional', equipmentEn: 'Mat optional', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Tumpu pada siku dan sisi kaki. Angkat pinggul agar badan lurus. Pilih versi lutut menekuk jika perlu.', instructionsEn: 'Support yourself on an elbow and the side of the foot. Lift hips to keep the body aligned. Bend the knees for an easier option.', timerSeconds: 25),
  _StrengthExercise(id: 'dead-bug', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Dead bug', nameEn: 'Dead bug', targetId: 'Stabilitas perut', targetEn: 'Abdominal stability', repsId: '8–10 per sisi', repsEn: '8–10 per side', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaring dengan tangan ke atas dan lutut terangkat. Turunkan lengan dan kaki berlawanan tanpa mengangkat punggung bawah dari matras.', instructionsEn: 'Lie with arms up and knees raised. Lower the opposite arm and leg without arching the lower back off the mat.', timerSeconds: 40),
  _StrengthExercise(id: 'bird-dog', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Bird dog', nameEn: 'Bird dog', targetId: 'Punggung bawah, core', targetEn: 'Lower back, core', repsId: '8–10 per sisi', repsEn: '8–10 per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Posisi merangkak. Luruskan lengan dan kaki berlawanan sambil menjaga panggul tetap rata; jangan memutar badan.', instructionsEn: 'Start on hands and knees. Extend opposite arm and leg while keeping hips level and avoiding trunk rotation.', timerSeconds: 40),
  _StrengthExercise(id: 'reverse-crunch', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Reverse crunch', nameEn: 'Reverse crunch', targetId: 'Perut', targetEn: 'Abdominals', repsId: '10–15 repetisi', repsEn: '10–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Berbaring telentang dengan lutut ditekuk. Gulung panggul sedikit ke arah dada tanpa mengayun kaki.', instructionsEn: 'Lie on your back with knees bent. Gently curl the pelvis toward the chest without swinging the legs.', timerSeconds: 40),
  _StrengthExercise(id: 'mountain-climber', groupId: 'core', groupIdNameId: 'Core', groupIdNameEn: 'Core', nameId: 'Mountain climber', nameEn: 'Mountain climber', targetId: 'Core, bahu', targetEn: 'Core, shoulders', repsId: '20–30 langkah total', repsEn: '20–30 total steps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Mulai dari posisi high plank. Bawa lutut bergantian ke depan dengan pinggul tetap stabil. Perlambat jika bentuk badan berubah.', instructionsEn: 'Start in a high plank. Drive knees forward in turns while keeping hips steady. Slow down if your form changes.', timerSeconds: 30),

  // Chest and triceps
  _StrengthExercise(id: 'push-up', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Push-up', nameEn: 'Push-up', targetId: 'Dada, bahu, trisep', targetEn: 'Chest, shoulders, triceps', repsId: '6–15 repetisi', repsEn: '6–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Tangan sedikit lebih lebar dari bahu. Jaga badan lurus, turunkan dada dengan kontrol, lalu dorong kembali.', instructionsEn: 'Place hands slightly wider than shoulders. Keep the body aligned, lower the chest with control, then push back up.', timerSeconds: 40),
  _StrengthExercise(id: 'incline-push-up', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Incline push-up', nameEn: 'Incline push-up', targetId: 'Dada, trisep', targetEn: 'Chest, triceps', repsId: '8–15 repetisi', repsEn: '8–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Meja atau bangku kokoh', equipmentEn: 'Stable bench or counter', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Letakkan tangan pada permukaan yang stabil. Turunkan dada menuju permukaan dan pertahankan garis lurus tubuh.', instructionsEn: 'Place hands on a stable raised surface. Lower chest toward it while maintaining a straight body line.', timerSeconds: 40),
  _StrengthExercise(id: 'knee-push-up', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Knee push-up', nameEn: 'Knee push-up', targetId: 'Dada, trisep', targetEn: 'Chest, triceps', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras opsional', equipmentEn: 'Mat optional', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Tumpu pada lutut dan tangan. Jaga garis dari kepala ke lutut, lalu turunkan dada tanpa membiarkan siku melebar berlebihan.', instructionsEn: 'Support yourself on knees and hands. Keep a line from head to knees and lower the chest without flaring elbows excessively.', timerSeconds: 40),
  _StrengthExercise(id: 'close-grip-push-up', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Close-grip push-up', nameEn: 'Close-grip push-up', targetId: 'Trisep, dada', targetEn: 'Triceps, chest', repsId: '6–10 repetisi', repsEn: '6–10 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Letakkan tangan sedikit lebih sempit dari bahu. Siku bergerak dekat sisi tubuh, tanpa memaksakan rentang gerak.', instructionsEn: 'Place hands slightly narrower than shoulders. Keep elbows close to the body and use a comfortable range of motion.', timerSeconds: 35),
  _StrengthExercise(id: 'floor-press', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Dumbbell floor press', nameEn: 'Dumbbell floor press', targetId: 'Dada, trisep', targetEn: 'Chest, triceps', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell', equipmentEn: 'Dumbbells', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Berbaring dengan lutut ditekuk. Mulai dengan siku di lantai, dorong beban ke atas, lalu turunkan perlahan.', instructionsEn: 'Lie with knees bent. Start with elbows on the floor, press weights upward, then lower slowly.', timerSeconds: 45),
  _StrengthExercise(id: 'triceps-extension', groupId: 'chest', groupIdNameId: 'Dada & trisep', groupIdNameEn: 'Chest & triceps', nameId: 'Overhead triceps extension', nameEn: 'Overhead triceps extension', targetId: 'Trisep', targetEn: 'Triceps', repsId: '10–12 repetisi', repsEn: '10–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Satu dumbbell ringan atau botol air', equipmentEn: 'Light dumbbell or water bottle', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Pegang beban di atas kepala. Tekuk siku untuk menurunkan beban di belakang kepala, lalu luruskan tanpa mengunci siku keras.', instructionsEn: 'Hold a weight overhead. Bend elbows to lower it behind the head, then straighten without snapping the elbows.', timerSeconds: 40),

  // Back
  _StrengthExercise(id: 'one-arm-row', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'One-arm dumbbell row', nameEn: 'One-arm dumbbell row', targetId: 'Punggung atas, lat', targetEn: 'Upper back, lats', repsId: '10–12 per sisi', repsEn: '10–12 per side', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell dan tumpuan stabil', equipmentEn: 'Dumbbell and stable support', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Sangga satu tangan, punggung netral. Tarik siku menuju pinggul tanpa memutar badan lalu turunkan secara terkendali.', instructionsEn: 'Support one hand with a neutral back. Pull elbow toward the hip without twisting, then lower with control.', timerSeconds: 45),
  _StrengthExercise(id: 'band-row', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'Resistance-band row', nameEn: 'Resistance-band row', targetId: 'Punggung tengah', targetEn: 'Mid-back', repsId: '12–15 repetisi', repsEn: '12–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Resistance band yang aman', equipmentEn: 'Secure resistance band', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Pasang band dengan aman di titik yang kokoh. Tarik siku ke belakang sambil merapatkan tulang belikat, lalu kembali perlahan.', instructionsEn: 'Secure the band to a sturdy anchor. Pull elbows back while bringing shoulder blades together, then return slowly.', timerSeconds: 45),
  _StrengthExercise(id: 'superman', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'Superman hold', nameEn: 'Superman hold', targetId: 'Punggung bawah', targetEn: 'Lower back', repsId: 'Tahan 10–20 detik', repsEn: 'Hold 10–20 seconds', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaring tengkurap. Angkat lengan dan kaki sedikit saja tanpa menengadah atau memaksa pinggang.', instructionsEn: 'Lie face down. Lift arms and legs slightly without looking upward or forcing the lower back.', timerSeconds: 20),
  _StrengthExercise(id: 'reverse-snow-angel', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'Prone reverse snow angel', nameEn: 'Prone reverse snow angel', targetId: 'Punggung atas, bahu', targetEn: 'Upper back, shoulders', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Tengkurap dengan dahi dekat matras. Gerakkan lengan dari sisi pinggul ke atas dalam bentuk lengkung, tanpa mengangkat bahu ke telinga.', instructionsEn: 'Lie face down with forehead near the mat. Sweep arms from hips overhead in an arc without shrugging shoulders.', timerSeconds: 40),
  _StrengthExercise(id: 'prone-y-raise', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'Prone Y raise', nameEn: 'Prone Y raise', targetId: 'Punggung atas, stabilisator bahu', targetEn: 'Upper back, shoulder stabilizers', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras, beban ringan opsional', equipmentEn: 'Mat, optional light weights', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Tengkurap dan posisikan lengan membentuk huruf Y. Angkat tangan sedikit sambil menjaga leher netral, lalu turunkan.', instructionsEn: 'Lie face down with arms forming a Y. Raise hands slightly while keeping the neck neutral, then lower.', timerSeconds: 35),
  _StrengthExercise(id: 'hip-hinge', groupId: 'back', groupIdNameId: 'Punggung', groupIdNameEn: 'Back', nameId: 'Hip hinge drill', nameEn: 'Hip hinge drill', targetId: 'Hamstring, punggung, glutes', targetEn: 'Hamstrings, back, glutes', repsId: '10–12 repetisi', repsEn: '10–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Dinding opsional', equipmentEn: 'Optional wall', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Tekuk pinggul dengan lutut sedikit menekuk dan punggung netral. Dorong pinggul ke belakang seolah menyentuh dinding, lalu berdiri.', instructionsEn: 'Hinge at the hips with a soft knee bend and neutral back. Push hips back as if reaching for a wall, then stand.', timerSeconds: 40),

  // Shoulders and arms
  _StrengthExercise(id: 'shoulder-press', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Dumbbell shoulder press', nameEn: 'Dumbbell shoulder press', targetId: 'Bahu, trisep', targetEn: 'Shoulders, triceps', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell ringan–sedang', equipmentEn: 'Light–moderate dumbbells', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Mulai dengan beban setinggi bahu. Dorong ke atas dengan rusuk tetap terkendali; hentikan jika terasa nyeri.', instructionsEn: 'Start with weights at shoulder height. Press upward while keeping ribs down; stop if painful.', timerSeconds: 40),
  _StrengthExercise(id: 'lateral-raise', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Lateral raise', nameEn: 'Lateral raise', targetId: 'Bahu samping', targetEn: 'Side delts', repsId: '10–15 repetisi', repsEn: '10–15 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell ringan atau botol', equipmentEn: 'Light dumbbells or bottles', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Angkat lengan ke samping hingga sekitar tinggi bahu. Gunakan beban ringan dan jangan mengayunkan badan.', instructionsEn: 'Raise arms out to roughly shoulder height. Use light weights and avoid swinging the torso.', timerSeconds: 40),
  _StrengthExercise(id: 'biceps-curl', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Biceps curl', nameEn: 'Biceps curl', targetId: 'Biceps', targetEn: 'Biceps', repsId: '10–12 repetisi', repsEn: '10–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell atau botol air', equipmentEn: 'Dumbbells or water bottles', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Jaga siku di dekat sisi tubuh. Tekuk siku untuk mengangkat beban lalu turunkan perlahan tanpa mengayun.', instructionsEn: 'Keep elbows by your sides. Curl weights up and lower slowly without swinging.', timerSeconds: 40),
  _StrengthExercise(id: 'hammer-curl', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Hammer curl', nameEn: 'Hammer curl', targetId: 'Biceps, brachialis', targetEn: 'Biceps, brachialis', repsId: '10–12 repetisi', repsEn: '10–12 reps', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell atau botol air', equipmentEn: 'Dumbbells or water bottles', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Pegang beban dengan telapak saling berhadapan. Angkat tanpa menggerakkan siku ke depan.', instructionsEn: 'Hold weights with palms facing inward. Curl without letting elbows drift forward.', timerSeconds: 40),
  _StrengthExercise(id: 'triceps-kickback', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Triceps kickback', nameEn: 'Triceps kickback', targetId: 'Trisep', targetEn: 'Triceps', repsId: '10–12 per sisi', repsEn: '10–12 per side', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dumbbell ringan', equipmentEn: 'Light dumbbell', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Condong dari pinggul dengan punggung netral. Pertahankan siku dekat badan dan luruskan lengan ke belakang, lalu kembali.', instructionsEn: 'Hinge forward with a neutral back. Keep elbow near the body, extend forearm backward, then return.', timerSeconds: 40),
  _StrengthExercise(id: 'front-raise', groupId: 'shoulders', groupIdNameId: 'Bahu & lengan', groupIdNameEn: 'Shoulders & arms', nameId: 'Front raise', nameEn: 'Front raise', targetId: 'Bahu depan', targetEn: 'Front delts', repsId: '10–12 repetisi', repsEn: '10–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Beban ringan', equipmentEn: 'Light weights', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Angkat beban ke depan hingga nyaman tanpa mengangkat bahu. Turunkan perlahan dan hindari ayunan.', instructionsEn: 'Raise weights forward only as high as comfortable without shrugging. Lower slowly and avoid swinging.', timerSeconds: 40),

  // Hips and runner-specific stability
  _StrengthExercise(id: 'clamshell', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Clamshell', nameEn: 'Clamshell', targetId: 'Gluteus medius', targetEn: 'Gluteus medius', repsId: '12–15 per sisi', repsEn: '12–15 per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras, band opsional', equipmentEn: 'Mat, optional band', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaring miring dengan lutut ditekuk dan tumit menyatu. Buka lutut atas tanpa memutar panggul ke belakang.', instructionsEn: 'Lie on your side with knees bent and heels together. Open the top knee without rolling the pelvis backward.', timerSeconds: 40),
  _StrengthExercise(id: 'side-leg-raise', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Side-lying leg raise', nameEn: 'Side-lying leg raise', targetId: 'Abduktor pinggul', targetEn: 'Hip abductors', repsId: '10–15 per sisi', repsEn: '10–15 per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaring miring, kaki bawah sedikit ditekuk. Angkat kaki atas tanpa memutar ujung kaki ke langit-langit.', instructionsEn: 'Lie on your side with the lower leg bent slightly. Lift the top leg without rotating the toes toward the ceiling.', timerSeconds: 40),
  _StrengthExercise(id: 'single-leg-balance', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Single-leg balance', nameEn: 'Single-leg balance', targetId: 'Pergelangan, pinggul', targetEn: 'Ankles, hips', repsId: 'Tahan 20–30 detik per sisi', repsEn: 'Hold 20–30 seconds per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Lantai datar, pegangan opsional', equipmentEn: 'Flat floor, optional support', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berdiri satu kaki dengan lutut sedikit menekuk. Pandangan lurus; dekatkan tangan ke pegangan jika keseimbangan belum stabil.', instructionsEn: 'Stand on one foot with a soft knee. Look ahead and stay near a support if balance is uncertain.', timerSeconds: 25),
  _StrengthExercise(id: 'single-leg-hinge', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Single-leg hip hinge', nameEn: 'Single-leg hip hinge', targetId: 'Glutes, hamstring, keseimbangan', targetEn: 'Glutes, hamstrings, balance', repsId: '6–10 per sisi', repsEn: '6–10 per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Tanpa alat, dinding opsional', equipmentEn: 'No equipment, optional wall', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Berdiri satu kaki. Dorong pinggul ke belakang dan rentangkan kaki lainnya untuk keseimbangan, lalu kembali tegak.', instructionsEn: 'Stand on one leg. Hinge hips back and extend the other leg for balance, then return upright.', timerSeconds: 40),
  _StrengthExercise(id: 'marching-bridge', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Bridge march', nameEn: 'Bridge march', targetId: 'Glutes, core', targetEn: 'Glutes, core', repsId: '8–10 angkatan per sisi', repsEn: '8–10 lifts per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Mulai dari glute bridge. Pertahankan pinggul tetap rata saat mengangkat satu kaki beberapa sentimeter secara bergantian.', instructionsEn: 'Start in a glute bridge. Keep hips level while lifting one foot a few centimetres at a time, alternating sides.', timerSeconds: 30),
  _StrengthExercise(id: 'standing-hip-abduction', groupId: 'hips', groupIdNameId: 'Pinggul & stabilitas lari', groupIdNameEn: 'Hips & running stability', nameId: 'Standing hip abduction', nameEn: 'Standing hip abduction', targetId: 'Sisi pinggul', targetEn: 'Side hips', repsId: '12 per sisi', repsEn: '12 per side', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Dinding untuk keseimbangan', equipmentEn: 'Wall for balance', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berdiri tegak dekat dinding. Gerakkan satu kaki ke samping tanpa memiringkan badan, kemudian kembali perlahan.', instructionsEn: 'Stand tall near a wall. Move one leg sideways without leaning the torso, then return slowly.', timerSeconds: 40),

  // Full body
  _StrengthExercise(id: 'farmer-carry', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'Farmer carry', nameEn: 'Farmer carry', targetId: 'Genggaman, core, postur', targetEn: 'Grip, core, posture', repsId: 'Jalan 20–40 meter', repsEn: 'Walk 20–40 metres', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Dua beban ringan–sedang', equipmentEn: 'Two light–moderate weights', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Bawa beban di sisi tubuh, berdiri tinggi, dan berjalan dengan langkah stabil. Jangan memiringkan badan ke salah satu sisi.', instructionsEn: 'Carry weights at your sides, stand tall, and walk steadily. Avoid leaning to either side.', timerSeconds: 30),
  _StrengthExercise(id: 'bear-hold', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'Bear hover hold', nameEn: 'Bear hover hold', targetId: 'Core, bahu, paha', targetEn: 'Core, shoulders, thighs', repsId: 'Tahan 10–20 detik', repsEn: 'Hold 10–20 seconds', setsId: '3 set', setsEn: '3 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Posisi merangkak, angkat lutut sedikit dari lantai. Jaga punggung stabil dan napas teratur; letakkan lutut kembali jika bentuk berubah.', instructionsEn: 'Start on hands and knees, then hover knees just above the floor. Keep the back steady and breathe; lower knees if form changes.', timerSeconds: 20),
  _StrengthExercise(id: 'march-in-place', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'March in place', nameEn: 'March in place', targetId: 'Pinggul, kaki, koordinasi', targetEn: 'Hips, legs, coordination', repsId: '30–60 detik', repsEn: '30–60 seconds', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Berbaris di tempat dengan badan tegak dan ayunan lengan alami. Pilih tinggi lutut yang nyaman dan jangan memaksa kecepatan.', instructionsEn: 'March in place with an upright torso and natural arm swing. Choose a comfortable knee height and do not force speed.', timerSeconds: 40),
  _StrengthExercise(id: 'bird-dog-row', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'Quadruped shoulder tap', nameEn: 'Quadruped shoulder tap', targetId: 'Core, bahu', targetEn: 'Core, shoulders', repsId: '8–12 per sisi', repsEn: '8–12 per side', setsId: '2 set', setsEn: '2 sets', equipmentId: 'Matras', equipmentEn: 'Mat', levelId: 'Menengah', levelEn: 'Intermediate', instructionsId: 'Posisi merangkak dengan tangan di bawah bahu. Sentuh bahu berlawanan secara bergantian tanpa mengayunkan pinggul.', instructionsEn: 'Start on hands and knees with hands under shoulders. Tap the opposite shoulder in turns without rocking hips.', timerSeconds: 35),
  _StrengthExercise(id: 'low-impact-squat-reach', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'Squat to reach', nameEn: 'Squat to reach', targetId: 'Kaki, bahu, koordinasi', targetEn: 'Legs, shoulders, coordination', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Pemula', levelEn: 'Beginner', instructionsId: 'Lakukan squat dangkal yang nyaman, lalu berdiri sambil meraih tangan ke atas. Bergerak pelan dan hindari lompatan.', instructionsEn: 'Perform a comfortable shallow squat, then stand and reach arms overhead. Move slowly and avoid jumping.', timerSeconds: 40),
  _StrengthExercise(id: 'calf-to-squat', groupId: 'full', groupIdNameId: 'Seluruh tubuh', groupIdNameEn: 'Full body', nameId: 'Squat and calf raise', nameEn: 'Squat and calf raise', targetId: 'Paha, betis', targetEn: 'Thighs, calves', repsId: '8–12 repetisi', repsEn: '8–12 reps', setsId: '2–3 set', setsEn: '2–3 sets', equipmentId: 'Tanpa alat', equipmentEn: 'No equipment', levelId: 'Pemula–menengah', levelEn: 'Beginner–intermediate', instructionsId: 'Dari berdiri, lakukan squat dangkal lalu berdiri dan angkat tumit. Pegang penyangga bila dibutuhkan.', instructionsEn: 'Perform a shallow squat, stand up, then raise heels. Hold a support if needed.', timerSeconds: 40),
];
