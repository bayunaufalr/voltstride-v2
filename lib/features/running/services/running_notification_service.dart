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

    final String time = _formatDuration(elapsed);
    final String distance = (distanceMeters / 1000.0).toStringAsFixed(2);
    final String speed = speedKmh != null &&
            speedKmh.isFinite && speedKmh >= 0.5 && speedKmh <= 35
        ? '${speedKmh.toStringAsFixed(1)} km/jam'
        : '-- km/jam';
    final String pace = _formatPace(paceSecondsPerKm);
    final String title = paused
        ? 'VoltStride • $activityLabel dijeda'
        : 'VoltStride • $activityLabel berlangsung';
    final String body = paused
        ? 'DIJEDA • Waktu $time • $distance km • $speed • $pace/km'
        : 'Waktu $time • $distance km • $speed • $pace/km';

    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_live_run_stats',
      'Statistik lari VoltStride',
      channelDescription: 'Waktu, jarak, kecepatan, dan pace sesi lari aktif.',
      importance: Importance.low,
      priority: Priority.low,
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
    required double? currentPaceSecondsPerKm,
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
    final String target = _formatPace(targetPaceSecondsPerKm);
    final bool hasCurrent = currentPaceSecondsPerKm != null &&
        currentPaceSecondsPerKm.isFinite &&
        currentPaceSecondsPerKm > 0 &&
        currentPaceSecondsPerKm <= 3600;
    final String current = hasCurrent
        ? _formatPace(currentPaceSecondsPerKm)
        : '--:--';
    final String requiredPace = _formatPace(
      guidance.requiredRemainingPaceSecondsPerKm,
    );

    final String advice;
    if (guidance.targetReached) {
      advice = english
          ? 'Target distance reached. Check the finished average pace against $target/km.'
          : 'Jarak target tercapai. Bandingkan pace rata-rata akhir dengan target $target/km.';
    } else if (!guidance.targetAchievable) {
      advice = english
          ? 'The target average pace is no longer mathematically reachable over the remaining distance. Finish at a safe effort.'
          : 'Target pace rata-rata tidak lagi tercapai secara hitungan pada sisa jarak. Selesaikan dengan usaha yang aman.';
    } else {
      final String remaining = guidance.remainingDistanceKm.toStringAsFixed(2);
      advice = english
          ? 'To finish at $target/km average, cover the remaining $remaining km at about $requiredPace/km.'
          : 'Untuk finis dengan rata-rata $target/km, tempuh sisa $remaining km sekitar $requiredPace/km.';
    }

    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_minute_pacer_priority_v3',
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
      category: AndroidNotificationCategory.navigation,
      visibility: NotificationVisibility.public,
    );
    await _plugin.show(
      42602,
      english
          ? 'Running pacer • Minute $elapsedMinutes'
          : 'Pacer lari • Menit $elapsedMinutes',
      english
          ? 'Target avg $target/km • Current avg $current/km. $advice'
          : 'Target rata-rata $target/km • Rata-rata saat ini $current/km. $advice',
      NotificationDetails(android: android),
    );
  }

  static Future<void> stop() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
    await _plugin.cancel(42602);
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
