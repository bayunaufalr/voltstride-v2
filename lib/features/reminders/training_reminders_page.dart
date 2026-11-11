// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
import 'reminder_service.dart';
import '../running/models/run_session.dart';
import '../running/services/run_history_repository.dart';
import '../running/services/training_plan_repository.dart';
import '../running/services/training_plan_service.dart';

class TrainingRemindersPage extends StatefulWidget {
  const TrainingRemindersPage({super.key, this.embedded = false});

  /// true berarti halaman tampil di dalam tab Anda.
  final bool embedded;

  @override
  TrainingRemindersPageState createState() => TrainingRemindersPageState();
}

class TrainingRemindersPageState extends State<TrainingRemindersPage>
    with SingleTickerProviderStateMixin {
  List<TrainingReminder> _reminders = <TrainingReminder>[];
  List<RunSession> _sessions = <RunSession>[];
  List<SavedTrainingPlan> _trainingPlans = <SavedTrainingPlan>[];
  final Map<String, List<TrainingPlanDay>> _trainingPlanDays =
      <String, List<TrainingPlanDay>>{};
  bool _loading = true;
  bool _saving = false;
  int _lastCategoryIndex = 0;
  int? _previousCategory;
  late final TabController _categoryController;

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  void initState() {
    super.initState();
    _categoryController = TabController(length: 5, vsync: this);
    _categoryController.addListener(_trackCategoryHistory);
    ReminderService.changes.addListener(_onReminderDataChanged);
    _loadReminders();
  }

  @override
  void dispose() {
    ReminderService.changes.removeListener(_onReminderDataChanged);
    _categoryController.removeListener(_trackCategoryHistory);
    _categoryController.dispose();
    super.dispose();
  }

  void _trackCategoryHistory() {
    final int currentIndex = _categoryController.index;
    if (currentIndex == _lastCategoryIndex) return;
    _previousCategory = _lastCategoryIndex;
    _lastCategoryIndex = currentIndex;
  }

  bool handleBack() {
    final int? previousIndex = _previousCategory;
    if (previousIndex == null) return false;
    _previousCategory = null;
    _lastCategoryIndex = previousIndex;
    _categoryController.animateTo(previousIndex);
    return true;
  }

  void _onReminderDataChanged() {
    if (mounted) _loadReminders();
  }

  Future<void> reload() => _loadReminders();

  Future<void> _loadReminders() async {
    try {
      final List<dynamic> loaded = await Future.wait<dynamic>(<Future<dynamic>>[
        ReminderService.getAll(),
        RunHistoryRepository.instance.getAll(),
        TrainingPlanRepository.instance.getPlans(limit: 12),
      ]);
      final List<TrainingReminder> saved = loaded[0] as List<TrainingReminder>;
      final List<RunSession> sessions = loaded[1] as List<RunSession>;
      final List<SavedTrainingPlan> plans =
          loaded[2] as List<SavedTrainingPlan>;
      final Map<String, List<TrainingPlanDay>> planDays =
          <String, List<TrainingPlanDay>>{};
      for (final SavedTrainingPlan plan in plans) {
        planDays[plan.id] =
            await TrainingPlanRepository.instance.getDays(plan.id);
      }
      if (!mounted) return;
      setState(() {
        _reminders = saved;
        _sessions = sessions;
        _trainingPlans = plans;
        _trainingPlanDays
          ..clear()
          ..addAll(planDays);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editReminder({TrainingReminder? reminder}) async {
    final int nextId = reminder?.id ??
        (_reminders.fold<int>(
              0,
              (int highest, TrainingReminder item) =>
                  item.id > highest ? item.id : highest,
            ) +
            1);
    final TrainingReminder? result = await showDialog<TrainingReminder>(
      context: context,
      builder: (BuildContext context) => _ReminderEditor(
        newId: nextId,
        initial: reminder,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ReminderService.save(result);
      await _loadReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('Jadwal disimpan.', 'Schedule saved.'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Jadwal tersimpan, tetapi notifikasi gagal dijadwalkan: $error',
              'Schedule saved, but the notification could not be scheduled: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteReminder(TrainingReminder reminder) async {
    try {
      await ReminderService.delete(reminder);
      await _loadReminders();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Jadwal belum berhasil dihapus.', 'Could not delete schedule.'),
          ),
        ),
      );
    }
  }

  Future<void> _markNotCompleted(_ReminderOccurrence occurrence) async {
    final TextEditingController otherReason = TextEditingController();
    const List<String> reasonsId = <String>[
      'Tidak sempat',
      'Cuaca tidak mendukung',
      'Kurang sehat',
      'Nyeri atau cedera',
      'Alasan lain',
    ];
    const List<String> reasonsEn = <String>[
      'Not enough time',
      'Weather conditions',
      'Unwell',
      'Pain or injury',
      'Other reason',
    ];
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final List<String> reasons = english ? reasonsEn : reasonsId;
    String selectedReason = reasons.first;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
          title: Text(_text('Latihan tidak terlaksana', 'Workout not completed')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _text('Alasan', 'Reason'),
                  ),
                  items: reasons
                      .map((String option) => DropdownMenuItem<String>(
                            value: option,
                            child: Text(option),
                          ))
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value != null) {
                      setDialogState(() => selectedReason = value);
                    }
                  },
                ),
                if (selectedReason == reasons.last) ...<Widget>[
                  const SizedBox(height: 10),
                  TextField(
                    controller: otherReason,
                    autofocus: true,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _text('Alasan', 'Reason'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_text('Kembali', 'Back')),
            ),
            FilledButton(
              onPressed: () {
                final String value = selectedReason == reasons.last
                    ? otherReason.text.trim()
                    : selectedReason;
                if (value.isEmpty) return;
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(_text('Simpan alasan', 'Save reason')),
            ),
          ],
        ),
      ),
    );
    otherReason.dispose();
    if (reason == null || reason.trim().isEmpty || !mounted) return;
    try {
      await ReminderService.setOccurrenceNotCompleted(
        reminderId: occurrence.reminder.id,
        dateKey: occurrence.dateKey,
        reason: reason,
      );
      await _loadReminders();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_text(
            'Status tidak terlaksana belum berhasil disimpan.',
            'Could not save the missed-workout status.',
          )),
        ),
      );
    }
  }

  Future<void> _setCompleted(
    _ReminderOccurrence occurrence, {
    required bool completed,
    String reason = '',
  }) async {
    try {
      await ReminderService.setOccurrenceCompleted(
        reminderId: occurrence.reminder.id,
        dateKey: occurrence.dateKey,
        completed: completed,
        reason: reason,
      );
      await _loadReminders();
    } catch (_) {
      await _loadReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Status lokal diperbarui, tetapi notifikasi Android belum dapat diselaraskan.',
              'The local status changed, but the Android notification could not be synchronized.',
            ),
          ),
        ),
      );
    }
  }

  String _activityCategoryForSession(RunSession session) {
    // HIIT juga menyimpan rencana interval, jadi periksa jenis HIIT lebih dulu.
    if (session.activityType == RunActivityType.hiit) return 'hiit';
    if (session.intervalPlan != null) return 'interval';
    return session.activityType.name;
  }

  List<RunSession> _matchingActivitySessions(_ReminderOccurrence occurrence) {
    final TrainingReminder reminder = occurrence.reminder;
    final List<RunSession> matches = _sessions.where((RunSession session) {
      return ReminderService.matchesDateAndCategory(
        reminder: reminder,
        startedAt: session.startedAt,
        activityCategory: _activityCategoryForSession(session),
      );
    }).toList(growable: false)
      ..sort((RunSession a, RunSession b) =>
          b.startedAt.compareTo(a.startedAt));
    return matches;
  }

  List<RunSession> _eligibleActivitySessions(
    _ReminderOccurrence occurrence,
  ) {
    return _matchingActivitySessions(occurrence)
        .where((RunSession session) =>
            ReminderService.activityFinishedBeforePlannedTime(
              reminder: occurrence.reminder,
              startedAt: session.startedAt,
              duration: session.elapsed,
              activityCategory: _activityCategoryForSession(session),
              finishedAt: session.finishedAt,
            ))
        .toList(growable: false);
  }

  Future<void> _completeWithReason(
    _ReminderOccurrence occurrence,
    RunSession session,
  ) async {
    final TextEditingController reasonController = TextEditingController();
    final int creditedSeconds =
        occurrence.reminder.activityDurationSecondsByDate[occurrence.dateKey] ?? 0;
    final List<RunSession> sessions = _eligibleActivitySessions(occurrence);
    final int recordedSeconds = sessions.fold<int>(
      0,
      (int total, RunSession item) => total + item.elapsed.inSeconds,
    );
    // Durasi parsial disimpan juga untuk pemulihan alarm native. Jika riwayat
    // tersedia, gunakan total sesi sebenarnya agar tidak menghitung ganda.
    final int actualSeconds = recordedSeconds > 0
        ? recordedSeconds
        : creditedSeconds > 0
            ? creditedSeconds
            : session.elapsed.inSeconds;
    final String actualMinutes = (actualSeconds / 60).toStringAsFixed(1);
    final int targetMinutes = occurrence.reminder.durationMinutes;
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(_text('Selesaikan jadwal?', 'Complete this schedule?')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(_text(
                'Aktivitas tercatat $actualMinutes menit, sedangkan targetnya $targetMinutes menit. Durasi tidak sesuai dengan rencana.',
                'The activity lasted $actualMinutes minutes, while the target was $targetMinutes minutes. The recorded duration does not match the plan.',
              )),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                autofocus: true,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _text('Alasan menyelesaikan jadwal', 'Reason for completing the schedule'),
                  hintText: _text('Contoh: latihan dipersingkat karena hujan', 'Example: shortened the workout because of rain'),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_text('Kembali', 'Back')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () {
              final String value = reasonController.text.trim();
              if (value.isEmpty) return;
              Navigator.of(dialogContext).pop(value);
            },
            child: Text(_text('Tetap selesai', 'Complete anyway')),
          ),
        ],
      ),
    );
    reasonController.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    await _setCompleted(occurrence, completed: true, reason: reason);
  }

  Widget _routineScheduleList() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_reminders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(_text(
            'Belum ada jadwal. Tambahkan jadwal rutin atau tanggal tertentu.',
            'No schedules yet. Add a routine or one-time schedule.',
          )),
        ),
      );
    }
    final List<TrainingReminder> sorted = List<TrainingReminder>.of(_reminders)
      ..sort((TrainingReminder a, TrainingReminder b) {
        final DateTime dateA = a.specificDate ?? DateTime(2100);
        final DateTime dateB = b.specificDate ?? DateTime(2100);
        final int byDate = dateA.compareTo(dateB);
        if (byDate != 0) return byDate;
        final int byHour = a.hour.compareTo(b.hour);
        return byHour != 0 ? byHour : a.minute.compareTo(b.minute);
      });
    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
        itemCount: sorted.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) =>
            _routineScheduleCard(sorted[index]),
      ),
    );
  }

  Widget _routineScheduleCard(TrainingReminder reminder) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Icon(Icons.notifications_active_outlined, color: colors.onSurface),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _reminderTitle(reminder),
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${reminder.scheduleType == ReminderScheduleType.specificDate ? _specificDateText(reminder.specificDate) : _text('Rutin · ${_scheduleDaysText(reminder)}', 'Routine · ${_scheduleDaysText(reminder)}')} · ${reminder.timeText}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                if (!ReminderService.isVehicleCheckReminder(reminder))
                  Text(
                    '${_text('Target aktivitas', 'Activity target')}: '
                    '${reminder.durationMinutes} ${_text('menit', 'min')} · '
                    '${_text('Notifikasi', 'Notification')}',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  )
                else
                  Text(
                    _text('Pemeriksaan kendaraan · Notifikasi',
                        'Vehicle inspection · Notification'),
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: _text('Pengaturan jadwal', 'Schedule options'),
            onSelected: (String action) {
              if (action == 'edit') {
                _editReminder(reminder: reminder);
              } else if (action == 'delete') {
                _deleteReminder(reminder);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: Text(_text('Ubah jadwal', 'Edit schedule')),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(_text('Hapus jadwal', 'Delete schedule')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _scheduleDaysText(TrainingReminder reminder) {
    const List<String> id = <String>[
      'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min',
    ];
    const List<String> en = <String>[
      'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
    ];
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final List<int> days = reminder.weekdays.toList()..sort();
    return days.map((int day) => (english ? en : id)[day - 1]).join(' · ');
  }

  List<_ReminderOccurrence> _occurrencesForThisWeek() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime monday = today.subtract(Duration(days: today.weekday - 1));
    final List<_ReminderOccurrence> result = <_ReminderOccurrence>[];

    for (int offset = 0; offset < 7; offset++) {
      final DateTime day = monday.add(Duration(days: offset));
      for (final TrainingReminder reminder in _reminders) {
        if (reminder.scheduleType == ReminderScheduleType.specificDate) {
          final DateTime? scheduledDate = reminder.specificDate;
          if (scheduledDate == null ||
              scheduledDate.year != day.year ||
              scheduledDate.month != day.month ||
              scheduledDate.day != day.day) {
            continue;
          }
          result.add(_ReminderOccurrence(reminder: reminder, date: day));
        } else if (reminder.weekdays.contains(day.weekday)) {
          result.add(_ReminderOccurrence(reminder: reminder, date: day));
        }
      }
    }

    result.sort((_ReminderOccurrence a, _ReminderOccurrence b) {
      final DateTime dateA = DateTime(
        a.date.year,
        a.date.month,
        a.date.day,
        a.reminder.hour,
        a.reminder.minute,
      );
      final DateTime dateB = DateTime(
        b.date.year,
        b.date.month,
        b.date.day,
        b.reminder.hour,
        b.reminder.minute,
      );
      return dateA.compareTo(dateB);
    });
    return result;
  }

  List<_ReminderOccurrence> _completedOccurrences() {
    final List<_ReminderOccurrence> completed = <_ReminderOccurrence>[];
    for (final TrainingReminder reminder in _reminders) {
      for (final String dateKey in reminder.completedDates) {
        final DateTime? date = DateTime.tryParse(dateKey);
        if (date == null) continue;
        completed.add(_ReminderOccurrence(
          reminder: reminder,
          date: DateTime(date.year, date.month, date.day),
        ));
      }
    }
    completed.sort((_ReminderOccurrence a, _ReminderOccurrence b) =>
        b.date.compareTo(a.date));
    return completed;
  }

  List<_ReminderOccurrence> _notCompletedOccurrences() {
    final List<_ReminderOccurrence> missed = <_ReminderOccurrence>[];
    for (final TrainingReminder reminder in _reminders) {
      for (final String dateKey in reminder.notCompletedDates) {
        final DateTime? date = DateTime.tryParse(dateKey);
        if (date == null) continue;
        missed.add(_ReminderOccurrence(
          reminder: reminder,
          date: DateTime(date.year, date.month, date.day),
        ));
      }
    }
    missed.sort((_ReminderOccurrence a, _ReminderOccurrence b) =>
        b.date.compareTo(a.date));
    return missed;
  }

  Widget _categoryList({required int category}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<_ReminderOccurrence> items;
    final String emptyMessage;
    if (category == 1) {
      items = _completedOccurrences();
      emptyMessage = _text(
        'Belum ada latihan yang ditandai selesai.',
        'No completed sessions yet.',
      );
    } else if (category == 2) {
      items = _notCompletedOccurrences();
      emptyMessage = _text(
        'Belum ada latihan yang tercatat tidak terlaksana.',
        'No missed workouts recorded.',
      );
    } else {
      items = _occurrencesForThisWeek()
          .where((_ReminderOccurrence item) =>
              !item.completed && !item.notCompleted)
          .toList(growable: false);
      emptyMessage = _text(
        'Tidak ada jadwal yang belum selesai.',
        'No unfinished sessions.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 92),
        itemCount: items.isEmpty ? 1 : items.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: Text(emptyMessage)),
            );
          }
          return _occurrenceCard(items[index]);
        },
      ),
    );
  }

  Widget _occurrenceCard(_ReminderOccurrence occurrence) {
    final TrainingReminder reminder = occurrence.reminder;
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String days = _weekdayName(occurrence.date.weekday);
    final String dateText = '$days, ${occurrence.date.day} '
        '${_monthName(occurrence.date.month)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _reminderTitle(reminder),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('$dateText · ${reminder.timeText}'),
          if (!ReminderService.isVehicleCheckReminder(reminder))
            Text(
              '${_text('Target aktivitas', 'Activity target')}: '
              '${reminder.durationMinutes} ${_text('menit', 'min')}',
            ),
          if (ReminderService.isVehicleCheckReminder(reminder))
            Text(_text('Pemeriksaan kendaraan', 'Vehicle inspection')),
          const SizedBox(height: 10),
          if (occurrence.completed || occurrence.notCompleted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest,
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    occurrence.completed
                        ? _text('Selesai', 'Completed')
                        : _text('Tidak terlaksana', 'Not completed'),
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (occurrence.notCompleted &&
                      (occurrence.reason?.isNotEmpty ?? false)) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      _text('Alasan: ${occurrence.reason}', 'Reason: ${occurrence.reason}'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (occurrence.completed &&
                      (occurrence.completionReason?.isNotEmpty ?? false)) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      _text('Alasan: ${occurrence.completionReason}', 'Reason: ${occurrence.completionReason}'),
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            )
          else
            _buildOccurrenceActions(occurrence, colors),
        ],
      ),
    );
  }

  Widget _buildOccurrenceActions(
    _ReminderOccurrence occurrence,
    ColorScheme colors,
  ) {
    final List<RunSession> activities =
        _eligibleActivitySessions(occurrence);
    final RunSession? latest = activities.isEmpty ? null : activities.first;
    if (ReminderService.isVehicleCheckReminder(occurrence.reminder)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _text(
              'Pengingat ini untuk pemeriksaan kendaraan, bukan sesi olahraga. Tandai selesai setelah pemeriksaan dilakukan.',
              'This is a vehicle check reminder, not a workout. Mark it complete after checking the vehicle.',
            ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _setCompleted(occurrence, completed: true),
                  icon: const Icon(Icons.check_circle_outline_rounded),
                  label: Text(_text('Selesai', 'Complete')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _markNotCompleted(occurrence),
                  icon: const Icon(Icons.event_busy_outlined),
                  label: Text(_text('Tidak terlaksana', 'Not completed')),
                ),
              ),
            ],
          ),
        ],
      );
    }
    final int partialSeconds =
        occurrence.reminder.activityDurationSecondsByDate[occurrence.dateKey] ?? 0;
    final int targetSeconds = occurrence.reminder.durationMinutes * 60;
    final int eligibleSeconds = activities.fold<int>(
      0,
      (int total, RunSession session) => total + session.elapsed.inSeconds,
    );
    // Durasi dapat berasal dari beberapa sesi sebelum waktu jadwal.
    final bool exactMatch = eligibleSeconds == targetSeconds ||
        (eligibleSeconds == 0 && partialSeconds == targetSeconds);

    if (latest == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _text(
              'Belum ada aktivitas yang memenuhi waktu jadwal pada tanggal ini. Tandai tidak terlaksana dan masukkan alasannya.',
              'No activity met the scheduled time on this date. Mark it not completed and provide a reason.',
            ),
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _markNotCompleted(occurrence),
              icon: const Icon(Icons.event_busy_outlined),
              label: Text(_text('Tidak terlaksana', 'Not completed')),
            ),
          ),
        ],
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.icon(
            style: exactMatch
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  ),
            onPressed: exactMatch
                ? () => _setCompleted(occurrence, completed: true)
                : () => _completeWithReason(occurrence, latest),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Text(_text('Selesai', 'Complete')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _markNotCompleted(occurrence),
            icon: const Icon(Icons.event_busy_outlined),
            label: Text(_text('Tidak terlaksana', 'Not completed')),
          ),
        ),
      ],
    );
  }

  String _reminderTitle(TrainingReminder reminder) {
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    if (ReminderService.isVehicleCheckReminder(reminder)) {
      final String customName = reminder.activityName.trim();
      if (customName.isEmpty) {
        return _text('Pengingat pemeriksaan motor',
            'Motorcycle inspection reminder');
      }
      return english
          ? 'Motorcycle inspection · $customName'
          : 'Pemeriksaan motor · $customName';
    }
    final String name = reminder.activityName.trim();
    if (name.isNotEmpty) {
      return english
          ? 'Routine workout · $name'
          : 'Latihan rutin · $name';
    }
    return english
        ? 'Routine workout · ${_activityName(reminder.activity)}'
        : 'Latihan rutin ${_activityName(reminder.activity)}';
  }

  String _activityName(String activity) {
    final String value = activity.toLowerCase();
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    if (value.contains('motor')) {
      return english ? 'motorcycle inspection' : 'pemeriksaan motor';
    }
    if (value.contains('interval')) {
      return english ? 'interval running' : 'lari interval';
    }
    if (value.contains('sepeda') || value.contains('cycling') ||
        value.contains('cycle')) {
      return english ? 'cycling' : 'bersepeda';
    }
    if (value.contains('hiit')) return 'HIIT';
    if (value.contains('walk') || value.contains('jalan')) {
      return english ? 'walking' : 'berjalan';
    }
    if (value.contains('run') || value.contains('lari')) {
      return english ? 'running' : 'berlari';
    }
    if (value.contains('other') || value.contains('lain')) {
      return english ? 'other activity' : 'aktivitas lainnya';
    }
    return activity;
  }

  String _specificDateText(DateTime? date) {
    if (date == null) return _text('Tanggal belum dipilih', 'No date selected');
    return '${date.day} ${_monthName(date.month)} ${date.year}';
  }

  String _weekdayName(int weekday) {
    const List<String> indonesia = <String>[
      'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
    ];
    const List<String> english = <String>[
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    return Localizations.localeOf(context).languageCode == 'en'
        ? english[weekday - 1]
        : indonesia[weekday - 1];
  }

  String _monthName(int month) {
    const List<String> indonesia = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    const List<String> english = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return Localizations.localeOf(context).languageCode == 'en'
        ? english[month - 1]
        : indonesia[month - 1];
  }


  String _planGoalLabel(TrainingGoal goal) => switch (goal) {
        TrainingGoal.endurance => _text('Daya tahan', 'Endurance'),
        TrainingGoal.pace => _text('Pace', 'Pace'),
        TrainingGoal.vo2max => 'VO₂max',
      };

  String _planStrategyLabel(TrainingStrategy strategy) => switch (strategy) {
        TrainingStrategy.progressive => _text('Progresif', 'Progressive'),
        TrainingStrategy.balanced => _text('Seimbang', 'Balanced'),
        TrainingStrategy.lowImpact => _text('Beban ringan', 'Low impact'),
      };

  String _planActivityLabel(RunActivityType type) => switch (type) {
        RunActivityType.run => _text('Lari', 'Run'),
        RunActivityType.walk => _text('Berjalan', 'Walk'),
        RunActivityType.cycle => _text('Bersepeda', 'Cycling'),
        RunActivityType.hiit => 'HIIT',
      };

  Future<void> _deleteTrainingPlan(SavedTrainingPlan plan) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_text('Hapus rencana latihan?', 'Delete training plan?')),
          content: Text(_text(
            'Rencana ${plan.title} dan seluruh jadwalnya akan dihapus. Riwayat aktivitas yang sudah direkam tidak ikut dihapus.',
            '${plan.title} and its scheduled sessions will be deleted. Recorded activity history will remain.',
          )),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_text('Batal', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_text('Hapus rencana', 'Delete plan')),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await TrainingPlanRepository.instance.deletePlan(plan.id);
      await _loadReminders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Rencana latihan dihapus.', 'Training plan deleted.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Rencana belum berhasil dihapus.', 'Could not delete training plan.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markPlanDayNotCompleted(TrainingPlanDay day) async {
    if (_saving || day.completed || day.isRestDay || day.notCompleted) return;
    setState(() => _saving = true);
    try {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(_text('Tandai tidak terlaksana?', 'Mark as not completed?')),
          content: Text(_text(
            'Sesi ${day.title} akan ditandai tidak terlaksana. Sesi lain dalam rencana tidak berubah.',
            '${day.title} will be marked as not completed. Other sessions in the plan will stay unchanged.',
          )),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_text('Batal', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_text('Tandai', 'Mark')),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await TrainingPlanRepository.instance.markDayNotCompleted(day.id);
      await _loadReminders();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Status sesi belum berhasil diperbarui.', 'Could not update the session status.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _planDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _planStatus(SavedTrainingPlan plan) {
    final DateTime today = DateTime.now();
    final DateTime date = DateTime(today.year, today.month, today.day);
    if (plan.endDate.isBefore(date)) return _text('Berakhir', 'Ended');
    if (plan.startDate.isAfter(date)) return _text('Akan datang', 'Upcoming');
    return _text('Aktif', 'Active');
  }

  Widget _trainingPlansList() {
    if (_trainingPlans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.event_note_outlined, size: 42),
              const SizedBox(height: 10),
              Text(
                _text('Belum ada rencana latihan dari VoltStride.',
                    'No training plans have been created in VoltStride yet.'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _text('Buat rencana melalui Rekam aktivitas. Rencana yang disimpan akan muncul di sini.',
                    'Create a plan from Record activity. Saved plans will appear here.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReminders,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: _trainingPlans.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final SavedTrainingPlan plan = _trainingPlans[index];
          final List<TrainingPlanDay> days =
              _trainingPlanDays[plan.id] ?? <TrainingPlanDay>[];
          final int scheduledCount =
              days.where((TrainingPlanDay day) => !day.isRestDay).length;
          final int completedCount = days
              .where((TrainingPlanDay day) =>
                  !day.isRestDay && day.completed)
              .length;
          final double progress = scheduledCount == 0
              ? 0
              : completedCount / scheduledCount;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey<String>('saved-training-plan-${plan.id}'),
              initiallyExpanded: index == 0,
              leading: const Icon(Icons.event_note_rounded),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: _text('Hapus rencana', 'Delete plan'),
                    onPressed: _saving ? null : () => _deleteTrainingPlan(plan),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
              title: Text(
                plan.title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${_planGoalLabel(plan.goal)} • ${_planStrategyLabel(plan.strategy)} • ${_planStatus(plan)}',
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_planDate(plan.startDate)} – ${_planDate(plan.endDate)} • ${plan.sessionHour.toString().padLeft(2, '0')}:${plan.sessionMinute.toString().padLeft(2, '0')}',
                    ),
                    const SizedBox(height: 7),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$completedCount/$scheduledCount ${_text('sesi selesai', 'sessions completed')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              children: <Widget>[
                if (plan.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(plan.summary),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      plan.targetDescription,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                if (plan.advantages.isNotEmpty || plan.disadvantages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_text('Kelebihan', 'Advantages')}: ${plan.advantages.join('; ')}\n${_text('Hal yang perlu diperhatikan', 'Trade-offs')}: ${plan.disadvantages.join('; ')}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const Divider(height: 1),
                ...days.map((TrainingPlanDay day) {
                  final String dayDetails = day.isRestDay
                      ? _text('Pemulihan', 'Recovery')
                      : '${_planActivityLabel(day.activityType)} • ${day.durationMinutes} menit • ${day.intensity}';
                  final String intervalDetails = day.intervalPlan == null
                      ? ''
                      : '\n${day.intervalPlan!.workSeconds} detik kerja • ${day.intervalPlan!.recoverySeconds} detik pemulihan • ${day.intervalPlan!.repetitions} ulangan';
                  return ListTile(
                    dense: true,
                    leading: SizedBox(
                      width: 43,
                      child: Text(
                        _planDate(day.date),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    title: Text(
                      day.title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('${day.notCompleted ? _text('Tidak terlaksana', 'Not completed') + '\n' : ''}$dayDetails\n${day.description}$intervalDetails'),
                    isThreeLine: true,
                    trailing: day.completed
                        ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary, size: 19)
                        : day.isRestDay
                            ? const Icon(Icons.self_improvement_rounded, size: 19)
                            : day.notCompleted
                                ? Icon(Icons.event_busy_rounded, color: Theme.of(context).colorScheme.error, size: 19)
                                : IconButton(
                                    tooltip: _text('Tandai tidak terlaksana', 'Mark not completed'),
                                    onPressed: _saving ? null : () => _markPlanDayNotCompleted(day),
                                    icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                                  ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget isi = Column(
      children: <Widget>[
        TabBar(
          controller: _categoryController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            Tab(text: _text('Rencana', 'Plans')),
            Tab(text: _text('Jadwal', 'Schedules')),
            Tab(text: _text('Minggu ini', 'This week')),
            Tab(text: _text('Selesai', 'Completed')),
            Tab(text: _text('Tidak terlaksana', 'Not completed')),
          ],
        ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _categoryController,
            children: <Widget>[
              _trainingPlansList(),
              _routineScheduleList(),
              _categoryList(category: 0),
              _categoryList(category: 1),
              _categoryList(category: 2),
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(_text('Rencanakan latihan', 'Training plan')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isi,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _editReminder(),
        icon: const Icon(Icons.add),
        label: Text(_text('Tambah jadwal', 'Add schedule')),
      ),
    );
  }
}

class _ReminderOccurrence {
  const _ReminderOccurrence({required this.reminder, required this.date});

  final TrainingReminder reminder;
  final DateTime date;

  String get dateKey => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  bool get completed => reminder.completedDates.contains(dateKey);

  bool get notCompleted => reminder.notCompletedDates.contains(dateKey);

  String? get reason => reminder.notCompletedReasons[dateKey];

  String? get completionReason => reminder.completionReasons[dateKey];
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.newId, this.initial});

  final int newId;
  final TrainingReminder? initial;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  static const List<String> _dayLabelsId = <String>[
    'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min',
  ];
  static const List<String> _dayLabelsEn = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<int> _dayNumbers = <int>[
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
    DateTime.sunday,
  ];

  late final TextEditingController _durationController;
  late final TextEditingController _activityNameController;
  late final TextEditingController _repeatIntervalController;
  late String _activity;
  late TimeOfDay _time;
  late Set<int> _selectedDays;
  late ReminderScheduleType _scheduleType;
  late DateTime _specificDate;
  String? _validationMessage;
  bool _checkingPermission = false;

  String _text(BuildContext context, String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  void initState() {
    super.initState();
    final TrainingReminder? old = widget.initial;
    _durationController = TextEditingController(
      text: (old?.durationMinutes ?? 30).toString(),
    );
    _activityNameController = TextEditingController(
      text: old?.activityName ?? '',
    );
    _repeatIntervalController = TextEditingController(
      text: (old?.repeatIntervalSeconds ?? 60).toString(),
    );
    final String savedActivity = old?.activity ?? 'Lari';
    final String normalized = savedActivity.toLowerCase();
    _activity = normalized.contains('motor')
        ? 'Pemeriksaan motor'
        : normalized.contains('interval')
            ? 'Lari interval'
            : normalized.contains('sepeda') ||
                    normalized.contains('cycling') ||
                    normalized.contains('cycle')
                ? 'Bersepeda'
                : normalized.contains('hiit')
                    ? 'HIIT'
                    : normalized.contains('jalan') ||
                            normalized.contains('walk')
                        ? 'Jalan'
                        : normalized.contains('lain') ||
                                normalized.contains('other')
                            ? 'Lainnya'
                            : 'Lari';
    _time = TimeOfDay(hour: old?.hour ?? 7, minute: old?.minute ?? 0);
    _scheduleType = old?.scheduleType ?? ReminderScheduleType.routine;
    final DateTime today = DateTime.now();
    final DateTime? oldDate = old?.specificDate;
    _specificDate = oldDate == null
        ? DateTime(today.year, today.month, today.day)
        : DateTime(oldDate.year, oldDate.month, oldDate.day);
    final List<int> savedWeekdays = old?.weekdays ?? const <int>[];
    _selectedDays = (savedWeekdays.isNotEmpty ? savedWeekdays : <int>[
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]).toSet();
  }

  @override
  void dispose() {
    _durationController.dispose();
    _activityNameController.dispose();
    _repeatIntervalController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: _text(context, 'Pilih waktu latihan', 'Choose workout time'),
    );
    if (selected != null && mounted) setState(() => _time = selected);
  }

  Future<void> _chooseDate() async {
    final DateTime today = DateTime.now();
    final DateTime firstDate = DateTime(today.year, today.month, today.day);
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _specificDate.isBefore(firstDate) ? firstDate : _specificDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 3, 12, 31),
      helpText: _text(context, 'Pilih tanggal latihan', 'Choose workout date'),
    );
    if (selected != null && mounted) {
      setState(() {
        _specificDate = DateTime(selected.year, selected.month, selected.day);
        _validationMessage = null;
      });
    }
  }

  Future<void> _save() async {
    final int? duration = int.tryParse(_durationController.text.trim());
    if (_scheduleType == ReminderScheduleType.routine && _selectedDays.isEmpty) {
      setState(() {
        _validationMessage = _text(
          context,
          'Pilih setidaknya satu hari.',
          'Choose at least one day.',
        );
      });
      return;
    }
    if (_scheduleType == ReminderScheduleType.specificDate) {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (_specificDate.isBefore(today)) {
        setState(() => _validationMessage = _text(
          context,
          'Tanggal tidak boleh di masa lalu.',
          'The date cannot be in the past.',
        ));
        return;
      }
      final bool isToday = _specificDate.year == today.year &&
          _specificDate.month == today.month && _specificDate.day == today.day;
      if (isToday && (_time.hour < now.hour ||
          (_time.hour == now.hour && _time.minute <= now.minute))) {
        setState(() => _validationMessage = _text(
          context,
          'Untuk hari ini, pilih waktu yang belum lewat.',
          'For today, choose a time that has not passed.',
        ));
        return;
      }
    }
    if (_activity != 'Pemeriksaan motor' &&
        (duration == null || duration < 5 || duration > 360)) {
      setState(() {
        _validationMessage = _text(
          context,
          'Durasi harus 5–360 menit.',
          'Duration must be 5–360 minutes.',
        );
      });
      return;
    }
    final int? repeatSeconds = int.tryParse(_repeatIntervalController.text.trim());
    if (repeatSeconds == null || repeatSeconds < 30 || repeatSeconds > 600) {
      setState(() {
        _validationMessage = _text(
          context,
          'Interval notifikasi harus 30–600 detik.',
          'Notification interval must be 30–600 seconds.',
        );
      });
      return;
    }

    setState(() {
      _checkingPermission = true;
      _validationMessage = null;
    });
    try {
      final bool allowed =
          await ReminderService.requestNotificationPermission();
      if (!mounted) return;
      if (!allowed) {
        setState(() {
          _validationMessage = _text(
            context,
            'Izinkan notifikasi VoltStride di halaman pengaturan yang terbuka, lalu kembali ke aplikasi.',
            'Allow VoltStride notifications in the settings page that opens, then return to the app.',
          );
        });
        return;
      }
      _closeWithReminder(
        _activity == 'Pemeriksaan motor' ? 30 : duration!,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _validationMessage = _text(
          context,
          'Notifikasi belum bisa dijadwalkan: $error',
          'The notification could not be scheduled: $error',
        );
      });
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  void _closeWithReminder(int duration) {
    Navigator.of(context).pop(
      TrainingReminder(
        id: widget.initial?.id ?? widget.newId,
        activity: _activity,
        activityName: _activityNameController.text.trim(),
        weekdays: _scheduleType == ReminderScheduleType.routine
            ? (_selectedDays.toList()..sort())
            : const <int>[],
        scheduleType: _scheduleType,
        specificDate: _scheduleType == ReminderScheduleType.specificDate
            ? _specificDate
            : null,
        hour: _time.hour,
        minute: _time.minute,
        durationMinutes: duration,
        repeatIntervalSeconds: int.parse(_repeatIntervalController.text.trim()),
        style: ReminderStyle.notificationOnly,
        sound: 'lembut',
        completedDates: widget.initial?.completedDates ?? const <String>[],
        notCompletedDates: widget.initial?.notCompletedDates ?? const <String>[],
        notCompletedReasons: widget.initial?.notCompletedReasons ?? const <String, String>{},
        completionReasons: widget.initial?.completionReasons ?? const <String, String>{},
        activityDurationSecondsByDate:
            widget.initial?.activityDurationSecondsByDate ?? const <String, int>{},
      ),
    );
  }

  String _monthNameForEditor(int month, bool english) {
    const List<String> id = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    const List<String> en = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return (english ? en : id)[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    final List<String> dayLabels = english ? _dayLabelsEn : _dayLabelsId;

    return AlertDialog(
      title: Text(_text(
        context,
        widget.initial == null ? 'Tambah jadwal' : 'Ubah jadwal',
        widget.initial == null ? 'Add schedule' : 'Edit schedule',
      )),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<ReminderScheduleType>(
                initialValue: _scheduleType,
                decoration: InputDecoration(
                  labelText: _text(context, 'Jenis jadwal', 'Schedule type'),
                ),
                items: <DropdownMenuItem<ReminderScheduleType>>[
                  DropdownMenuItem(
                    value: ReminderScheduleType.routine,
                    child: Text(_text(context, 'Jadwal rutin', 'Routine schedule')),
                  ),
                  DropdownMenuItem(
                    value: ReminderScheduleType.specificDate,
                    child: Text(_text(context, 'Jadwal per tanggal', 'One-time date')),
                  ),
                ],
                onChanged: _checkingPermission
                    ? null
                    : (ReminderScheduleType? value) {
                        if (value != null) {
                          setState(() {
                            _scheduleType = value;
                            _validationMessage = null;
                          });
                        }
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _activity,
                decoration: InputDecoration(
                  labelText: _text(context, 'Aktivitas', 'Activity'),
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'Lari',
                    child: Text(_text(context, 'Lari biasa', 'Run')),
                  ),
                  DropdownMenuItem(
                    value: 'Lari interval',
                    child: Text(_text(context, 'Lari interval', 'Interval run')),
                  ),
                  DropdownMenuItem(
                    value: 'Jalan',
                    child: Text(_text(context, 'Berjalan', 'Walk')),
                  ),
                  DropdownMenuItem(
                    value: 'Bersepeda',
                    child: Text(_text(context, 'Bersepeda', 'Cycling')),
                  ),
                  const DropdownMenuItem<String>(
                    value: 'HIIT',
                    child: Text('HIIT'),
                  ),
                  DropdownMenuItem(
                    value: 'Pemeriksaan motor',
                    child: Text(_text(
                      context,
                      'Pemeriksaan motor',
                      'Motorcycle inspection',
                    )),
                  ),
                  if (_activity == 'Lainnya')
                    DropdownMenuItem(
                      value: 'Lainnya',
                      child: Text(_text(context, 'Lainnya (lama)', 'Other (legacy)')),
                    ),
                ],
                onChanged: _checkingPermission
                    ? null
                    : (String? value) {
                        if (value != null) setState(() => _activity = value);
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _activityNameController,
                enabled: !_checkingPermission,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: _text(context, 'Nama aktivitas (opsional)', 'Activity name (optional)'),
                  hintText: _text(context, 'Contoh: Lari pagi', 'Example: Morning run'),
                ),
              ),
              const SizedBox(height: 12),
              if (_scheduleType == ReminderScheduleType.routine) ...<Widget>[
                Text(_text(context, 'Hari', 'Days')),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: List<Widget>.generate(_dayNumbers.length, (int index) {
                    final int day = _dayNumbers[index];
                    final bool selected = _selectedDays.contains(day);
                    return FilterChip(
                      label: Text(dayLabels[index]),
                      selected: selected,
                      onSelected: _checkingPermission
                          ? null
                          : (bool value) {
                              setState(() {
                                if (value) {
                                  _selectedDays.add(day);
                                } else {
                                  _selectedDays.remove(day);
                                }
                                _validationMessage = null;
                              });
                            },
                    );
                  }),
                ),
              ] else ...<Widget>[
                OutlinedButton(
                  onPressed: _checkingPermission ? null : _chooseDate,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_text(context, 'Tanggal', 'Date')),
                      Text('${_specificDate.day} ${_monthNameForEditor(_specificDate.month, english)} ${_specificDate.year}'),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _checkingPermission ? null : _chooseTime,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(_text(context, 'Waktu', 'Time')),
                    Text(_time.format(context)),
                  ],
                ),
              ),
              if (_activity != 'Pemeriksaan motor') ...<Widget>[
                const SizedBox(height: 10),
                TextField(
                  controller: _durationController,
                  enabled: !_checkingPermission,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _text(
                      context,
                      'Target durasi aktivitas (menit)',
                      'Activity duration target (min)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _repeatIntervalController,
                enabled: !_checkingPermission,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _text(context, 'Ulangi notifikasi setiap (detik)', 'Repeat notification every (sec)'),
                  hintText: '60',
                ),
              ),
              if (_validationMessage != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _validationMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _checkingPermission
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(_text(context, 'Batal', 'Cancel')),
        ),
        FilledButton(
          onPressed: _checkingPermission ? null : _save,
          child: _checkingPermission
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_text(context, 'Simpan', 'Save')),
        ),
      ],
    );
  }
}
