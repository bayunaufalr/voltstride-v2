import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/app_language_service.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

/// Pilihan cara VoltStride mengingatkan jadwal.
enum ReminderStyle { notificationOnly, notificationAndAlarm }

/// Satu kegiatan rutin pada hari dan waktu tertentu.
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

  TrainingReminder copyWith({List<String>? completedDates}) {
    return TrainingReminder(
      id: id,
      activity: activity,
      weekdays: weekdays,
      hour: hour,
      minute: minute,
      durationMinutes: durationMinutes,
      style: style,
      sound: sound,
      completedDates: completedDates ?? this.completedDates,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'activity': activity,
        'weekdays': weekdays,
        'hour': hour,
        'minute': minute,
        'durationMinutes': durationMinutes,
        'style': style.name,
        'sound': sound,
        'completedDates': completedDates,
      };

  factory TrainingReminder.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawDays = json['weekdays'] as List<dynamic>? ??
        <dynamic>[DateTime.monday, DateTime.wednesday, DateTime.friday];
    return TrainingReminder(
      id: (json['id'] as num).toInt(),
      activity: json['activity'] as String? ?? 'Lari',
      weekdays: rawDays.map((dynamic day) => (day as num).toInt()).toList(),
      hour: (json['hour'] as num?)?.toInt() ?? 7,
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt() ?? 30,
      style: ReminderStyle.values.firstWhere(
        (ReminderStyle value) => value.name == json['style'],
        orElse: () => ReminderStyle.notificationOnly,
      ),
      sound: json['sound'] as String? ?? 'lembut',
      completedDates: (json['completedDates'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  String get timeText =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String get daysText {
    const List<String> labels = <String>[
      'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'
    ];
    final List<int> sorted = weekdays.toList()..sort();
    return sorted.map((int day) => labels[day - 1]).join(', ');
  }
}

/// Menyimpan jadwal di perangkat dan memasang pemberitahuan Android.
class ReminderService {
  ReminderService._();

  static const String _storageKey = 'voltstride_training_reminders_v1';
  static const String _zoneName = 'Asia/Jakarta';
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static Future<void>? _initialization;

  static bool get _english =>
      AppLanguageService.localeNotifier.value.languageCode == 'en';

  static String _activityName(String storedActivity) {
    final String value = storedActivity.toLowerCase();
    if (value.contains('kekuatan') || value.contains('strength')) {
      return _english ? 'strength training' : 'latihan kekuatan';
    }
    if (value.contains('interval')) return _english ? 'interval run' : 'lari interval';
    if (value.contains('jalan') || value.contains('walk')) return _english ? 'walk' : 'jalan';
    if (value.contains('lari') || value.contains('run')) return _english ? 'run' : 'lari';
    return storedActivity.toLowerCase();
  }

  static String _notificationTitle(TrainingReminder reminder) {
    final String activity = _activityName(reminder.activity);
    if (_english) {
      return reminder.style == ReminderStyle.notificationAndAlarm
          ? 'Time for $activity'
          : 'Scheduled $activity';
    }
    return reminder.style == ReminderStyle.notificationAndAlarm
        ? 'Waktunya $activity'
        : 'Jadwal $activity';
  }

  static String _notificationBody(TrainingReminder reminder) => _english
      ? 'Duration: ${reminder.durationMinutes} min.'
      : 'Durasi ${reminder.durationMinutes} menit.';


  /// Hindari inisialisasi plugin ganda jika halaman dan proses pemulihan
  /// pengingat memanggil fungsi ini hampir bersamaan.
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
      // Izinkan percobaan ulang jika inisialisasi pertama gagal.
      _initialization = null;
      rethrow;
    }
  }

  static Future<List<TrainingReminder>> getAll() async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
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
    await initialize();
    final List<TrainingReminder> existing = await getAll();
    await _cancelReminderNotifications(reminder.id);

    for (final int day in reminder.weekdays.toSet()) {
      final int notificationId = _notificationId(reminder.id, day);
      final timezone.TZDateTime nextDate = _nextDate(
        weekday: day,
        hour: reminder.hour,
        minute: reminder.minute,
      );
      await _plugin.zonedSchedule(
        notificationId,
        _notificationTitle(reminder),
        _notificationBody(reminder),
        nextDate,
        _details(reminder),
        payload: 'voltstride-reminder-${reminder.id}',
        androidScheduleMode: _scheduleMode(reminder),
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }

    final List<TrainingReminder> updated = <TrainingReminder>[
      ...existing.where((TrainingReminder item) => item.id != reminder.id),
      reminder,
    ]..sort((TrainingReminder a, TrainingReminder b) => a.hour != b.hour
        ? a.hour.compareTo(b.hour)
        : a.minute.compareTo(b.minute));
    await _write(updated);
  }

  static Future<void> delete(TrainingReminder reminder) async {
    await initialize();
    await _cancelReminderNotifications(reminder.id);
    final List<TrainingReminder> updated = await getAll();
    updated.removeWhere((TrainingReminder item) => item.id == reminder.id);
    await _write(updated);
  }

  static Future<void> setOccurrenceCompleted({
    required int reminderId,
    required String dateKey,
    required bool completed,
  }) async {
    final List<TrainingReminder> reminders = await getAll();
    final List<TrainingReminder> updated = reminders.map((TrainingReminder item) {
      if (item.id != reminderId) return item;
      final Set<String> dates = item.completedDates.toSet();
      if (completed) {
        dates.add(dateKey);
      } else {
        dates.remove(dateKey);
      }
      return item.copyWith(completedDates: dates.toList()..sort());
    }).toList(growable: false);
    await _write(updated);
  }

  static Future<void> restoreSavedSchedules() async {
    await initialize();
    final List<TrainingReminder> saved = await getAll();
    for (final TrainingReminder reminder in saved) {
      try {
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
            _details(reminder),
            payload: 'voltstride-reminder-${reminder.id}',
            androidScheduleMode: _scheduleMode(reminder),
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      } catch (_) {
        // Satu jadwal yang tidak bisa dipasang tidak membatalkan jadwal lain.
      }
    }
  }

  /// Memeriksa izin notifikasi Android tanpa menutup formulir jadwal.
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
      // Jika dialog sudah ditolak, buka halaman izin aplikasi, bukan sekadar
      // menyuruh pengguna mencari setelan secara manual.
      await permissions.openAppSettings();
      allowed = await android.areNotificationsEnabled();
    }
    return allowed == true;
  }

  /// Membaca izin notifikasi tanpa memunculkan dialog atau mengubah setelan.
  static Future<bool> areNotificationsEnabled() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.areNotificationsEnabled() == true;
  }

  /// Membuka halaman pengaturan VoltStride di Android.
  static Future<void> openAppSettings() async {
    await permissions.openAppSettings();
  }

  /// Membaca status izin alarm tepat setelah pengguna kembali dari Setelan.
  static Future<bool> isExactAlarmPermissionGranted() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.canScheduleExactNotifications() == true;
  }

  /// Membuka halaman izin alarm khusus untuk VoltStride.
  /// Android memang mengharuskan pengguna mengaktifkan izin ini di Setelan.
  static Future<void> openExactAlarmSettings() async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    try {
      // Plugin ini membuka halaman khusus izin alarm tepat di Android.
      await android.requestExactAlarmsPermission();
    } catch (_) {
      // Beberapa varian Android menolak deep-link khusus. Buka setelan app.
      await permissions.openAppSettings();
    }
  }

  static Future<bool> areRequiredPermissionsGranted(
    ReminderStyle style,
  ) async {
    await initialize();
    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    final bool notificationsAllowed =
        await android.areNotificationsEnabled() == true;
    if (!notificationsAllowed) return false;

    if (style == ReminderStyle.notificationAndAlarm) {
      return isExactAlarmPermissionGranted();
    }
    return true;
  }

  /// Meminta izin yang diperlukan. Formulir akan tetap terbuka bila pengguna
  /// perlu mengaktifkan izin alarm dari Setelan Android.
  static Future<bool> requestRequiredPermissions(ReminderStyle style) async {
    if (!await requestNotificationPermission()) return false;
    if (style == ReminderStyle.notificationAndAlarm &&
        !await isExactAlarmPermissionGranted()) {
      await openExactAlarmSettings();
      return isExactAlarmPermissionGranted();
    }
    return true;
  }

  static AndroidScheduleMode _scheduleMode(TrainingReminder reminder) {
    return reminder.style == ReminderStyle.notificationAndAlarm
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Memainkan suara yang dipilih melalui notifikasi percobaan.
  static Future<void> previewSound(String sound) async {
    await initialize();
    final bool permission = await requestNotificationPermission();
    if (!permission) {
      throw StateError('Izin notifikasi belum diaktifkan.');
    }
    final TrainingReminder contoh = TrainingReminder(
      id: 987654,
      activity: 'uji suara',
      weekdays: const <int>[DateTime.monday],
      hour: 7,
      minute: 0,
      durationMinutes: 30,
      style: ReminderStyle.notificationAndAlarm,
      sound: sound,
    );
    await _plugin.cancel(987654);
    await _plugin.show(
      987654,
      'Contoh suara alarm',
      'Ini suara yang dipilih untuk pengingat latihan.',
      _details(contoh),
      payload: 'voltstride-alarm-preview',
    );
  }

  static NotificationDetails _details(TrainingReminder reminder) {
    final bool withAlarm =
        reminder.style == ReminderStyle.notificationAndAlarm;
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      withAlarm ? 'voltstride_alarm_${reminder.sound}' : 'voltstride_notice',
      withAlarm ? 'Alarm latihan' : 'Pengingat latihan',
      channelDescription: withAlarm
          ? 'Pengingat latihan dengan suara pilihan pengguna.'
          : 'Pemberitahuan jadwal latihan.',
      importance: withAlarm ? Importance.max : Importance.defaultImportance,
      priority: withAlarm ? Priority.max : Priority.defaultPriority,
      playSound: true,
      sound: withAlarm
          ? RawResourceAndroidNotificationSound(_soundResource(reminder.sound))
          : null,
      audioAttributesUsage:
          withAlarm ? AudioAttributesUsage.alarm : AudioAttributesUsage.notification,
      enableVibration: true,
      category: withAlarm ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
    );
    return NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );
  }

  static String _soundResource(String value) {
    switch (value) {
      case 'digital':
        return 'volt_alarm_digital';
      case 'denyut':
        return 'volt_alarm_pulse';
      default:
        return 'volt_alarm_gentle';
    }
  }

  static int _notificationId(int reminderId, int weekday) =>
      (reminderId * 10) + weekday;

  static timezone.TZDateTime _nextDate({
    required int weekday,
    required int hour,
    required int minute,
  }) {
    final timezone.TZDateTime now = timezone.TZDateTime.now(timezone.local);
    int daysAhead = (weekday - now.weekday) % 7;
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
      await _plugin.cancel(_notificationId(reminderId, day));
    }
  }

  static Future<void> _write(List<TrainingReminder> reminders) async {
    final SharedPreferences preferences =
        await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(reminders.map((TrainingReminder item) => item.toJson()).toList()),
    );
  }
}
