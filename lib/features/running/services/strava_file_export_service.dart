import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../models/run_session.dart';

/// Membuat file TCX untuk diunggah manual ke Strava, tanpa API berbayar.
class StravaFileExportService {
  const StravaFileExportService._();

  static const MethodChannel _storageChannel =
      MethodChannel('voltstride/android_settings');

  static Future<String> saveTcx(RunSession session) async {
    final String tcx = buildTcx(session);
    final String fileName = _fileName(session.startedAt);
    final String? location = await _storageChannel.invokeMethod<String>(
      'saveFileToDownloads',
      <String, Object?>{
        'fileName': fileName,
        'mimeType': 'application/vnd.garmin.tcx+xml',
        'bytes': Uint8List.fromList(utf8.encode(tcx)),
      },
    );
    if (location == null || location.isEmpty) {
      throw StateError('File TCX tidak berhasil disimpan ke perangkat.');
    }
    return location;
  }

  /// Menghasilkan TCX 2.0 dengan waktu, jarak, elevasi, HR, dan cadence.
  static String buildTcx(RunSession session) {
    final DateTime start = session.startedAt.toUtc();
    final DateTime end = (session.finishedAt ??
            session.startedAt.add(session.elapsed))
        .toUtc();
    if (end.isBefore(start)) {
      throw StateError('Waktu selesai aktivitas tidak valid.');
    }

    final List<RunPoint> gpsPoints = session.route
        .where(_isValidPoint)
        .toList(growable: false);
    final bool hasGps =
        session.environment == RunEnvironment.outdoor && gpsPoints.length >= 2;
    final List<List<_ExportPoint>> segments;

    if (hasGps) {
      if (gpsPoints.length < 2) {
        throw StateError(
          'Rute GPS belum memiliki cukup titik untuk diekspor ke Strava.',
        );
      }
      final _TrackMetrics metrics =
          _calculateTrackMetrics(session, gpsPoints);
      if (metrics.rawDistanceMeters <= 0 ||
          !metrics.rawDistanceMeters.isFinite ||
          !session.distanceMeters.isFinite ||
          session.distanceMeters <= 0) {
        throw StateError(
          'Jarak GPS tidak valid. Rekam aktivitas luar ruangan yang lebih '
          'panjang.',
        );
      }
      segments = _buildOutdoorSegments(gpsPoints, metrics);
    } else {
      if (session.elapsed.inSeconds <= 0 ||
          !session.distanceMeters.isFinite ||
          (session.distanceMeters <= 0 &&
              session.activityType != RunActivityType.hiit)) {
        throw StateError(
          'Aktivitas dalam ruangan perlu durasi dan jarak yang valid.',
        );
      }
      segments = <List<_ExportPoint>>[
        _buildIndoorTrack(session, start, end),
      ];
    }

    final int? averageHeartRate = session.averageHeartRateBpm ??
        _averageHeartRate(session.heartRateSamples);
    final int? maximumHeartRate = _maximumHeartRate(session.heartRateSamples);
    final String sport = session.activityType == RunActivityType.run
        ? 'Running'
        : 'Other';

    final StringBuffer xml = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<TrainingCenterDatabase '
        'xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2" '
        'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:schemaLocation="http://www.garmin.com/xmlschemas/'
        'TrainingCenterDatabase/v2 '
        'http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd">',
      )
      ..writeln('<Activities>')
      ..writeln('<Activity Sport="$sport">')
      ..writeln('<Id>${_xmlTime(start)}</Id>');

    if (session.activityType == RunActivityType.hiit) {
      final String notes = _escapeXml(session.activityDetails ?? 'HIIT');
      xml.writeln('<Notes>VoltStride HIIT: $notes</Notes>');
    } else if (session.activityType == RunActivityType.walk) {
      xml.writeln('<Notes>VoltStride activity type: walk</Notes>');
    }

    xml
      ..writeln('<Lap StartTime="${_xmlTime(start)}">')
      ..writeln(
        '<TotalTimeSeconds>'
        '${_decimalSeconds(session.elapsed.inMilliseconds)}'
        '</TotalTimeSeconds>',
      )
      ..writeln(
        '<DistanceMeters>${_decimal(session.distanceMeters)}</DistanceMeters>',
      );

    if (averageHeartRate != null && averageHeartRate > 0) {
      xml.writeln(
        '<AverageHeartRateBpm><Value>$averageHeartRate</Value>'
        '</AverageHeartRateBpm>',
      );
    }
    if (maximumHeartRate != null && maximumHeartRate > 0) {
      xml.writeln(
        '<MaximumHeartRateBpm><Value>$maximumHeartRate</Value>'
        '</MaximumHeartRateBpm>',
      );
    }

    xml
      ..writeln('<Intensity>Active</Intensity>')
      ..writeln('<TriggerMethod>Manual</TriggerMethod>');

    for (final List<_ExportPoint> segment in segments) {
      if (segment.isEmpty) continue;
      xml.writeln('<Track>');
      for (final _ExportPoint point in segment) {
        xml
          ..writeln('<Trackpoint>')
          ..writeln('<Time>${_xmlTime(point.timestamp)}</Time>');

        final double? latitude = point.latitude;
        final double? longitude = point.longitude;
        if (latitude != null && longitude != null) {
          xml
            ..writeln('<Position>')
            ..writeln(
              '<LatitudeDegrees>${_decimal(latitude)}'
              '</LatitudeDegrees>',
            )
            ..writeln(
              '<LongitudeDegrees>${_decimal(longitude)}'
              '</LongitudeDegrees>',
            )
            ..writeln('</Position>');
        }

        final double? altitude = point.altitudeMeters;
        if (altitude != null && altitude.isFinite && altitude > -12000) {
          xml.writeln('<AltitudeMeters>${_decimal(altitude)}</AltitudeMeters>');
        }
        xml.writeln(
          '<DistanceMeters>'
          '${_decimal(point.cumulativeDistanceMeters)}'
          '</DistanceMeters>',
        );

        final int? heartRate = point.heartRateBpm ??
            _nearestHeartRate(
              session.heartRateSamples,
              point.activeElapsedSeconds,
            );
        if (heartRate != null && heartRate > 0) {
          xml.writeln('<HeartRateBpm><Value>$heartRate</Value></HeartRateBpm>');
        }

        final int? cadence = point.cadenceSpm ??
            _nearestCadence(
              session.cadenceSamples,
              point.cumulativeDistanceMeters,
            );
        if (cadence != null && cadence > 0) {
          xml.writeln('<Cadence>$cadence</Cadence>');
        }
        xml.writeln('</Trackpoint>');
      }
      xml.writeln('</Track>');
    }

    xml
      ..writeln('</Lap>')
      ..writeln('<Creator xsi:type="Device_t">')
      ..writeln('<Name>VoltStride</Name>')
      ..writeln('<UnitId>0</UnitId>')
      ..writeln('<ProductID>0</ProductID>')
      ..writeln('<Version>')
      ..writeln('<VersionMajor>1</VersionMajor>')
      ..writeln('<VersionMinor>0</VersionMinor>')
      ..writeln('<BuildMajor>1</BuildMajor>')
      ..writeln('<BuildMinor>0</BuildMinor>')
      ..writeln('</Version>')
      ..writeln('</Creator>')
      ..writeln('</Activity>')
      ..writeln('</Activities>')
      ..writeln('</TrainingCenterDatabase>');
    return xml.toString();
  }

  static List<_ExportPoint> _buildIndoorTrack(
    RunSession session,
    DateTime start,
    DateTime finish,
  ) {
    final int totalSeconds = session.elapsed.inSeconds;
    final List<RunHeartRateSample> samples = session.heartRateSamples
        .where((RunHeartRateSample sample) =>
            sample.elapsedSeconds > 0 && sample.elapsedSeconds < totalSeconds)
        .toList(growable: false);
    final List<_ExportPoint> track = <_ExportPoint>[
      _ExportPoint(
        timestamp: start,
        cumulativeDistanceMeters: 0,
        activeElapsedSeconds: 0,
        latitude: null,
        longitude: null,
        altitudeMeters: null,
        heartRateBpm: _nearestHeartRate(session.heartRateSamples, 0),
        cadenceSpm: _nearestCadence(session.cadenceSamples, 0),
      ),
    ];

    for (final RunHeartRateSample sample in samples) {
      final int elapsed = sample.elapsedSeconds;
      final double progress = elapsed / totalSeconds;
      final double distance = session.distanceMeters * progress;
      track.add(
        _ExportPoint(
          timestamp: start.add(Duration(seconds: elapsed)),
          cumulativeDistanceMeters: distance,
          activeElapsedSeconds: elapsed,
          latitude: null,
          longitude: null,
          altitudeMeters: null,
          heartRateBpm: sample.bpm,
          cadenceSpm: _nearestCadence(session.cadenceSamples, distance),
        ),
      );
    }

    track.add(
      _ExportPoint(
        timestamp: finish.isAfter(start) ? finish : start.add(session.elapsed),
        cumulativeDistanceMeters: session.distanceMeters,
        activeElapsedSeconds: totalSeconds,
        latitude: null,
        longitude: null,
        altitudeMeters: null,
        heartRateBpm: _nearestHeartRate(
          session.heartRateSamples,
          totalSeconds,
        ),
        cadenceSpm: _nearestCadence(
          session.cadenceSamples,
          session.distanceMeters,
        ),
      ),
    );
    return track;
  }

  static List<List<_ExportPoint>> _buildOutdoorSegments(
    List<RunPoint> points,
    _TrackMetrics metrics,
  ) {
    final List<List<_ExportPoint>> segments = <List<_ExportPoint>>[
      <_ExportPoint>[],
    ];
    for (int index = 0; index < points.length; index++) {
      final RunPoint point = points[index];
      if (index > 0 && point.startsNewSegment) {
        segments.add(<_ExportPoint>[]);
      }
      final double distance =
          metrics.cumulativeRawDistance[index] * metrics.scale;
      segments.last.add(
        _ExportPoint(
          timestamp: point.timestamp,
          latitude: point.latitude,
          longitude: point.longitude,
          altitudeMeters: point.altitudeMeters,
          cumulativeDistanceMeters: distance,
          activeElapsedSeconds: metrics.activeSecondsAtPoint[index],
          heartRateBpm: null,
          cadenceSpm: null,
        ),
      );
    }
    return segments;
  }

  static _TrackMetrics _calculateTrackMetrics(
    RunSession session,
    List<RunPoint> points,
  ) {
    final List<double> rawCumulative = <double>[0];
    final List<int> activeSecondsAtPoint = <int>[0];
    double rawDistance = 0;
    int activeSeconds = 0;

    for (int index = 1; index < points.length; index++) {
      final RunPoint previous = points[index - 1];
      final RunPoint current = points[index];
      final int deltaSeconds = current.timestamp
          .difference(previous.timestamp)
          .inSeconds;
      if (!current.startsNewSegment) {
        rawDistance += _distanceBetween(previous, current);
        if (deltaSeconds > 0) activeSeconds += deltaSeconds;
      }
      rawCumulative.add(rawDistance);
      activeSecondsAtPoint.add(activeSeconds);
    }

    final double scale = rawDistance > 0
        ? session.distanceMeters / rawDistance
        : 1;
    return _TrackMetrics(
      rawDistanceMeters: rawDistance,
      scale: scale,
      activeSecondsAtPoint: activeSecondsAtPoint,
      cumulativeRawDistance: rawCumulative,
    );
  }

  static bool _isValidPoint(RunPoint point) {
    return point.latitude.isFinite &&
        point.longitude.isFinite &&
        point.latitude >= -90 &&
        point.latitude <= 90 &&
        point.longitude >= -180 &&
        point.longitude <= 180;
  }

  static double _distanceBetween(RunPoint first, RunPoint second) {
    const double earthRadiusMeters = 6371000;
    final double latitudeOne = _radians(first.latitude);
    final double latitudeTwo = _radians(second.latitude);
    final double latitudeDifference =
        _radians(second.latitude - first.latitude);
    final double longitudeDifference =
        _radians(second.longitude - first.longitude);
    final double a = (math.pow(math.sin(latitudeDifference / 2), 2).toDouble() +
            math.cos(latitudeOne) *
                math.cos(latitudeTwo) *
                math.pow(math.sin(longitudeDifference / 2), 2).toDouble())
        .clamp(0.0, 1.0)
        .toDouble();
    return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  static int? _nearestHeartRate(List<RunHeartRateSample> samples, int seconds) {
    if (samples.isEmpty) return null;
    RunHeartRateSample? closest;
    int difference = 31;
    for (final RunHeartRateSample sample in samples) {
      final int currentDifference = (sample.elapsedSeconds - seconds).abs();
      if (currentDifference < difference) {
        difference = currentDifference;
        closest = sample;
      }
    }
    return difference <= 30 ? closest?.bpm : null;
  }

  static int? _nearestCadence(List<RunCadenceSample> samples, double distance) {
    if (samples.isEmpty) return null;
    RunCadenceSample? closest;
    double difference = 76;
    for (final RunCadenceSample sample in samples) {
      final double currentDifference = (sample.distanceMeters - distance).abs();
      if (currentDifference < difference) {
        difference = currentDifference;
        closest = sample;
      }
    }
    return difference <= 75 ? closest?.cadenceSpm.round() : null;
  }

  static int? _averageHeartRate(List<RunHeartRateSample> samples) {
    if (samples.isEmpty) return null;
    final int total = samples.fold<int>(
      0,
      (int sum, RunHeartRateSample sample) => sum + sample.bpm,
    );
    return (total / samples.length).round();
  }

  static int? _maximumHeartRate(List<RunHeartRateSample> samples) {
    if (samples.isEmpty) return null;
    int maximum = samples.first.bpm;
    for (final RunHeartRateSample sample in samples.skip(1)) {
      if (sample.bpm > maximum) maximum = sample.bpm;
    }
    return maximum;
  }

  /// Membaca satu atau beberapa aktivitas dari file TCX 2.0.
  /// Parser ini menerima namespace TCX biasa maupun prefix namespace.
  static List<RunSession> parseTcxSessions(String contents) {
    if (contents.trim().isEmpty ||
        !contents.toLowerCase().contains('trainingcenterdatabase')) {
      throw const FormatException('File bukan TCX yang valid.');
    }
    final RegExp activityPattern = RegExp(
      r'<(?:[A-Za-z0-9_]+:)?Activity\b([^>]*)>(.*?)</(?:[A-Za-z0-9_]+:)?Activity\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    final Iterable<RegExpMatch> matches = activityPattern.allMatches(contents);
    final List<RunSession> sessions = <RunSession>[];
    for (final RegExpMatch match in matches) {
      final String body = match.group(2) ?? '';
      final String attributes = match.group(1) ?? '';
      final String sport = RegExp(
        r'\bSport\s*=\s*["\']([^"\']+)["\']',
        caseSensitive: false,
      ).firstMatch(attributes)?.group(1)?.toLowerCase() ?? 'running';
      final String notes = _readTcxText(body, 'Notes') ?? '';
      final bool isHiit = notes.toLowerCase().contains('voltstride hiit');
      final bool isWalk = sport.contains('walk') ||
          notes.toLowerCase().contains('activity type: walk');
      final RunActivityType activityType = isHiit
          ? RunActivityType.hiit
          : isWalk
              ? RunActivityType.walk
              : RunActivityType.run;

      final List<RunPoint> route = <RunPoint>[];
      final List<RunHeartRateSample> heartRates = <RunHeartRateSample>[];
      final List<RunCadenceSample> cadences = <RunCadenceSample>[];
      final List<DateTime> timestamps = <DateTime>[];
      final RegExp pointPattern = RegExp(
        r'<(?:[A-Za-z0-9_]+:)?Trackpoint\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?Trackpoint\s*>',
        caseSensitive: false,
        dotAll: true,
      );
      double lastDistance = 0;
      double? firstDistance;
      for (final RegExpMatch pointMatch in pointPattern.allMatches(body)) {
        final String pointXml = pointMatch.group(1) ?? '';
        final DateTime? timestamp = DateTime.tryParse(
          _readTcxText(pointXml, 'Time') ?? '',
        );
        if (timestamp == null) continue;
        timestamps.add(timestamp);
        final double? distance = _readTcxNumber(pointXml, 'DistanceMeters');
        if (distance != null && distance.isFinite && distance >= 0) {
          firstDistance ??= distance;
          lastDistance = math.max(lastDistance, distance).toDouble();
        }
        final double? latitude = _readTcxNumber(pointXml, 'LatitudeDegrees');
        final double? longitude = _readTcxNumber(pointXml, 'LongitudeDegrees');
        final double? altitude = _readTcxNumber(pointXml, 'AltitudeMeters');
        if (latitude != null && longitude != null &&
            latitude >= -90 && latitude <= 90 &&
            longitude >= -180 && longitude <= 180) {
          route.add(RunPoint(
            latitude: latitude,
            longitude: longitude,
            timestamp: timestamp,
            accuracyMeters: 0,
            altitudeMeters: altitude,
            startsNewSegment: route.isEmpty,
          ));
        }
        final int? bpm = _readTcxNumber(pointXml, 'Value', parentTag: 'HeartRateBpm')?.round();
        if (bpm != null && bpm >= 30 && bpm <= 250) {
          final int elapsedSeconds = timestamps.first == timestamp
              ? 0
              : timestamp.difference(timestamps.first).inSeconds;
          if (elapsedSeconds >= 0) {
            heartRates.add(RunHeartRateSample(
              elapsedSeconds: elapsedSeconds,
              bpm: bpm,
            ));
          }
        }
        final int? cadence = _readTcxNumber(pointXml, 'Cadence')?.round();
        if (cadence != null && cadence > 0) {
          cadences.add(RunCadenceSample(
            distanceMeters: distance ?? lastDistance,
            cadenceSpm: cadence.toDouble(),
          ));
        }
      }

      DateTime? start = _readTcxDate(body, 'Id');
      start ??= timestamps.isEmpty ? null : timestamps.first;
      if (start == null) continue;
      DateTime? finish = timestamps.isEmpty ? null : timestamps.last;
      final double? totalSeconds = _readTcxNumber(body, 'TotalTimeSeconds');
      final Duration elapsed = finish != null && !finish.isBefore(start)
          ? finish.difference(start)
          : Duration(milliseconds: ((totalSeconds ?? 0) * 1000).round());
      if (elapsed <= Duration.zero) continue;
      finish ??= start.add(elapsed);

      double distanceMeters = lastDistance - (firstDistance ?? 0);
      if (distanceMeters <= 0 && route.length >= 2) {
        distanceMeters = 0;
        for (int index = 1; index < route.length; index++) {
          distanceMeters += _distanceBetween(route[index - 1], route[index]);
        }
      }
      if (!distanceMeters.isFinite || distanceMeters < 0) distanceMeters = 0;
      final double? averagePace = distanceMeters > 0
          ? elapsed.inMilliseconds / 1000.0 / (distanceMeters / 1000.0)
          : null;
      final int? averageHeartRate = heartRates.isEmpty
          ? null
          : (heartRates.fold<int>(0, (int total, RunHeartRateSample sample) =>
                  total + sample.bpm) / heartRates.length).round();
      sessions.add(RunSession(
        startedAt: start,
        finishedAt: finish,
        distanceMeters: distanceMeters,
        elapsed: elapsed,
        movingTime: elapsed,
        averagePaceSecondsPerKm: averagePace,
        currentPaceSecondsPerKm: null,
        gpsAccuracyMeters: null,
        acceptedPoints: route.length,
        rejectedPoints: 0,
        route: route,
        splits: const <RunSplit>[],
        hundredMeterLaps: const <RunLap100m>[],
        intervalPlan: null,
        activityType: activityType,
        environment: route.length >= 2
            ? RunEnvironment.outdoor
            : RunEnvironment.indoor,
        averageHeartRateBpm: averageHeartRate,
        heartRateSamples: heartRates,
        cadenceSamples: cadences,
        activityDetails: isHiit
            ? notes.replaceFirst(RegExp(r'^VoltStride HIIT:\s*', caseSensitive: false), '')
            : null,
      ));
    }
    if (sessions.isEmpty) {
      throw const FormatException('Tidak ditemukan sesi TCX yang dapat dibaca.');
    }
    sessions.sort((RunSession a, RunSession b) =>
        a.startedAt.compareTo(b.startedAt));
    return sessions;
  }

  static String? _readTcxText(String source, String tag, {String? parentTag}) {
    final String input = parentTag == null
        ? source
        : _readTcxBlock(source, parentTag) ?? '';
    if (input.isEmpty) return null;
    final RegExp expression = RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag\\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?$tag\\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    final String? value = expression.firstMatch(input)?.group(1);
    return value?.replaceAll(RegExp(r'<[^>]+>'), '').trim();
  }

  static String? _readTcxBlock(String source, String tag) {
    final RegExp expression = RegExp(
      '<(?:[A-Za-z0-9_]+:)?$tag\\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?$tag\\s*>',
      caseSensitive: false,
      dotAll: true,
    );
    return expression.firstMatch(source)?.group(1);
  }

  static double? _readTcxNumber(
    String source,
    String tag, {
    String? parentTag,
  }) {
    final String? text = _readTcxText(
      source,
      tag,
      parentTag: parentTag,
    );
    return text == null ? null : double.tryParse(text);
  }

  static DateTime? _readTcxDate(String source, String tag) {
    final String? value = _readTcxText(source, tag);
    return value == null ? null : DateTime.tryParse(value);
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _decimal(double value) => value.toStringAsFixed(2);

  static String _decimalSeconds(int milliseconds) =>
      (milliseconds / 1000).toStringAsFixed(3);

  static String _xmlTime(DateTime value) {
    final DateTime utc = value.toUtc();
    final String year = utc.year.toString().padLeft(4, '0');
    final String month = utc.month.toString().padLeft(2, '0');
    final String day = utc.day.toString().padLeft(2, '0');
    final String hour = utc.hour.toString().padLeft(2, '0');
    final String minute = utc.minute.toString().padLeft(2, '0');
    final String second = utc.second.toString().padLeft(2, '0');
    final String millisecond = utc.millisecond.toString().padLeft(3, '0');
    return '$year-$month-$day' 'T$hour:$minute:$second.$millisecond' 'Z';
  }

  static String _fileName(DateTime value) {
    final DateTime local = value.toLocal();
    final String year = local.year.toString().padLeft(4, '0');
    final String month = local.month.toString().padLeft(2, '0');
    final String day = local.day.toString().padLeft(2, '0');
    final String hour = local.hour.toString().padLeft(2, '0');
    final String minute = local.minute.toString().padLeft(2, '0');
    return 'VoltStride_$year$month$day-$hour$minute.tcx';
  }
}

class _TrackMetrics {
  const _TrackMetrics({
    required this.rawDistanceMeters,
    required this.scale,
    required this.activeSecondsAtPoint,
    required this.cumulativeRawDistance,
  });

  final double rawDistanceMeters;
  final double scale;
  final List<int> activeSecondsAtPoint;
  final List<double> cumulativeRawDistance;
}

class _ExportPoint {
  const _ExportPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.altitudeMeters,
    required this.cumulativeDistanceMeters,
    required this.activeElapsedSeconds,
    required this.heartRateBpm,
    required this.cadenceSpm,
  });

  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final double? altitudeMeters;
  final double cumulativeDistanceMeters;
  final int activeElapsedSeconds;
  final int? heartRateBpm;
  final int? cadenceSpm;
}
