// ignore_for_file: lines_longer_than_80_chars
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    this.activityName = '',
    this.repeatIntervalSeconds = 60,
    this.completedDates = const <String>[],
  });

  final int id;
  /// Kategori tersimpan sebagai nilai kompatibel dengan jadwal versi lama.
  final String activity;
  /// Nama khusus yang diberikan pengguna; kosong berarti memakai nama kategori.
  final String activityName;
  final List<int> weekdays;
  final int hour;
  final int minute;
  final int durationMinutes;
  final int repeatIntervalSeconds;
  final ReminderStyle style;
  final String sound;
  final List<String> completedDates;

  TrainingReminder copyWith({List<String>? completedDates}) => TrainingReminder(
        id: id,
        activity: activity,
        activityName: activityName,
        weekdays: weekdays,
        hour: hour,
        minute: minute,
        durationMinutes: durationMinutes,
        repeatIntervalSeconds: repeatIntervalSeconds,
        style: ReminderStyle.notificationOnly,
        sound: 'lembut',
        completedDates: completedDates ?? this.completedDates,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'activity': activity,
        'activityName': activityName,
        'weekdays': weekdays,
        'hour': hour,
        'minute': minute,
        'durationMinutes': durationMinutes,
        'repeatIntervalSeconds': repeatIntervalSeconds,
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
      activityName: (json['activityName'] as String? ?? '').trim(),
      weekdays: rawDays.map((dynamic day) => (day as num).toInt()).toList(),
      hour: (json['hour'] as num?)?.toInt() ?? 7,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
      repeatIntervalSeconds: ((json['repeatIntervalSeconds'] as num?)?.toInt() ?? 60).clamp(30, 600).toInt(),
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
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
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
    final TrainingReminder normalized = TrainingReminder(
      id: reminder.id,
      activity: reminder.activity,
      activityName: reminder.activityName.trim(),
      weekdays: reminder.weekdays.toSet().toList()..sort(),
      hour: reminder.hour,
      minute: reminder.minute,
      durationMinutes: reminder.durationMinutes,
      repeatIntervalSeconds: reminder.repeatIntervalSeconds.clamp(30, 600).toInt(),
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: reminder.completedDates.toList(growable: false),
    );
    final List<TrainingReminder> current = await getAll();
    final List<TrainingReminder> updated = <TrainingReminder>[
      ...current.where((TrainingReminder item) => item.id != reminder.id),
      normalized,
    ]..sort((TrainingReminder a, TrainingReminder b) => a.hour != b.hour
        ? a.hour.compareTo(b.hour)
        : a.minute.compareTo(b.minute));

    // Data jadwal selalu disimpan dulu sebelum mencoba menjadwalkan notifikasi.
    await _write(updated);
    await initialize();
    await _cancelLegacyNotifications(normalized.id);

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _scheduleNativeReminder(normalized);
      return;
    }

    // Cadangan untuk platform selain Android. Android memakai receiver native
    // agar notifikasi bisa berulang sepanjang durasi tanpa menumpuk ratusan alarm.
    for (final int day in normalized.weekdays.toSet()) {
      await _plugin.zonedSchedule(
        _notificationId(normalized.id, day),
        _notificationTitle(normalized),
        _notificationBody(normalized),
        _nextDate(
          weekday: day,
          hour: normalized.hour,
          minute: normalized.minute,
        ),
        _details(),
        payload: 'voltstride-reminder-${normalized.id}',
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  static Future<void> _scheduleNativeReminder(TrainingReminder reminder) async {
    final String category = _activityName(reminder.activity);
    final String title = reminder.activityName.isNotEmpty
        ? reminder.activityName
        : category;
    await _settingsChannel.invokeMethod<void>(
      'scheduleTrainingReminder',
      <String, Object?>{
        'id': reminder.id,
        'title': title,
        'category': category,
        'weekdays': reminder.weekdays,
        'hour': reminder.hour,
        'minute': reminder.minute,
        'durationMinutes': reminder.durationMinutes,
        'repeatIntervalSeconds': reminder.repeatIntervalSeconds,
        'doneLabel': _english ? 'Done' : 'Selesai',
        'bodyLabel': _english ? 'Training reminder' : 'Pengingat latihan',
      },
    );
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
      await _cancelLegacyNotifications(reminder.id);
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _settingsChannel.invokeMethod<void>(
          'cancelTrainingReminder',
          <String, Object?>{'id': reminder.id},
        );
      }
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
      await _cancelLegacyNotifications(reminder.id);
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await _scheduleNativeReminder(reminder);
        } else {
          for (final int day in reminder.weekdays.toSet()) {
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
          }
        }
      } catch (_) {
        // Pemulihan jadwal lain tetap berjalan jika satu jadwal gagal.
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
    final String activity = reminder.activityName.trim().isNotEmpty
        ? reminder.activityName.trim()
        : _activityName(reminder.activity);
    return _english ? 'VoltStride · $activity' : 'VoltStride · $activity';
  }

  static String _activityName(String activity) {
    final String value = activity.toLowerCase();
    if (value.contains('interval')) return _english ? 'interval run' : 'lari interval';
    if (value.contains('jalan') || value.contains('walk')) return _english ? 'Walk' : 'Jalan';
    if (value.contains('lain') || value.contains('other')) return _english ? 'Other' : 'Lainnya';
    if (value.contains('lari') || value.contains('run')) return _english ? 'Run' : 'Lari';
    return activity.toLowerCase();
  }

  static String _notificationBody(TrainingReminder reminder) => _english
      ? '${reminder.durationMinutes} min · repeats every ${reminder.repeatIntervalSeconds} sec until completed'
      : '${reminder.durationMinutes} menit · diulang setiap ${reminder.repeatIntervalSeconds} detik sampai selesai';

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

  static Future<void> _cancelLegacyNotifications(int reminderId) async {
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
