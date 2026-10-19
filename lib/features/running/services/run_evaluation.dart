import 'dart:math' as math;

import '../models/run_session.dart';

class RunEvaluation {
  final String title;
  final String overview;
  final List<String> observations;
  final List<String> recommendations;

  const RunEvaluation({
    required this.title,
    required this.overview,
    required this.observations,
    required this.recommendations,
  });
}

/// Evaluasi performa lari lokal. Ini coaching sederhana, bukan diagnosis medis.
RunEvaluation evaluateRun(RunSession session) {
  final List<String> observations = <String>[];
  final List<String> recommendations = <String>[];
  final double distanceKm = session.distanceKm;
  final double? averagePace = session.averagePaceSecondsPerKm;
  final List<double> paces = session.splits
      .map((RunSplit split) => split.paceSecondsPerKm.toDouble())
      .where((double pace) => pace.isFinite && pace > 0 && pace <= 3600)
      .toList(growable: false);

  // Di bawah 300 m, selisih satu atau dua titik GPS dapat mengubah pace
  // secara drastis. Jangan menampilkan angka pace seolah-olah sudah bermakna.
  if (distanceKm < 0.3) {
    return const RunEvaluation(
      title: 'Data masih terbatas',
      overview: 'Sesi terlalu singkat untuk mengevaluasi pace.',
      observations: <String>[
        'Jarak terlalu pendek untuk membandingkan pace.',
      ],
      recommendations: <String>[
        'Coba rekam sesi yang lebih panjang agar pace bisa dibandingkan.',
      ],
    );
  }

  observations.add(
    'Kamu menempuh ${distanceKm.toStringAsFixed(2)} km dalam ${session.elapsedText}; waktu bergerak ${session.movingTimeText}.',
  );
  if (averagePace != null && averagePace.isFinite && averagePace > 0) {
    observations.add('Pace rata-rata ${session.averagePaceText}/km.');
  }

  if (paces.length >= 3) {
    final double fastest = paces.reduce((double a, double b) => a < b ? a : b);
    final double slowest = paces.reduce((double a, double b) => a > b ? a : b);
    final double spread = slowest - fastest;
    observations.add(
      'Pace split kilometer berada pada rentang ${_formatPace(fastest)}–${_formatPace(slowest)}/km; selisih tercepat dan terlambat ${_formatDurationSeconds(spread.round())}.',
    );
    final int splitIndex = math.max(1, paces.length ~/ 2).toInt();
    final double firstHalf = paces.take(splitIndex).reduce((double a, double b) => a + b) / splitIndex;
    final List<double> later = paces.skip(splitIndex).toList(growable: false);
    if (later.isNotEmpty) {
      final double laterAverage = later.reduce((double a, double b) => a + b) / later.length;
      final double drift = laterAverage - firstHalf;
      if (drift > 45) {
        observations.add('Paruh akhir lebih lambat sekitar ${_formatDurationSeconds(drift.round())}/km dibanding paruh awal.');
        recommendations.add('Coba mulai 1–2 kilometer pertama sedikit lebih santai dan tingkatkan usaha bertahap agar tenaga tersisa di akhir.');
      } else if (drift < -30) {
        observations.add('Pace bagian akhir lebih cepat daripada bagian awal.');
        recommendations.add('Pertahankan ritme bertahap jika terasa nyaman.');
      } else {
        observations.add('Pace bagian awal dan akhir relatif seimbang.');
        recommendations.add('Pertahankan ritme yang sama pada sesi serupa.');
      }
    }
  } else if (session.hundredMeterLaps.length >= 5) {
    final List<double> shortPaces = session.hundredMeterLaps
        .map((RunLap100m lap) => lap.paceSecondsPerKm)
        .whereType<double>()
        .where((double pace) => pace.isFinite && pace > 0 && pace <= 3600)
        .toList(growable: false);
    if (shortPaces.length >= 5) {
      final double fastest = shortPaces.reduce((double a, double b) => a < b ? a : b);
      final double slowest = shortPaces.reduce((double a, double b) => a > b ? a : b);
      observations.add('Pace segmen 100 m berada di rentang ${_formatPace(fastest)}–${_formatPace(slowest)}/km.');
      recommendations.add('Bandingkan beberapa segmen, jangan hanya satu segmen.');
    }
  } else {
    observations.add('Split yang tersedia belum cukup untuk menilai kestabilan ritme secara kuat.');
  }

  final RunElevationStats elevation = session.elevationStats;
  if (elevation.hasAltitudeData && elevation.totalAscentMeters >= 15) {
    observations.add('Elevasi +${elevation.totalAscentMeters.round()} m.');
    recommendations.add('Di rute menanjak, jaga usaha tetap stabil.');
  }

  if (session.averageCadenceSpm != null && session.averageCadenceSpm!.isFinite) {
    observations.add('Cadence rata-rata ${session.averageCadenceSpm!.round()} langkah/menit.');
    if (session.cadenceSamples.length >= 4) {
      final List<double> cadence = session.cadenceSamples.map((RunCadenceSample sample) => sample.cadenceSpm).toList(growable: false);
      final double mean = cadence.reduce((double a, double b) => a + b) / cadence.length;
      final double spread = cadence.reduce((double a, double b) => a > b ? a : b) - cadence.reduce((double a, double b) => a < b ? a : b);
      if (mean > 0 && spread / mean > 0.25) {
        recommendations.add('Jaga langkah tetap rileks, terutama saat mulai lelah.');
      }
    }
  }

  if (session.intervalPlan != null) {
    final IntervalRunPlan plan = session.intervalPlan!;
    if (plan.measure == IntervalMeasure.time) {
      observations.add('Interval waktu: ${plan.workSeconds} detik kerja, ${plan.recoverySeconds} detik pemulihan.');
    } else {
      observations.add('Interval jarak: ${plan.workDistanceMeters.round()} m kerja, ${plan.recoveryDistanceMeters.round()} m pemulihan.');
    }
    recommendations.add('Mulai repetisi dengan terkendali dan tambah usaha bertahap.');
  }

  if (recommendations.isEmpty) {
    recommendations.add('Bandingkan split dengan sesi berikutnya dan beri tubuh waktu pulih.');
  }

  return RunEvaluation(
    title: 'Evaluasi dan saran',
    overview: 'Ringkasan sesi.',
    observations: observations,
    recommendations: recommendations,
  );
}

String _formatPace(double secondsPerKm) {
  if (!secondsPerKm.isFinite || secondsPerKm <= 0 || secondsPerKm > 3600) return '--:--';
  final int seconds = secondsPerKm.round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

String _formatDurationSeconds(int seconds) {
  final int absolute = seconds.abs();
  return '${absolute ~/ 60}:${(absolute % 60).toString().padLeft(2, '0')}';
}
