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

String _reminderDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime? _parseReminderDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final DateTime? parsed = DateTime.tryParse(value);
  return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
}

/// notificationAndAlarm dipertahankan hanya untuk membaca data versi lama.
/// Semua jadwal baru dan jadwal lama sekarang menggunakan notifikasi biasa.
enum ReminderStyle { notificationOnly }
enum ReminderScheduleType { routine, specificDate }

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
    this.scheduleType = ReminderScheduleType.routine,
    this.specificDate,
    this.completedDates = const <String>[],
    this.notCompletedDates = const <String>[],
    this.notCompletedReasons = const <String, String>{},
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
  final ReminderScheduleType scheduleType;
  final DateTime? specificDate;
  final ReminderStyle style;
  final String sound;
  final List<String> completedDates;
  final List<String> notCompletedDates;
  final Map<String, String> notCompletedReasons;

  TrainingReminder copyWith({
    List<String>? completedDates,
    List<String>? notCompletedDates,
    Map<String, String>? notCompletedReasons,
  }) => TrainingReminder(
        id: id,
        activity: activity,
        activityName: activityName,
        weekdays: weekdays,
        hour: hour,
        minute: minute,
        durationMinutes: durationMinutes,
        repeatIntervalSeconds: repeatIntervalSeconds,
        scheduleType: scheduleType,
        specificDate: specificDate,
        style: ReminderStyle.notificationOnly,
        sound: 'lembut',
        completedDates: completedDates ?? this.completedDates,
        notCompletedDates: notCompletedDates ?? this.notCompletedDates,
        notCompletedReasons: notCompletedReasons ?? this.notCompletedReasons,
      );

  Map<String, Object?> toJson() {
    final DateTime? date = specificDate;
    return <String, Object?>{
      'id': id,
      'activity': activity,
      'activityName': activityName,
      'weekdays': weekdays,
      'hour': hour,
      'minute': minute,
      'durationMinutes': durationMinutes,
      'repeatIntervalSeconds': repeatIntervalSeconds,
      'scheduleType': scheduleType.name,
      'specificDate': date == null ? null : _reminderDateKey(date),
      'style': ReminderStyle.notificationOnly.name,
      'sound': 'lembut',
      'completedDates': completedDates,
      'notCompletedDates': notCompletedDates,
      'notCompletedReasons': notCompletedReasons,
    };
  }

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
      scheduleType: json['scheduleType'] == ReminderScheduleType.specificDate.name
          ? ReminderScheduleType.specificDate
          : ReminderScheduleType.routine,
      specificDate: _parseReminderDate(json['specificDate']),
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: (json['completedDates'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
      notCompletedDates:
          (json['notCompletedDates'] as List<dynamic>? ?? <dynamic>[])
              .whereType<String>()
              .toList(growable: false),
      notCompletedReasons: _decodeReasons(json['notCompletedReasons']),
    );
  }

  static Map<String, String> _decodeReasons(Object? value) {
    if (value is! Map) return const <String, String>{};
    return value.map<String, String>(
      (dynamic key, dynamic reason) => MapEntry<String, String>(
        key.toString(),
        reason.toString(),
      ),
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
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
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
    final DateTime? suppliedDate = reminder.specificDate;
    final TrainingReminder normalized = TrainingReminder(
      id: reminder.id,
      activity: reminder.activity,
      activityName: reminder.activityName.trim(),
      weekdays: reminder.scheduleType == ReminderScheduleType.routine
          ? (reminder.weekdays.toSet().toList()..sort())
          : const <int>[],
      hour: reminder.hour,
      minute: reminder.minute,
      durationMinutes: reminder.durationMinutes,
      repeatIntervalSeconds: reminder.repeatIntervalSeconds.clamp(30, 600).toInt(),
      scheduleType: reminder.scheduleType,
      specificDate: suppliedDate == null
          ? null
          : DateTime(suppliedDate.year, suppliedDate.month, suppliedDate.day),
      style: ReminderStyle.notificationOnly,
      sound: 'lembut',
      completedDates: reminder.completedDates.toList(growable: false),
      notCompletedDates: reminder.notCompletedDates.toList(growable: false),
      notCompletedReasons: Map<String, String>.of(reminder.notCompletedReasons),
    );
    if (normalized.scheduleType == ReminderScheduleType.routine &&
        normalized.weekdays.isEmpty) {
      throw ArgumentError('Pilih setidaknya satu hari.');
    }
    if (normalized.scheduleType == ReminderScheduleType.specificDate &&
        normalized.specificDate == null) {
      throw ArgumentError('Pilih tanggal jadwal.');
    }
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

    // Cadangan untuk platform selain Android.
    if (normalized.scheduleType == ReminderScheduleType.specificDate) {
      final DateTime? date = normalized.specificDate;
      if (date == null) return;
      final timezone.TZDateTime scheduled = timezone.TZDateTime(
        timezone.local, date.year, date.month, date.day,
        normalized.hour, normalized.minute,
      );
      if (scheduled.isAfter(timezone.TZDateTime.now(timezone.local))) {
        await _plugin.zonedSchedule(
          _notificationId(normalized.id, date.day),
          _notificationTitle(normalized), _notificationBody(normalized),
          scheduled, _details(),
          payload: 'voltstride-reminder-${normalized.id}',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } else {
      for (final int day in normalized.weekdays.toSet()) {
        await _plugin.zonedSchedule(
          _notificationId(normalized.id, day),
          _notificationTitle(normalized), _notificationBody(normalized),
          _nextDate(weekday: day, hour: normalized.hour, minute: normalized.minute),
          _details(),
          payload: 'voltstride-reminder-${normalized.id}',
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  static Future<void> _scheduleNativeReminder(TrainingReminder reminder) async {
    final String category = _activityName(reminder.activity);
    final String title = reminder.activityName.isNotEmpty
        ? reminder.activityName
        : category;
    final DateTime? scheduledDate = reminder.specificDate;
    await _settingsChannel.invokeMethod<void>(
      'scheduleTrainingReminder',
      <String, Object?>{
        'id': reminder.id,
        'title': title,
        'category': category,
        'weekdays': reminder.weekdays,
        'scheduleType': reminder.scheduleType.name,
        'specificDate': scheduledDate == null ? null : _dateKey(scheduledDate),
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
          final Set<String> completedDates = item.completedDates.toSet();
          final Set<String> missedDates = item.notCompletedDates.toSet();
          final Map<String, String> reasons =
              Map<String, String>.of(item.notCompletedReasons);
          if (completed) {
            completedDates.add(dateKey);
            missedDates.remove(dateKey);
            reasons.remove(dateKey);
          } else {
            completedDates.remove(dateKey);
          }
          return item.copyWith(
            completedDates: completedDates.toList()..sort(),
            notCompletedDates: missedDates.toList()..sort(),
            notCompletedReasons: reasons,
          );
        })
        .toList(growable: false);
    await _write(updated);
    if (completed && defaultTargetPlatform == TargetPlatform.android) {
      await _settingsChannel.invokeMethod<void>(
        'completeTrainingReminder',
        <String, Object?>{'id': reminderId, 'dateKey': dateKey},
      );
    }
  }

  static Future<void> setOccurrenceNotCompleted({
    required int reminderId,
    required String dateKey,
    required String reason,
  }) async {
    final String trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be empty.');
    }
    final List<TrainingReminder> reminders = await getAll();
    final List<TrainingReminder> updated = reminders
        .map((TrainingReminder item) {
          if (item.id != reminderId) return item;
          final Set<String> completedDates = item.completedDates.toSet()
            ..remove(dateKey);
          final Set<String> missedDates = item.notCompletedDates.toSet()
            ..add(dateKey);
          final Map<String, String> reasons =
              Map<String, String>.of(item.notCompletedReasons)
                ..[dateKey] = trimmedReason;
          return item.copyWith(
            completedDates: completedDates.toList()..sort(),
            notCompletedDates: missedDates.toList()..sort(),
            notCompletedReasons: reasons,
          );
        })
        .toList(growable: false);
    await _write(updated);
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _settingsChannel.invokeMethod<void>(
        'dismissTrainingReminder',
        <String, Object?>{'id': reminderId, 'dateKey': dateKey},
      );
    }
  }

  static Future<void> restoreSavedSchedules() async {
    await initialize();
    final List<TrainingReminder> saved = await getAll();
    for (final TrainingReminder reminder in saved) {
      await _cancelLegacyNotifications(reminder.id);
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          await _scheduleNativeReminder(reminder);
        } else if (reminder.scheduleType == ReminderScheduleType.specificDate) {
          final DateTime? date = reminder.specificDate;
          if (date == null) continue;
          final timezone.TZDateTime scheduled = timezone.TZDateTime(
            timezone.local, date.year, date.month, date.day,
            reminder.hour, reminder.minute,
          );
          if (scheduled.isAfter(timezone.TZDateTime.now(timezone.local))) {
            await _plugin.zonedSchedule(
              _notificationId(reminder.id, date.day),
              _notificationTitle(reminder), _notificationBody(reminder),
              scheduled, _details(),
              payload: 'voltstride-reminder-${reminder.id}',
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            );
          }
        } else {
          for (final int day in reminder.weekdays.toSet()) {
            await _plugin.zonedSchedule(
              _notificationId(reminder.id, day),
              _notificationTitle(reminder), _notificationBody(reminder),
              _nextDate(weekday: day, hour: reminder.hour, minute: reminder.minute),
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

  /// Memeriksa hari/tanggal latihan tanpa membandingkan jam yang dipilih.
  static bool matchesScheduledDate(TrainingReminder reminder, DateTime date) {
    final DateTime localDate = date.toLocal();
    final DateTime? scheduledDate = reminder.specificDate;
    if (reminder.scheduleType == ReminderScheduleType.specificDate) {
      return scheduledDate != null &&
          scheduledDate.year == localDate.year &&
          scheduledDate.month == localDate.month &&
          scheduledDate.day == localDate.day;
    }
    return reminder.weekdays.contains(localDate.weekday);
  }

  /// Lari dan jalan dicocokkan dengan jenis aktivitas yang direkam.
  /// Lainnya menerima sesi aktivitas yang valid karena tidak ada tipe ketiga
  /// di perekam saat ini.
  static bool matchesActivityCategory(
    TrainingReminder reminder,
    String activityCategory,
  ) {
    final String planned = reminder.activity.toLowerCase();
    final String actual = activityCategory.toLowerCase();
    if (planned.contains('lari') || planned.contains('run')) {
      return actual == 'run';
    }
    if (planned.contains('jalan') || planned.contains('walk')) {
      return actual == 'walk';
    }
    return (planned.contains('lain') || planned.contains('other')) &&
        actual.isNotEmpty;
  }

  /// Menyelesaikan jadwal yang cocok ketika aktivitas memenuhi durasi.
  /// Jam jadwal tidak diperbandingkan; cukup cocok tanggal, kategori, dan durasi.
  static Future<int> completeMatchingActivity({
    required DateTime startedAt,
    required Duration duration,
    required String activityCategory,
  }) async {
    if (duration.inSeconds <= 0) return 0;
    final DateTime localStart = startedAt.toLocal();
    final String dateKey = _dateKey(localStart);
    final List<TrainingReminder> current = await getAll();
    final Set<int> matchedIds = <int>{};

    final List<TrainingReminder> updated = current.map((TrainingReminder item) {
      if (!matchesScheduledDate(item, localStart) ||
          duration < Duration(minutes: item.durationMinutes)) {
        return item;
      }
      if (!matchesActivityCategory(item, activityCategory) ||
          item.completedDates.contains(dateKey)) {
        return item;
      }

      matchedIds.add(item.id);
      final Set<String> completed = item.completedDates.toSet()..add(dateKey);
      final Set<String> missed = item.notCompletedDates.toSet()..remove(dateKey);
      final Map<String, String> reasons =
          Map<String, String>.of(item.notCompletedReasons)..remove(dateKey);
      return item.copyWith(
        completedDates: completed.toList()..sort(),
        notCompletedDates: missed.toList()..sort(),
        notCompletedReasons: reasons,
      );
    }).toList(growable: false);

    if (matchedIds.isEmpty) return 0;
    await _write(updated);
    if (defaultTargetPlatform == TargetPlatform.android) {
      for (final int id in matchedIds) {
        try {
          await _settingsChannel.invokeMethod<void>(
            'completeTrainingReminder',
            <String, Object?>{'id': id, 'dateKey': dateKey},
          );
        } on PlatformException {
          // Status selesai tetap tersimpan lokal bila kanal Android gagal.
        } on MissingPluginException {
          // Platform lain tidak memiliki kanal native ini.
        }
      }
    }
    return matchedIds.length;
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
    // Jadwal per tanggal menggunakan day-of-month dalam ID; batalkan juga itu
    // ketika jadwal diedit atau dihapus.
    for (int day = 1; day <= 31; day++) {
      try {
        await _plugin.cancel(_notificationId(reminderId, day));
      } catch (_) {
        // Teruskan membatalkan notifikasi hari lain.
      }
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static Future<void> _write(List<TrainingReminder> reminders) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(reminders.map((TrainingReminder item) => item.toJson()).toList()),
    );
    changes.value++;
  }
}
