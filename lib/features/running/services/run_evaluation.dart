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

/// Evaluasi deterministik dan offline. Tidak mengarang VO2max, kalori,
/// kesehatan, atau prediksi lomba dari data yang tidak tersedia.
RunEvaluation evaluateRun(RunSession session) {
  final List<String> observations = <String>[];
  final List<String> recommendations = <String>[];
  final int totalPoints = session.acceptedPoints + session.rejectedPoints;
  final double cleanRatio = totalPoints == 0
      ? 0.0
      : session.acceptedPoints / totalPoints;

  if (session.distanceMeters < 200) {
    observations.add('Sesi terlalu singkat untuk menilai pace secara stabil.');
    recommendations.add('Coba sesi berikutnya dengan durasi yang nyaman dan GPS yang sudah akurat.');
    return RunEvaluation(
      title: 'Data masih terbatas',
      overview: 'Simpan hasil ini sebagai catatan awal, bukan patokan performa.',
      observations: observations,
      recommendations: recommendations,
    );
  }

  observations.add('Jarak tercatat ${session.distanceKm.toStringAsFixed(2)} km dalam ${session.elapsedText}.');
  if (session.averagePaceSecondsPerKm != null) {
    observations.add('Pace rata-rata ${session.averagePaceText} menit/km.');
  } else {
    observations.add('Pace rata-rata belum tersedia karena jarak valid masih pendek.');
  }

  if (cleanRatio < 0.60) {
    observations.add('Banyak titik GPS ditolak atau tidak stabil; pace dan jarak bisa kurang akurat.');
    recommendations.add('Mulai di area terbuka dan tunggu akurasi GPS membaik sebelum berlari.');
  } else if (session.gpsAccuracyMeters != null && session.gpsAccuracyMeters! > 25) {
    observations.add('Akurasi GPS terakhir masih cukup kasar (${session.gpsAccuracyText}).');
    recommendations.add('Untuk sesi berikutnya, tunggu beberapa saat di area terbuka sebelum mulai.');
  } else {
    observations.add('Mayoritas titik GPS yang diproses lolos penyaringan.');
  }

  if (session.hundredMeterLaps.length >= 4) {
    final List<double> speeds = session.hundredMeterLaps
        .map((RunLap100m lap) => lap.speedKmh)
        .whereType<double>()
        .where((double speed) => speed.isFinite && speed > 0)
        .toList();
    if (speeds.length >= 4) {
      final double mean = speeds.reduce((double a, double b) => a + b) / speeds.length;
      final double fastest = speeds.reduce((double a, double b) => a > b ? a : b);
      final double slowest = speeds.reduce((double a, double b) => a < b ? a : b);
      final double spread = mean <= 0 ? 1 : (fastest - slowest) / mean;
      if (spread <= 0.25) {
        observations.add('Kecepatan segmen 100 m relatif konsisten menurut data GPS yang terkumpul.');
        recommendations.add('Pertahankan ritme yang terasa nyaman; tidak perlu mempercepat setiap segmen.');
      } else {
        observations.add('Kecepatan antarsegmen 100 m cukup bervariasi. Ini bisa dipengaruhi perubahan usaha, medan, atau noise GPS.');
        recommendations.add('Mulai lebih tenang dan gunakan split sebagai petunjuk, bukan penilaian mutlak.');
      }
    }
  } else {
    observations.add('Belum cukup segmen 100 m untuk menilai kestabilan kecepatan.');
  }

  final RunElevationStats elevation = session.elevationStats;
  if (elevation.hasAltitudeData) {
    observations.add(
      'Elevasi bersih ${elevation.netChangeMeters >= 0 ? '+' : ''}'
      '${elevation.netChangeMeters.toStringAsFixed(0)} m; total naik '
      '${elevation.totalAscentMeters.toStringAsFixed(0)} m dan turun '
      '${elevation.totalDescentMeters.toStringAsFixed(0)} m.',
    );
    observations.add(
      'Kenaikan maksimum dari titik awal: '
      '${elevation.maxAboveStartMeters.toStringAsFixed(0)} m.',
    );
    recommendations.add(
      'Gunakan data elevasi sebagai perkiraan medan. GPS ponsel bisa berisik, jadi jangan menilai usaha hanya dari angka elevasi.',
    );
  }

  if (session.intervalPlan != null) {
    final IntervalRunPlan plan = session.intervalPlan!;
    observations.add('Mode interval: ${plan.workSeconds} detik kerja, ${plan.recoverySeconds} detik pemulihan, ${plan.repetitions} ulangan direncanakan.');
    recommendations.add('Pada sesi interval, gunakan fase pemulihan untuk menurunkan usaha. Hentikan latihan jika terasa nyeri atau tidak aman.');
  }

  if (recommendations.isEmpty) {
    recommendations.add('Catat beberapa sesi lagi sebelum membandingkan tren. Utamakan peningkatan bertahap dan hari pemulihan.');
  }

  return RunEvaluation(
    title: session.distanceMeters >= 1000 ? 'Sesi berhasil direkam' : 'Sesi tercatat',
    overview: 'Evaluasi ini memakai data lokal dan perkiraan GPS. Ia bukan diagnosis kesehatan atau jaminan hasil lomba.',
    observations: observations,
    recommendations: recommendations,
  );
}
