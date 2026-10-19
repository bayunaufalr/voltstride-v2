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
      overview: 'Sesi ini terlalu singkat untuk memberi evaluasi performa yang dapat diandalkan.',
      observations: <String>[
        'Durasi dan jarak awal berhasil dicatat. Data yang ada belum cukup untuk menilai ritme secara andal.',
      ],
      recommendations: <String>[
        'Pada sesi berikutnya, mulai dengan pemanasan ringan lalu jaga ritme yang nyaman sebelum mengejar kecepatan.',
      ],
    );
  }

  observations.add(
    'Kamu menempuh ${distanceKm.toStringAsFixed(2)} km dalam ${session.elapsedText}; waktu bergerak ${session.movingTimeText}.',
  );
  if (averagePace != null && averagePace.isFinite && averagePace > 0) {
    observations.add('Pace rata-rata sesi ini ${session.averagePaceText}/km. Gunakan angka ini sebagai patokan pribadi, bukan target wajib pada setiap lari.');
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
        observations.add('Pace pada bagian akhir lebih cepat daripada bagian awal; kamu menambah usaha menjelang selesai.');
        recommendations.add('Pertahankan pola bertahap ini jika terasa nyaman, dan tetap sisakan tenaga untuk menyelesaikan sesi tanpa memaksakan diri.');
      } else {
        observations.add('Pace paruh awal dan akhir relatif seimbang berdasarkan split yang terekam.');
        recommendations.add('Pertahankan awal yang terkendali dan gunakan split sebagai panduan ritme, bukan alasan untuk memaksa pace pada setiap kilometer.');
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
      observations.add('Pace segmen pendek bervariasi dari ${_formatPace(fastest)} sampai ${_formatPace(slowest)}/km; angka 100 m lebih mudah terpengaruh noise GPS daripada split panjang.');
      recommendations.add('Jangan mengubah kecepatan karena satu segmen pendek. Periksa tren beberapa menit atau split kilometer.');
    }
  } else {
    observations.add('Split yang tersedia belum cukup untuk menilai kestabilan ritme secara kuat.');
  }

  final RunElevationStats elevation = session.elevationStats;
  if (elevation.hasAltitudeData && elevation.totalAscentMeters >= 15) {
    observations.add('Rute memiliki perkiraan kenaikan ${elevation.totalAscentMeters.round()} m. Tanjakan dapat membuat pace melambat meski usaha terasa sama.');
    recommendations.add('Pada rute menanjak, jaga usaha dan langkah tetap nyaman; jangan memaksa pace datar saat sedang menanjak.');
  }

  if (session.averageCadenceSpm != null && session.averageCadenceSpm!.isFinite) {
    observations.add('Cadence rata-rata perangkat sekitar ${session.averageCadenceSpm!.round()} langkah/menit. Angka ini hanya perkiraan sensor ponsel dan bukan standar yang wajib dikejar.');
    if (session.cadenceSamples.length >= 4) {
      final List<double> cadence = session.cadenceSamples.map((RunCadenceSample sample) => sample.cadenceSpm).toList(growable: false);
      final double mean = cadence.reduce((double a, double b) => a + b) / cadence.length;
      final double spread = cadence.reduce((double a, double b) => a > b ? a : b) - cadence.reduce((double a, double b) => a < b ? a : b);
      if (mean > 0 && spread / mean > 0.25) {
        recommendations.add('Perhatikan apakah langkah berubah karena lelah atau medan. Utamakan langkah yang rileks dan nyaman, bukan mengejar angka cadence tertentu.');
      }
    }
  }

  if (session.intervalPlan != null) {
    final IntervalRunPlan plan = session.intervalPlan!;
    if (plan.measure == IntervalMeasure.time) {
      observations.add('Kamu memakai interval berbasis waktu: ${plan.workSeconds} detik kerja dan ${plan.recoverySeconds} detik pemulihan selama ${plan.repetitions} ulangan yang direncanakan.');
    } else {
      observations.add('Kamu memakai interval berbasis jarak: ${plan.workDistanceMeters.round()} m kerja dan ${plan.recoveryDistanceMeters.round()} m pemulihan selama ${plan.repetitions} ulangan yang direncanakan.');
    }
    recommendations.add('Pada sesi berikutnya, mulai repetisi pertama dengan kendali dan gunakan pemulihan untuk menurunkan usaha. Tambah beban secara bertahap, bukan sekaligus.');
  }

  if (recommendations.isEmpty) {
    recommendations.add('Catat beberapa sesi dengan kondisi serupa, bandingkan split, lalu ubah satu hal kecil dalam latihan. Beri tubuh waktu pulih di antara sesi.');
  }

  return RunEvaluation(
    title: 'Yang bisa ditingkatkan',
    overview: 'Gunakan hasil ini untuk memilih satu hal yang realistis diperbaiki pada sesi berikutnya. Pace yang nyaman dan pemulihan tetap lebih penting daripada mengejar angka setiap kali berlari.',
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
