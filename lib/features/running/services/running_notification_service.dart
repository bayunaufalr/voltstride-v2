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
  static const int _pacerNotificationId = 42602;
  static final Set<int> _intervalNotificationIds = <int>{};
  static bool _initialized = false;
  static bool _legacyPacerNotificationsCleared = false;

  static Future<void> _ensureInitialized() async {
    if (_initialized) return;
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
    if (!_legacyPacerNotificationsCleared) {
      _legacyPacerNotificationsCleared = true;
      try {
        final List<ActiveNotification> active =
            await _plugin.getActiveNotifications();
        for (final ActiveNotification notification in active) {
          if (notification.id != _pacerNotificationId &&
              (notification.title ?? '').contains('VoltStride Pacer')) {
            await _plugin.cancel(notification.id ?? 0);
          }
        }
      } catch (_) {
        // Kegagalan membersihkan notifikasi versi lama tidak menghalangi sesi.
      }
    }
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
      'voltstride_live_run_stats_v4',
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
    final double? currentAveragePace = currentDistanceKm > 0 &&
            elapsed.inSeconds > 0
        ? elapsed.inSeconds / currentDistanceKm
        : null;
    final String requiredPace = _formatPace(
      guidance.requiredRemainingPaceSecondsPerKm,
    );

    final String advice;
    if (currentDistanceKm >= targetDistanceKm && currentAveragePace != null) {
      if (currentAveragePace < targetPaceSecondsPerKm * 0.90) {
        advice = english ? 'Pace too fast' : 'Pace terlalu cepat';
      } else if (currentAveragePace <= targetPaceSecondsPerKm) {
        advice = english ? 'Pace on target' : 'Pace aman';
      } else {
        advice = english
            ? 'Distance reached · ${_formatPace(currentAveragePace)}/km'
            : 'Jarak tercapai · ${_formatPace(currentAveragePace)}/km';
      }
    } else if (currentAveragePace != null &&
        currentAveragePace < targetPaceSecondsPerKm) {
      advice = currentAveragePace < targetPaceSecondsPerKm * 0.90
          ? (english ? 'Pace too fast' : 'Pace terlalu cepat')
          : (english ? 'Pace on target' : 'Pace aman');
    } else if (!guidance.targetAchievable) {
      advice = english
          ? 'Target out of reach · keep a steady pace'
          : 'Target sulit tercapai · jaga pace stabil';
    } else {
      advice = english
          ? 'Run at $requiredPace/km now'
          : 'Sekarang harus lari pace $requiredPace/km';
    }

    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_pacer_watch_v11',
      english ? 'Pacer notifications' : 'Notifikasi pacer',
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
      timeoutAfter: 30000,
      ticker: advice,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
    );
    // Selalu gunakan ID yang sama. Notifikasi baru menggantikan notifikasi
    // pacer sebelumnya, alih-alih menumpuk satu notifikasi setiap menit.
    await _plugin.cancel(_pacerNotificationId);
    await _plugin.show(
      _pacerNotificationId,
      'VoltStride Pacer',
      advice,
      NotificationDetails(android: android),
    );
  }

  /// Notifikasi eksplisit saat latihan interval berpindah fase.
  static Future<void> showIntervalTransition({
    required String stage,
    required int repetition,
    required int totalRepetitions,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _ensureInitialized();

    final bool english =
        AppLanguageService.localeNotifier.value.languageCode == 'en';
    final String title;
    final String body;
    switch (stage) {
      case 'recovery':
        title = english ? 'Start recovery' : 'Mulai pemulihan';
        body = english
            ? 'Run interval $repetition finished. Recovery starts now.'
            : 'Lari selesai. Mulai pemulihan sekarang · interval $repetition/$totalRepetitions.';
        break;
      case 'complete':
        title = english ? 'Interval complete' : 'Interval selesai';
        body = english
            ? 'All $totalRepetitions intervals are complete.'
            : 'Semua $totalRepetitions interval sudah selesai.';
        break;
      default:
        title = english ? 'Start running' : 'Mulai lari';
        body = english
            ? 'Recovery finished. Start running now · interval $repetition/$totalRepetitions.'
            : 'Pemulihan selesai. Mulai lari sekarang · interval $repetition/$totalRepetitions.';
        break;
    }

    final int stageCode = stage == 'recovery' ? 1 : (stage == 'complete' ? 2 : 0);
    final int notificationId =
        43000 + repetition.clamp(0, 30).toInt() * 3 + stageCode;
    _intervalNotificationIds.add(notificationId);
    final AndroidNotificationDetails android = AndroidNotificationDetails(
      'voltstride_interval_transition_v2',
      english ? 'Interval changes' : 'Pergantian interval',
      channelDescription: english
          ? 'Clear notices when a running or recovery interval begins.'
          : 'Pemberitahuan saat fase lari atau pemulihan dimulai.',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.navigation,
      visibility: NotificationVisibility.public,
      onlyAlertOnce: false,
      playSound: false,
      enableVibration: false,
      autoCancel: true,
      timeoutAfter: 20000,
      ticker: title,
    );
    await _plugin.show(
      notificationId,
      title,
      body,
      NotificationDetails(android: android),
    );
  }

  static Future<void> stop() async {
    if (!_initialized) return;
    await _plugin.cancel(_notificationId);
    await _plugin.cancel(_pacerNotificationId);
    for (final int notificationId in _intervalNotificationIds) {
      await _plugin.cancel(notificationId);
    }
    _intervalNotificationIds.clear();
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
