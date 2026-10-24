// ignore_for_file: lines_longer_than_80_chars, prefer_const_constructors
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../services/app_language_service.dart';
import 'pacer_guidance.dart';

/// Notifikasi statistik lari yang diperbarui berkala.
/// Geolocator tetap menampilkan notifikasi layanan GPS-nya sendiri.
class RunningNotificationService {
  RunningNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const int _notificationId = 42601;
  static final Set<int> _pacerNotificationIds = <int>{};
  static bool _initialized = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<void> showRunStats({
    required Duration elapsed,
    required double distanceMeters,
    required double? speedKmh,
    required double? paceSecondsPerKm,
    required bool paused,
    String activityLabel = 'Aktivitas',
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _ensureInitialized();

    final bool english =
        AppLanguageService.localeNotifier.value.languageCode == 'en';
    final String time = _formatDuration(elapsed);
    final String distance = (distanceMeters / 1000.0).toStringAsFixed(2);
    final String speed = speedKmh != null &&
            speedKmh.isFinite && speedKmh >= 0.5 && speedKmh <= 35
        ? '${speedKmh.toStringAsFixed(1)} ${english ? 'km/h' : 'km/jam'}'
        : (english ? '-- km/h' : '-- km/jam');
    final String pace = _formatPace(paceSecondsPerKm);
    final String title = paused
        ? (english
            ? 'VoltStride • $activityLabel paused'
            : 'VoltStride • $activityLabel dijeda')
        : (english
            ? 'VoltStride • $activityLabel'
            : 'VoltStride • $activityLabel');
    final String body = paused
        ? (english
            ? 'PAUSED • $time • $distance km'
            : 'DIJEDA • $time • $distance km')
        : (english
            ? 'Pace $pace/km • $speed • $distance km'
            : 'Pace $pace/km • $speed • $distance km');

    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_live_run_stats_v3',
      'Pace dan kecepatan VoltStride',
      channelDescription: 'Pace dan kecepatan sesi aktif.',
      importance: Importance.high,
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: false,
      visibility: NotificationVisibility.public,
    );
    await _plugin.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(android: android),
    );
  }

  /// Gives minute-by-minute pace advice for the requested average pace.
  static Future<void> showPacerUpdate({
    required double targetDistanceKm,
    required double targetPaceSecondsPerKm,
    required double currentDistanceKm,
    required Duration elapsed,
    required int elapsedMinutes,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _ensureInitialized();

    final bool english =
        AppLanguageService.localeNotifier.value.languageCode == 'en';
    final PacerGuidance guidance = PacerGuidance.calculate(
      targetDistanceKm: targetDistanceKm,
      targetAveragePaceSecondsPerKm: targetPaceSecondsPerKm,
      currentDistanceKm: currentDistanceKm,
      elapsed: elapsed,
    );
    final String requiredPace = _formatPace(
      guidance.requiredRemainingPaceSecondsPerKm,
    );

    final String advice;
    if (guidance.targetReached) {
      advice = english ? 'Average pace target reached' : 'Target pace rata-rata tercapai';
    } else if (!guidance.targetAchievable) {
      advice = english
          ? 'Target unreachable · keep a safe pace'
          : 'Target tak terkejar · jaga pace aman';
    } else {
      advice = english
          ? 'Run at $requiredPace/km now'
          : 'Sekarang harus lari pace $requiredPace/km';
    }

    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_pacer_watch_v10',
      english ? 'Minute-by-minute pacer' : 'Pacer setiap menit',
      channelDescription: english
          ? 'High-priority pace guidance while a running session is active.'
          : 'Arahan pace berprioritas tinggi selama sesi lari berlangsung.',
      importance: Importance.max,
      priority: Priority.max,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );
    final int notificationId = 42602 + elapsedMinutes.clamp(1, 10000).toInt();
    _pacerNotificationIds.add(notificationId);
    await _plugin.show(
      notificationId,
      english ? 'VoltStride Pacer' : 'VoltStride Pacer',
      advice,
      NotificationDetails(android: android),
    );
  }

  static Future<void> stop() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
    for (final int notificationId in _pacerNotificationIds) {
      await _plugin.cancel(notificationId);
    }
    _pacerNotificationIds.clear();
  }

  static String _formatDuration(Duration duration) {
    final int hours = duration.inHours;
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${duration.inMinutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatPace(double? secondsPerKm) {
    if (secondsPerKm == null ||
        !secondsPerKm.isFinite ||
        secondsPerKm <= 0 ||
        secondsPerKm > 3600) {
      return '--:--';
    }
    final int rounded = secondsPerKm.round();
    return '${rounded ~/ 60}:${(rounded % 60).toString().padLeft(2, '0')}';
  }
}
