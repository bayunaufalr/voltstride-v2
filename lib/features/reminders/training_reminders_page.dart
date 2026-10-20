import 'dart:async';

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
    _categoryController = TabController(length: 2, vsync: this);
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Jadwal belum tersimpan. Periksa izin dan coba lagi.',
              'Schedule was not saved. Check permissions and try again.',
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
        ? _text('Belum ada latihan yang selesai minggu ini.',
            'No completed sessions this week.')
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
    final bool alarm = reminder.style == ReminderStyle.notificationAndAlarm;
    final String soundName = _soundName(reminder.sound);
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
                      reminder.activity,
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
                      alarm
                          ? '${_text('Notifikasi dan alarm', 'Notification and alarm')} · $soundName'
                          : _text('Notifikasi saja', 'Notification only'),
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

  String _soundName(String sound) {
    switch (sound) {
      case 'digital':
        return 'Digital';
      case 'denyut':
        return _text('Denyut', 'Pulse');
      default:
        return _text('Lembut', 'Gentle');
    }
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
            Tab(text: _text('Belum selesai', 'Upcoming')),
            Tab(text: _text('Selesai', 'Completed')),
          ],
        ),
        if (_saving) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: TabBarView(
            controller: _categoryController,
            children: <Widget>[
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

class _ReminderEditorState extends State<_ReminderEditor>
    with WidgetsBindingObserver {
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
  late String _activity;
  late TimeOfDay _time;
  late Set<int> _selectedDays;
  late ReminderStyle _style;
  late String _sound;
  String? _validationMessage;
  bool _checkingPermission = false;
  bool _waitingForAlarmSettings = false;
  bool _leftForAlarmSettings = false;
  bool _returnedFromAlarmSettings = false;

  String _text(BuildContext context, String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final TrainingReminder? old = widget.initial;
    _durationController = TextEditingController(
      text: (old?.durationMinutes ?? 30).toString(),
    );
    _activity = old?.activity ?? 'Lari';
    _time = TimeOfDay(hour: old?.hour ?? 7, minute: 0);
    _selectedDays = (old?.weekdays ?? <int>[
      DateTime.monday,
      DateTime.wednesday,
      DateTime.friday,
    ]).toSet();
    _style = old?.style ?? ReminderStyle.notificationAndAlarm;
    _sound = old?.sound ?? 'lembut';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_waitingForAlarmSettings) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _leftForAlarmSettings = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _leftForAlarmSettings) {
      _returnedFromAlarmSettings = true;
      if (!_checkingPermission) {
        unawaited(_saveAfterAlarmPermissionReturn());
      }
    }
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

    setState(() {
      _checkingPermission = true;
      _validationMessage = null;
    });

    try {
      // Izin notifikasi bisa diminta lewat dialog Android dari aplikasi.
      final bool notificationsAllowed =
          await ReminderService.requestNotificationPermission();
      if (!mounted) return;
      if (!notificationsAllowed) {
        setState(() {
          _validationMessage = _text(
            context,
            'Izinkan notifikasi VoltStride agar pengingat bisa disimpan.',
            'Allow VoltStride notifications to save this reminder.',
          );
        });
        return;
      }

      if (_style == ReminderStyle.notificationAndAlarm &&
          !await ReminderService.isExactAlarmPermissionGranted()) {
        // Android membuka Setelan khusus alarm. Formulir dipertahankan dan
        // izin akan diperiksa lagi otomatis saat pengguna kembali.
        _waitingForAlarmSettings = true;
        _leftForAlarmSettings = false;
        _returnedFromAlarmSettings = false;
        await ReminderService.openExactAlarmSettings();
        if (!mounted) return;

        final bool alarmAllowed =
            await ReminderService.isExactAlarmPermissionGranted();
        if (!alarmAllowed) {
          setState(() {
            _validationMessage = _text(
              context,
              'Aktifkan izin alarm di Setelan Android. Saat kembali ke VoltStride, izin akan diperiksa otomatis.',
              'Enable alarm permission in Android settings. VoltStride will check it when you return.',
            );
          });
          return;
        }
      }

      _waitingForAlarmSettings = false;
      _returnedFromAlarmSettings = false;
      _closeWithReminder(duration);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _validationMessage = _text(
          context,
          'Izin belum berhasil diperiksa. Coba tekan Simpan lagi.',
          'Could not verify permissions. Try tapping Save again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() => _checkingPermission = false);
        if (_waitingForAlarmSettings && _returnedFromAlarmSettings) {
          unawaited(_saveAfterAlarmPermissionReturn());
        }
      }
    }
  }

  Future<void> _saveAfterAlarmPermissionReturn() async {
    if (!mounted ||
        !_waitingForAlarmSettings ||
        !_returnedFromAlarmSettings ||
        _checkingPermission) {
      return;
    }

    setState(() => _checkingPermission = true);
    try {
      // Tunggu sebentar agar Android selesai memperbarui status izin.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final bool allowed =
          await ReminderService.areRequiredPermissionsGranted(_style);
      if (!mounted) return;

      if (allowed) {
        final int? duration = int.tryParse(_durationController.text.trim());
        if (duration == null || duration < 5 || duration > 360) {
          _waitingForAlarmSettings = false;
          _returnedFromAlarmSettings = false;
          setState(() {
            _validationMessage = _text(
              context,
              'Periksa kembali durasi latihan.',
              'Check the workout duration.',
            );
          });
          return;
        }

        _waitingForAlarmSettings = false;
        _returnedFromAlarmSettings = false;
        _closeWithReminder(duration);
        return;
      }

      _waitingForAlarmSettings = false;
      _returnedFromAlarmSettings = false;
      setState(() {
        _validationMessage = _text(
          context,
          'Izin alarm belum aktif. Aktifkan izin, lalu tekan Simpan lagi.',
          'Alarm permission is still off. Enable it, then tap Save again.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      _waitingForAlarmSettings = false;
      _returnedFromAlarmSettings = false;
      setState(() {
        _validationMessage = _text(
          context,
          'Status izin belum terbaca. Tekan Simpan untuk mencoba lagi.',
          'Permission status could not be read. Tap Save to try again.',
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
        weekdays: _selectedDays.toList()..sort(),
        hour: _time.hour,
        minute: _time.minute,
        durationMinutes: duration,
        style: _style,
        sound: _sound,
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
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem(value: 'Lari', child: Text('Lari')),
                  DropdownMenuItem(
                    value: 'Lari interval',
                    child: Text('Lari interval'),
                  ),
                  DropdownMenuItem(value: 'Jalan', child: Text('Jalan')), 
                  DropdownMenuItem(
                    value: 'Latihan kekuatan',
                    child: Text('Latihan kekuatan'),
                  ),
                ],
                onChanged: _checkingPermission
                    ? null
                    : (String? value) {
                        if (value != null) setState(() => _activity = value);
                      },
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
              const SizedBox(height: 14),
              Text(_text(context, 'Pengingat', 'Reminder')),
              RadioListTile<ReminderStyle>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_text(context, 'Notifikasi saja', 'Notification only')),
                value: ReminderStyle.notificationOnly,
                groupValue: _style,
                onChanged: _checkingPermission
                    ? null
                    : (ReminderStyle? value) {
                        if (value != null) setState(() => _style = value);
                      },
              ),
              RadioListTile<ReminderStyle>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(_text(context, 'Notifikasi dan alarm', 'Notification and alarm')),
                value: ReminderStyle.notificationAndAlarm,
                groupValue: _style,
                onChanged: _checkingPermission
                    ? null
                    : (ReminderStyle? value) {
                        if (value != null) setState(() => _style = value);
                      },
              ),
              if (_style == ReminderStyle.notificationAndAlarm) ...<Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _sound,
                  decoration: InputDecoration(
                    labelText: _text(context, 'Suara alarm', 'Alarm sound'),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'lembut', child: Text('Lembut')),
                    DropdownMenuItem(value: 'digital', child: Text('Digital')),
                    DropdownMenuItem(value: 'denyut', child: Text('Denyut')),
                  ],
                  onChanged: _checkingPermission
                      ? null
                      : (String? value) {
                          if (value != null) setState(() => _sound = value);
                        },
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: _checkingPermission
                      ? null
                      : () async {
                          try {
                            await ReminderService.previewSound(_sound);
                          } catch (_) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(_text(
                                  context,
                                  'Izin notifikasi belum aktif.',
                                  'Notification permission is not active.',
                                )),
                              ),
                            );
                          }
                        },
                  child: Text(_text(context, 'Coba suara', 'Preview sound')),
                ),
              ],
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
