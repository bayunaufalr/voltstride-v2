// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

import '../../services/app_language_service.dart';

/// notificationAndAlarm dipertahankan hanya untuk membaca data versi lama.
/// Semua jadwal baru dan jadwal lama sekarang menggunakan notifikasi biasa.
enum ReminderStyle { notificationOnly }

class TrainingReminder {
  const TrainingReminder({
    required this.id,
    required this.activity,
    required this.weekdays,
    required this.hour,
    required this.minute,
    required this.durationMinutes,
    required this.style,
    required this.sound,
    this.completedDates = const <String>[],
  });

  final int id;
  final String activity;
  final List<int> weekdays;
  final int hour;
  final int minute;
  final int durationMinutes;
  final ReminderStyle style;
  final String sound;
  final List<String> completedDates;

  TrainingReminder copyWith({List<String>? completedDates}) => TrainingReminder(
        id: id,
        activity: activity,
        weekdays: weekdays,
        hour: hour,
        minute: minute,
        durationMinutes: durationMinutes,
        style: ReminderStyle.notificationOnly,
        sound: 'lembut',
        completedDates: completedDates ?? this.completedDates,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'activity': activity,
        'weekdays': weekdays,
        'hour': hour,
        'minute': minute,
        'durationMinutes': durationMinutes,
        'style': ReminderStyle.notificationOnly.name,
        'sound': 'lembut',
        'completedDates': completedDates,
      };

  factory TrainingReminder.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawDays = json['weekdays'] as List<dynamic>? ??
        <dynamic>[DateTime.monday, DateTime.wednesday, DateTime.friday];
    final String savedActivity = json['activity'] as String? ?? 'Lari';
    final String normalizedActivity =
        savedActivity.toLowerCase().contains('strength') ||
                savedActivity.toLowerCase().contains('kekuatan')
            ? 'Lari'
            : savedActivity;
    return TrainingReminder(
      id: (json['id'] as num).toInt(),
      activity: normalizedActivity,
      weekdays: rawDays.map((dynamic day) => (day as num).toInt()).toList(),
      hour: (json['hour'] as num?)?.toInt() ?? 7,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: (json['completedDates'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get daysText {
    const List<String> labels = <String>[
      'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min',
    ];
    final List<int> sorted = weekdays.toList()..sort();
    return sorted.map((int day) => labels[day - 1]).join(', ');
  }
}

/// Penyimpanan jadwal lokal dan penjadwalan notifikasi Android standar.
class ReminderService {
  ReminderService._();

  static const String _storageKey = 'voltstride_training_reminders_v1';
  static const String _zoneName = 'Asia/Jakarta';
  static const MethodChannel _settingsChannel =
      MethodChannel('voltstride/android_settings');
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void>? _initialization;

  static bool get _english =>
      AppLanguageService.localeNotifier.value.languageCode == 'en';

  static Future<void> initialize() {
    if (_ready) return Future<void>.value();
    return _initialization ??= _initializePlugin();
  }

  static Future<void> _initializePlugin() async {
    try {
      timezone_data.initializeTimeZones();
      timezone.setLocalLocation(timezone.getLocation(_zoneName));
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );
      _ready = true;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  static void _onNotificationResponse(NotificationResponse response) {
    if (response.actionId != 'mark_completed') return;
    final String? payload = response.payload;
    if (payload == null) return;
    final RegExpMatch? match =
        RegExp(r'^voltstride-reminder-(\d+)$').firstMatch(payload);
    if (match == null) return;
    final int? reminderId = int.tryParse(match.group(1)!);
    if (reminderId != null) unawaited(_markCurrentOccurrenceCompleted(reminderId));
  }

  static Future<void> _markCurrentOccurrenceCompleted(int reminderId) async {
    final timezone.TZDateTime now = timezone.TZDateTime.now(timezone.local);
    final String dateKey = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    await setOccurrenceCompleted(
      reminderId: reminderId,
      dateKey: dateKey,
      completed: true,
    );
  }

  static Future<List<TrainingReminder>> getAll() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final String? jsonText = preferences.getString(_storageKey);
    if (jsonText == null || jsonText.isEmpty) return <TrainingReminder>[];
    try {
      final List<dynamic> values = jsonDecode(jsonText) as List<dynamic>;
      return values
          .whereType<Map<String, dynamic>>()
          .map(TrainingReminder.fromJson)
          .toList(growable: false);
    } catch (_) {
      return <TrainingReminder>[];
    }
  }

  static Future<void> save(TrainingReminder reminder) async {
    final TrainingReminder notificationOnly = TrainingReminder(
      id: reminder.id,
      activity: reminder.activity,
      weekdays: reminder.weekdays.toList(growable: false),
      hour: reminder.hour,
      minute: reminder.minute,
      durationMinutes: reminder.durationMinutes,
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: reminder.completedDates.toList(growable: false),
    );
    final List<TrainingReminder> current = await getAll();
    final List<TrainingReminder> updated = <TrainingReminder>[
      ...current.where((TrainingReminder item) => item.id != reminder.id),
      notificationOnly,
    ]..sort((TrainingReminder a, TrainingReminder b) => a.hour != b.hour
        ? a.hour.compareTo(b.hour)
        : a.minute.compareTo(b.minute));

    // Jadwal disimpan dahulu. Gangguan notifikasi tidak boleh menghilangkan
    // jadwal yang sudah diisi pengguna.
    await _write(updated);
    await initialize();
    await _cancelReminderNotifications(reminder.id);

    final List<String> failures = <String>[];
    for (final int day in notificationOnly.weekdays.toSet()) {
      final int notificationId = _notificationId(notificationOnly.id, day);
      try {
        await _plugin.zonedSchedule(
          notificationId,
          _notificationTitle(notificationOnly),
          _notificationBody(notificationOnly),
          _nextDate(
            weekday: day,
            hour: notificationOnly.hour,
            minute: notificationOnly.minute,
          ),
          _details(),
          payload: 'voltstride-reminder-${notificationOnly.id}',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      } catch (error) {
        failures.add('Hari $day: $error');
      }
    }

    if (failures.isNotEmpty) {
      throw StateError(
        'Jadwal tersimpan, tetapi notifikasi belum berhasil dijadwalkan: '
        '${failures.join('; ')}',
      );
    }
  }

  static Future<void> delete(TrainingReminder reminder) async {
    final List<TrainingReminder> updated = List<TrainingReminder>.of(
      await getAll(),
      growable: true,
    );
    updated.removeWhere((TrainingReminder item) => item.id == reminder.id);
    await _write(updated);
    try {
      await initialize();
      await _cancelReminderNotifications(reminder.id);
    } catch (_) {
      // Jadwal lokal sudah dihapus meskipun pembatalan notifikasi gagal.
    }
  }

  static Future<void> setOccurrenceCompleted({
    required int reminderId,
    required String dateKey,
    required bool completed,
  }) async {
    final List<TrainingReminder> reminders = await getAll();
    final List<TrainingReminder> updated = reminders
        .map((TrainingReminder item) {
          if (item.id != reminderId) return item;
          final Set<String> dates = item.completedDates.toSet();
          if (completed) {
            dates.add(dateKey);
          } else {
            dates.remove(dateKey);
          }
          return item.copyWith(completedDates: dates.toList()..sort());
        })
        .toList(growable: false);
    await _write(updated);
  }

  static Future<void> restoreSavedSchedules() async {
    await initialize();
    final List<TrainingReminder> saved = await getAll();
    for (final TrainingReminder reminder in saved) {
      // Batalkan notifikasi lama sebelum mendaftarkan jadwal standar lagi.
      await _cancelReminderNotifications(reminder.id);
      for (final int day in reminder.weekdays.toSet()) {
        try {
          await _plugin.zonedSchedule(
            _notificationId(reminder.id, day),
            _notificationTitle(reminder),
            _notificationBody(reminder),
            _nextDate(
              weekday: day,
              hour: reminder.hour,
              minute: reminder.minute,
            ),
            _details(),
            payload: 'voltstride-reminder-${reminder.id}',
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        } catch (_) {
          // Jadwal lain tetap dipulihkan walau satu notifikasi gagal.
        }
      }
    }
  }

  static Future<bool> requestNotificationPermission() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    bool? allowed = await android.areNotificationsEnabled();
    if (allowed == true) return true;
    await android.requestNotificationsPermission();
    allowed = await android.areNotificationsEnabled();
    if (allowed != true) {
      await openAppSettings();
      allowed = await android.areNotificationsEnabled();
    }
    return allowed == true;
  }

  static Future<bool> areNotificationsEnabled() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() == true;
  }

  static Future<void> openAppSettings() async {
    try {
      await _settingsChannel.invokeMethod<void>('openNotificationSettings');
    } on PlatformException {
      await permissions.openAppSettings();
    } on MissingPluginException {
      await permissions.openAppSettings();
    }
  }

  static String _notificationTitle(TrainingReminder reminder) {
    final String activity = _activityName(reminder.activity);
    return _english ? 'Scheduled $activity' : 'Jadwal $activity';
  }

  static String _activityName(String activity) {
    final String value = activity.toLowerCase();
    if (value.contains('interval')) return _english ? 'interval run' : 'lari interval';
    if (value.contains('jalan') || value.contains('walk')) return _english ? 'walk' : 'jalan';
    if (value.contains('lari') || value.contains('run')) return _english ? 'run' : 'lari';
    return activity.toLowerCase();
  }

  static String _notificationBody(TrainingReminder reminder) => _english
      ? 'Scheduled duration: ${reminder.durationMinutes} minutes.'
      : 'Durasi latihan terjadwal: ${reminder.durationMinutes} menit.';

  static NotificationDetails _details() {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'voltstride_notice_priority_v6',
      _english ? 'Training reminders' : 'Pengingat latihan',
      channelDescription: _english
          ? 'High-priority training reminders with sound and vibration.'
          : 'Pengingat latihan berprioritas tinggi dengan suara dan getaran.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'mark_completed',
          _english ? 'Done' : 'Selesai',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );
    return NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );
  }

  static int _notificationId(int reminderId, int weekday) =>
      (reminderId * 10) + weekday;

  static timezone.TZDateTime _nextDate({
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final timezone.TZDateTime now = timezone.TZDateTime.now(timezone.local);
    final int daysAhead = (weekday - now.weekday) % 7;
    timezone.TZDateTime candidate = timezone.TZDateTime(
      timezone.local,
      now.year,
      now.month,
      now.day + daysAhead,
      hour,
      minute,
    );
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 7));
    }
    return candidate;
  }

  static Future<void> _cancelReminderNotifications(int reminderId) async {
    for (int day = DateTime.monday; day <= DateTime.sunday; day++) {
      try {
        await _plugin.cancel(_notificationId(reminderId, day));
      } catch (_) {
        // Teruskan membatalkan notifikasi hari lain.
      }
    }
  }

  static Future<void> _write(List<TrainingReminder> reminders) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(reminders.map((TrainingReminder item) => item.toJson()).toList()),
    );
  }
}
