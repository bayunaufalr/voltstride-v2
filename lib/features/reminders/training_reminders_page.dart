import 'package:flutter/material.dart';

import 'reminder_service.dart';

class TrainingRemindersPage extends StatefulWidget {
  const TrainingRemindersPage({super.key});

  @override
  State<TrainingRemindersPage> createState() => _TrainingRemindersPageState();
}

class _TrainingRemindersPageState extends State<TrainingRemindersPage> {
  List<TrainingReminder> _reminders = <TrainingReminder>[];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

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

  Future<void> _addReminder() async => _editReminder();

  Future<void> _editReminder({TrainingReminder? reminder}) async {
    final int newId = reminder?.id ??
        (_reminders.fold<int>(0, (int highest, TrainingReminder item) =>
                item.id > highest ? item.id : highest) +
            1);
    final TrainingReminder? hasil = await showDialog<TrainingReminder>(
      context: context,
      builder: (BuildContext context) => _ReminderEditor(
        initial: reminder,
        newId: newId,
      ),
    );
    if (hasil == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ReminderService.save(hasil);
      await _loadReminders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jadwal latihan disimpan.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pesanKesalahan(error))),
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
        const SnackBar(content: Text('Jadwal belum berhasil dihapus.')),
      );
    }
  }

  String _pesanKesalahan(Object error) {
    final String message = error.toString();
    if (message.toLowerCase().contains('izin notifikasi')) {
      return 'Aktifkan izin notifikasi VoltStride di pengaturan HP.';
    }
    if (message.contains('Izinkan alarm terjadwal')) {
      return 'Izinkan alarm terjadwal untuk menjaga waktu pengingat.';
    }
    return 'Jadwal belum berhasil disimpan. Periksa izin notifikasi dan coba lagi.';
  }

  @override
  Widget build(BuildContext context) {
    final Color border = Theme.of(context).dividerColor;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengingat dan rencana latihan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : _addReminder,
        icon: const Icon(Icons.add),
        label: const Text('Tambah jadwal'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReminders,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: <Widget>[
                  const Text(
                    'Atur hari, waktu, durasi, dan cara pengingat latihan.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 14),
                  if (_saving) const LinearProgressIndicator(),
                  if (_reminders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        border: Border.all(color: border),
                      ),
                      child: const Text('Belum ada jadwal latihan.'),
                    ),
                  ..._reminders.map((TrainingReminder reminder) {
                    final bool alarm = reminder.style ==
                        ReminderStyle.notificationAndAlarm;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                        child: Row(
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
                                  const SizedBox(height: 5),
                                  Text('${reminder.daysText} • ${reminder.timeText}'),
                                  Text('${reminder.durationMinutes} menit'),
                                  const SizedBox(height: 5),
                                  Text(
                                    alarm
                                        ? 'Notifikasi dan alarm • ${_namaSuara(reminder.sound)}'
                                        : 'Notifikasi saja',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Pengaturan jadwal',
                              onSelected: (String action) {
                                if (action == 'edit') {
                                  _editReminder(reminder: reminder);
                                } else {
                                  _deleteReminder(reminder);
                                }
                              },
                              itemBuilder: (BuildContext context) =>
                                  const <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Ubah'),
                                ),
                                PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('Hapus'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }

  String _namaSuara(String sound) {
    switch (sound) {
      case 'digital':
        return 'Digital';
      case 'denyut':
        return 'Denyut';
      default:
        return 'Lembut';
    }
  }
}

class _ReminderEditor extends StatefulWidget {
  const _ReminderEditor({required this.newId, this.initial});

  final int newId;
  final TrainingReminder? initial;

  @override
  State<_ReminderEditor> createState() => _ReminderEditorState();
}

class _ReminderEditorState extends State<_ReminderEditor> {
  static const List<String> _dayLabels = <String>[
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
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

  @override
  void initState() {
    super.initState();
    final TrainingReminder? old = widget.initial;
    _durationController = TextEditingController(
      text: (old?.durationMinutes ?? 30).toString(),
    );
    _activity = old?.activity ?? 'Lari';
    _time = TimeOfDay(hour: old?.hour ?? 7, minute: old?.minute ?? 0);
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
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Pilih waktu latihan',
    );
    if (selected != null && mounted) setState(() => _time = selected);
  }

  void _save() {
    final int? duration = int.tryParse(_durationController.text.trim());
    if (_selectedDays.isEmpty) {
      setState(() => _validationMessage = 'Pilih setidaknya satu hari.');
      return;
    }
    if (duration == null || duration < 5 || duration > 360) {
      setState(() => _validationMessage = 'Durasi harus 5–360 menit.');
      return;
    }
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Tambah jadwal' : 'Ubah jadwal'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _activity,
                decoration: const InputDecoration(labelText: 'Aktivitas'),
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
                onChanged: (String? value) {
                  if (value != null) setState(() => _activity = value);
                },
              ),
              const SizedBox(height: 12),
              const Text('Hari'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: List<Widget>.generate(_dayNumbers.length, (int index) {
                  final int day = _dayNumbers[index];
                  final bool selected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(_dayLabels[index]),
                    selected: selected,
                    onSelected: (bool value) {
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
                onPressed: _chooseTime,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('Waktu'),
                    Text(_time.format(context)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Durasi (menit)',
                ),
              ),
              const SizedBox(height: 14),
              const Text('Cara mengingatkan'),
              RadioListTile<ReminderStyle>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Notifikasi saja'),
                value: ReminderStyle.notificationOnly,
                groupValue: _style,
                onChanged: (ReminderStyle? value) {
                  if (value != null) setState(() => _style = value);
                },
              ),
              RadioListTile<ReminderStyle>(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Notifikasi dan alarm'),
                value: ReminderStyle.notificationAndAlarm,
                groupValue: _style,
                onChanged: (ReminderStyle? value) {
                  if (value != null) setState(() => _style = value);
                },
              ),
              if (_style == ReminderStyle.notificationAndAlarm) ...<Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _sound,
                  decoration: const InputDecoration(labelText: 'Suara alarm'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'lembut', child: Text('Lembut')),
                    DropdownMenuItem(value: 'digital', child: Text('Digital')),
                    DropdownMenuItem(value: 'denyut', child: Text('Denyut')),
                  ],
                  onChanged: (String? value) {
                    if (value != null) setState(() => _sound = value);
                  },
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () async {
                    try {
                      await ReminderService.previewSound(_sound);
                    } catch (_) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Suara belum bisa diputar. Periksa izin notifikasi.',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('Coba suara'),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}
