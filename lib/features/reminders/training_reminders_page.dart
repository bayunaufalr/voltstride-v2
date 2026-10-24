// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'package:flutter/material.dart';

import '../../services/app_language_service.dart';
import 'reminder_service.dart';

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
  bool _loading = true;
  bool _saving = false;
  late final TabController _categoryController;

  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  void initState() {
    super.initState();
    _categoryController = TabController(length: 3, vsync: this);
    _loadReminders();
  }

  @override
  void dispose() {
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> reload() => _loadReminders();

  Future<void> _loadReminders() async {
    try {
      final List<TrainingReminder> saved = await ReminderService.getAll();
      if (!mounted) return;
      setState(() {
        _reminders = saved;
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

  Future<void> _setCompleted(
    _ReminderOccurrence occurrence, {
    required bool completed,
  }) async {
    try {
      await ReminderService.setOccurrenceCompleted(
        reminderId: occurrence.reminder.id,
        dateKey: occurrence.dateKey,
        completed: completed,
      );
      await _loadReminders();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Perubahan belum tersimpan.', 'Change was not saved.'),
          ),
        ),
      );
    }
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
            'Belum ada jadwal rutin. Tambahkan jadwal latihan pertama.',
            'No routine schedules yet. Add your first workout schedule.',
          )),
        ),
      );
    }
    final List<TrainingReminder> sorted = List<TrainingReminder>.of(_reminders)
      ..sort((TrainingReminder a, TrainingReminder b) {
        final int byTime = a.hour.compareTo(b.hour);
        return byTime != 0 ? byTime : a.minute.compareTo(b.minute);
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
                  '${_scheduleDaysText(reminder)} · ${reminder.timeText}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 3),
                Text(
                  '${reminder.durationMinutes} ${_text('menit', 'min')} · '
                  '${_text('Notifikasi', 'Notification')}',
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
        if (!reminder.weekdays.contains(day.weekday)) continue;
        result.add(_ReminderOccurrence(reminder: reminder, date: day));
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

  Widget _categoryList({required bool completed}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<_ReminderOccurrence> items = completed
        ? _completedOccurrences()
        : _occurrencesForThisWeek()
            .where((_ReminderOccurrence item) => !item.completed)
            .toList(growable: false);

    final String emptyMessage = completed
        ? _text('Belum ada latihan yang ditandai selesai.',
            'No completed sessions yet.')
        : _text('Tidak ada jadwal yang belum selesai.',
            'No unfinished sessions.');

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
    final Color border = Theme.of(context).dividerColor;
    final String days = _weekdayName(occurrence.date.weekday);
    final String dateText = '$days, ${occurrence.date.day} '
        '${_monthName(occurrence.date.month)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _reminderTitle(reminder),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('$dateText · ${reminder.timeText}'),
                    Text(
                      '${reminder.durationMinutes} '
                      '${_text('menit', 'min')}',
                    ),
                    Text(
                      _text('Notifikasi terjadwal', 'Scheduled notification'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  } else {
                    _deleteReminder(reminder);
                  }
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
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
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(border: Border.all(color: border)),
                child: Text(
                  occurrence.completed
                      ? _text('Selesai', 'Completed')
                      : _text('Belum selesai', 'Not completed'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (occurrence.completed)
                TextButton(
                  onPressed: () => _setCompleted(occurrence, completed: false),
                  child: Text(_text('Batalkan', 'Undo')),
                )
              else
                FilledButton.tonal(
                  onPressed: () => _setCompleted(occurrence, completed: true),
                  child: Text(_text('Tandai selesai', 'Mark complete')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _reminderTitle(TrainingReminder reminder) {
    final String name = reminder.activityName.trim();
    return name.isNotEmpty ? name : _activityName(reminder.activity);
  }

  String _activityName(String activity) {
    final String value = activity.toLowerCase();
    final bool english = Localizations.localeOf(context).languageCode == 'en';
    if (value.contains('interval')) {
      return english ? 'Interval run' : 'Lari interval';
    }
    if (value.contains('walk') || value.contains('jalan')) {
      return english ? 'Walk' : 'Jalan';
    }
    if (value.contains('run') || value.contains('lari')) {
      return english ? 'Run' : 'Lari';
    }
    if (value.contains('other') || value.contains('lain')) {
      return english ? 'Other' : 'Lainnya';
    }
    return activity;
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


  @override
  Widget build(BuildContext context) {
    final Widget isi = Column(
      children: <Widget>[
        TabBar(
          controller: _categoryController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            Tab(text: _text('Jadwal rutin', 'Routine schedules')),
            Tab(text: _text('Minggu ini', 'This week')),
            Tab(text: _text('Selesai', 'Completed')),
          ],
        ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _categoryController,
            children: <Widget>[
              _routineScheduleList(),
              _categoryList(completed: false),
              _categoryList(completed: true),
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
    _activity = normalized.contains('jalan') || normalized.contains('walk')
        ? 'Jalan'
        : normalized.contains('lain') || normalized.contains('other')
            ? 'Lainnya'
            : 'Lari';
    _time = TimeOfDay(hour: old?.hour ?? 7, minute: old?.minute ?? 0);
    _selectedDays = (old?.weekdays ?? <int>[
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

  Future<void> _save() async {
    final int? duration = int.tryParse(_durationController.text.trim());
    if (_selectedDays.isEmpty) {
      setState(() {
        _validationMessage = _text(
          context,
          'Pilih setidaknya satu hari.',
          'Choose at least one day.',
        );
      });
      return;
    }
    if (duration == null || duration < 5 || duration > 360) {
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
      _closeWithReminder(duration);
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
        weekdays: _selectedDays.toList()..sort(),
        hour: _time.hour,
        minute: _time.minute,
        durationMinutes: duration,
        repeatIntervalSeconds: int.parse(_repeatIntervalController.text.trim()),
        style: ReminderStyle.notificationOnly,
        sound: 'lembut',
        completedDates: widget.initial?.completedDates ?? const <String>[],
      ),
    );
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
              DropdownButtonFormField<String>(
                initialValue: _activity,
                decoration: InputDecoration(
                  labelText: _text(context, 'Aktivitas', 'Activity'),
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: 'Lari',
                    child: Text(_text(context, 'Lari', 'Run')),
                  ),
                  DropdownMenuItem(
                    value: 'Jalan',
                    child: Text(_text(context, 'Jalan', 'Walk')),
                  ),
                  DropdownMenuItem(
                    value: 'Lainnya',
                    child: Text(_text(context, 'Lainnya', 'Other')),
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
              const SizedBox(height: 10),
              TextField(
                controller: _durationController,
                enabled: !_checkingPermission,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _text(context, 'Durasi (menit)', 'Duration (min)'),
                ),
              ),
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
