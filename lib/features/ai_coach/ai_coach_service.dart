import '../running/models/run_session.dart';

/// Pesan percakapan untuk menjaga antarmuka AiCoachPage tetap sederhana.
class AiCoachMessage {
  const AiCoachMessage({
    required this.role,
    required this.text,
  });

  final String role;
  final String text;

  Map<String, String> toJson() => <String, String>{
        'role': role,
        'text': text,
      };
}

/// Pelatih lokal VoltStride.
///
/// Semua respons dihitung di perangkat dari kata kunci, rumus pace, dan
/// ringkasan lari SQLite. Kelas ini tidak melakukan request internet dan tidak
/// membutuhkan API key. Ini bukan model bahasa generatif; cakupan jawabannya
/// sengaja dibatasi pada topik lari yang dapat ditangani dengan aturan jelas.
class AiCoachService {
  const AiCoachService();

  /// Tetap true agar UI chat lama dapat dipakai tanpa konfigurasi endpoint.
  static bool get isConfigured => true;

  Future<String> sendMessage({
    required List<AiCoachMessage> conversation,
    required List<RunSession> recentRuns,
    String languageCode = 'id',
  }) async {
    final bool english = languageCode == 'en';
    final List<AiCoachMessage> userMessages = conversation
        .where((AiCoachMessage message) => message.role == 'user')
        .toList(growable: false);

    if (userMessages.isEmpty) {
      return english
          ? 'Ask about running, pace, splits, training, or a race goal.'
          : 'Tulis pertanyaan tentang lari, pace, split, latihan, atau target lomba.';
    }

    String message = userMessages.last.text.trim();
    if (message.length < 18 && userMessages.length > 1) {
      message = '${userMessages[userMessages.length - 2].text} $message';
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
    return generateLocalReply(
      message: message,
      recentRuns: recentRuns,
      languageCode: languageCode,
    );
  }

  /// Fungsi publik tanpa UI agar logika dapat dites otomatis.
  String generateLocalReply({
    required String message,
    required List<RunSession> recentRuns,
    String languageCode = 'id',
  }) {
    final bool english = languageCode == 'en';
    final String text = message.toLowerCase().replaceAll('–', '-').trim();
    final List<RunSession> runs = List<RunSession>.of(recentRuns)
      ..sort((RunSession a, RunSession b) => b.startedAt.compareTo(a.startedAt));

    if (text.isEmpty) {
      return english
          ? 'Ask a question first. I can analyse saved runs, calculate a target pace, explain splits, and offer general training guidance.'
          : 'Tulis pertanyaan terlebih dahulu. Saya dapat menganalisis lari tersimpan, menghitung pace target, menjelaskan split, dan memberi saran latihan umum.';
    }

    if (_containsAny(text, <String>[
      'nyeri dada', 'sakit dada', 'pingsan', 'sesak napas',
      'susah bernapas', 'sulit bernapas', 'mau pingsan',
      'chest pain', 'faint', 'shortness of breath', 'trouble breathing',
    ])) {
      return english
          ? 'Stop exercising and tell a trusted adult. Chest pain, fainting, or breathing difficulty needs prompt assessment by a healthcare professional. Do not try to push through the session.'
          : 'Hentikan latihan sekarang dan minta bantuan orang dewasa tepercaya. Nyeri dada, pingsan, atau gangguan napas perlu dinilai tenaga kesehatan segera. Jangan mencoba memaksa diri menyelesaikan sesi.';
    }

    if (_containsAny(text, <String>[
      'cedera', 'nyeri', 'sakit lutut', 'sakit kaki', 'pergelangan sakit', 'terkilir',
      'injury', 'injured', 'knee pain', 'foot pain', 'ankle pain', 'sore',
    ])) {
      return english
          ? 'Do not push through pain. Stop movements that make it worse, tell a trusted adult, and seek advice from a healthcare professional if the pain persists, worsens, causes swelling, or affects walking. I cannot diagnose an injury from chat.'
          : 'Jangan memaksakan latihan saat nyeri. Hentikan gerakan yang memperburuk rasa sakit, beri tahu orang dewasa tepercaya, dan mintalah penilaian tenaga kesehatan jika nyeri menetap, memburuk, bengkak, atau mengganggu berjalan. Saya tidak bisa mendiagnosis cedera dari chat.';
    }

    final double? targetDistance = _extractDistanceKm(text);
    final bool mentionsGoal = _containsAny(text, <String>[
      'sub', 'under', 'below', 'target', 'rencana', 'lomba', 'race',
      'finish', 'estimasi waktu', 'berapa menit', 'goal', 'estimate time',
    ]);
    if ((targetDistance != null && mentionsGoal) ||
        (text.contains('sub') && targetDistance == null) ||
        (RegExp(r'\b(under|below)\s*\d').hasMatch(text) && targetDistance == null)) {
      return _buildRacePlan(text, targetDistance, english: english);
    }

    if (_containsAny(text, <String>[
      'analisis', 'analisa', 'lari terakhir', 'sesi terakhir', 'performa terakhir', 'hasil lari',
      'analyse', 'analyze', 'last run', 'latest run', 'last session', 'recent performance',
    ])) {
      return _analyzeLatestRun(runs, english: english);
    }

    if (_containsAny(text, <String>[
      'split', 'per kilometer', 'tiap km', 'per kilometre', 'per kilometer',
    ])) {
      return _explainSplits(runs, english: english);
    }

    if (_containsAny(text, <String>[
      'konsisten', 'konsistensi', 'progres', 'progress', 'minggu ini',
      'total lari', 'berapa kali lari', 'consistency', 'this week',
      'weekly distance', 'how many runs', 'progress',
    ])) {
      return _analyzeConsistency(runs, english: english);
    }

    if (_containsAny(text, <String>[
      'pace', 'kecepatan', 'lebih cepat', 'lari lambat', 'lari pelan',
      'speed', 'faster', 'slower', 'slow run',
    ])) {
      return _explainPace(runs, english: english);
    }

    if (_containsAny(text, <String>[
      'latihan', 'training', 'jadwal', 'program', 'meningkatkan',
      'menambah jarak', 'stamina', 'daya tahan', 'schedule', 'workout',
      'improve', 'endurance', 'build stamina',
    ])) {
      return _trainingAdvice(runs, english: english);
    }

    if (_containsAny(text, <String>[
      'istirahat', 'recovery', 'pemulihan', 'hidrasi', 'minum', 'tidur',
      'rest', 'hydration', 'drink', 'sleep',
    ])) {
      return english
          ? 'For general recovery, allow time to rest, get enough sleep, drink according to thirst and weather, and eat regular meals. Avoid back-to-back hard sessions if you still feel very tired. Individual needs differ, so this is general guidance rather than medical advice.'
          : 'Untuk pemulihan umum, beri tubuh waktu istirahat, tidur cukup, minum sesuai rasa haus dan kondisi cuaca, serta makan teratur. Hindari latihan intens berturut-turut jika tubuh masih terasa sangat lelah. Kebutuhan setiap orang berbeda; jangan jadikan saran ini sebagai diagnosis medis.';
    }

    if (runs.isEmpty) {
      return english
          ? 'I run locally on your device and could not find a saved run yet. After you finish and save a session, I can read its distance, duration, average pace, and splits. Try asking “Plan a 10K under 50 minutes”, “What does a 6:00/km pace mean?”, or “How should a beginner structure run training?”.'
          : 'Saya berjalan secara lokal dan belum menemukan sesi lari tersimpan. Setelah kamu menyelesaikan dan menyimpan satu sesi, saya bisa membaca jarak, durasi, pace rata-rata, serta splitnya. Untuk saat ini, coba tanyakan “Bantu rencanakan 10K sub-50”, “Apa arti pace 6:00/km?”, atau “Bagaimana cara menyusun latihan lari pemula?”.';
    }

    return english
        ? 'I can help with running questions that can be calculated from local data. ${_shortLatestSummary(runs.first, english: true)}\n\nTry a more specific question, such as “Analyse my last run”, “Explain my splits”, “How did I progress this week?”, or “Plan a 10K under 50 minutes”. I use a local rules-based engine, not a general-purpose service like ChatGPT.'
        : 'Saya bisa membantu pada topik lari yang dapat dihitung dari data lokal. ${_shortLatestSummary(runs.first)}\n\nCoba pertanyaan yang lebih spesifik, misalnya “Analisis lari terakhir saya”, “Jelaskan split saya”, “Bagaimana progres saya minggu ini?”, atau “Bantu rencanakan 10K sub-50”. Saya tidak memiliki pengetahuan bebas seluas ChatGPT karena respons dibuat dengan aturan lokal, tanpa layanan AI berbayar.';
  }

  String _buildRacePlan(String text, double? parsedDistance, {required bool english}) {
    double distanceKm = parsedDistance ?? 10.0;
    if (distanceKm <= 0 || distanceKm > 100) distanceKm = 10.0;

    final int? parsedTargetMinutes = _extractTargetMinutes(text);
    final int suggestedTargetMinutes;
    if (parsedTargetMinutes != null) {
      suggestedTargetMinutes = parsedTargetMinutes;
    } else if ((distanceKm - 5).abs() < 0.1) {
      suggestedTargetMinutes = 30;
    } else if ((distanceKm - 10).abs() < 0.1) {
      suggestedTargetMinutes = 50;
    } else if ((distanceKm - 21.1).abs() < 0.4 ||
        (distanceKm - 21).abs() < 0.4) {
      suggestedTargetMinutes = 120;
    } else {
      suggestedTargetMinutes = (distanceKm * 6).round();
    }

    final int targetMinutes = suggestedTargetMinutes.clamp(1, 24 * 60).toInt();
    final bool subGoal = RegExp(r'\b(sub|under|below)\s*-?\s*\d').hasMatch(text);
    final int targetTotalSeconds = targetMinutes * 60;
    final int desiredSeconds = subGoal && targetTotalSeconds > 20
        ? targetTotalSeconds - 20
        : targetTotalSeconds;
    final int paceSeconds = (desiredSeconds / distanceKm).round();
    final String distanceLabel = _distanceLabel(distanceKm);
    final String finishLabel = _formatDuration(desiredSeconds);
    final String paceLabel = '${_formatPace(paceSeconds)}/km';

    final StringBuffer result = StringBuffer();
    if (english) {
      result
        ..writeln('Goal plan: $distanceLabel')
        ..writeln('• Time target: ${subGoal ? 'under ' : 'around '}$targetMinutes min.')
        ..writeln('• Mathematical average pace: ${_formatPace((targetTotalSeconds / distanceKm).round())}/km.')
        ..writeln('• Training pace with a small buffer: about $paceLabel for an estimated finish of $finishLabel.')
        ..writeln()
        ..writeln('Example even splits:');
    } else {
      result
        ..writeln('Rencana target $distanceLabel')
        ..writeln('• Target waktu: ${subGoal ? 'di bawah ' : 'sekitar '}$targetMinutes menit.')
        ..writeln('• Pace rata-rata matematis: ${_formatPace((targetTotalSeconds / distanceKm).round())}/km.')
        ..writeln('• Target latihan dengan sedikit ruang: sekitar $paceLabel untuk perkiraan finish $finishLabel.')
        ..writeln()
        ..writeln('Contoh split rata yang mendekati target:');
    }

    final int wholeKm = distanceKm.floor().clamp(1, 10).toInt();
    for (int km = 1; km <= wholeKm; km++) {
      result.writeln('Km $km: ${_formatPace(paceSeconds)}');
    }
    if (distanceKm > wholeKm + 0.01) {
      final double remainder = distanceKm - wholeKm;
      final int remainderSeconds = (paceSeconds * remainder).round();
      result.writeln(english
          ? 'Final ${remainder.toStringAsFixed(2)} km: about ${_formatDuration(remainderSeconds)}.'
          : '${remainder.toStringAsFixed(2)} km terakhir: kira-kira ${_formatDuration(remainderSeconds)}.');
    }

    result
      ..writeln()
      ..writeln(english
          ? 'Note: this pace calculation is mathematical, not proof that the goal matches your current fitness. Compare it with real training results, start at a controlled effort, and do not force the pace if you feel unwell.'
          : 'Catatan: hitungan pace hanya matematika, bukan bukti bahwa target sudah sesuai kemampuanmu. Cocokkan dengan hasil latihan aktual, mulai dengan effort yang terkontrol, dan jangan memaksakan pace jika tubuh terasa tidak aman.');
    return result.toString().trim();
  }

  String _analyzeLatestRun(List<RunSession> runs, {required bool english}) {
    if (runs.isEmpty) {
      return english
          ? 'No saved run was found. Record a run from the Record tab and finish the session to save it to History. I can then analyse the recorded results.'
          : 'Belum ada sesi lari tersimpan. Rekam lari melalui tab Rekam dan tekan Selesai agar ringkasannya muncul di Riwayat. Setelah itu, saya bisa menganalisis hasil yang benar-benar tercatat.';
    }

    final RunSession run = runs.first;
    final StringBuffer result = StringBuffer();
    if (english) {
      result
        ..writeln('Latest run analysis')
        ..writeln('• Date: ${_formatDate(run.startedAt.toLocal())}')
        ..writeln('• Distance: ${run.distanceKm.toStringAsFixed(2)} km')
        ..writeln('• Total duration: ${_formatDuration(run.elapsed.inSeconds)}')
        ..writeln('• Moving time: ${_formatDuration(run.movingTime.inSeconds)}')
        ..writeln('• Average pace: ${_paceFromRun(run, english: true)}')
        ..writeln('• GPS points accepted/rejected: ${run.acceptedPoints}/${run.rejectedPoints}');
    } else {
      result
        ..writeln('Analisis sesi terakhir')
        ..writeln('• Tanggal: ${_formatDate(run.startedAt.toLocal())}')
        ..writeln('• Jarak: ${run.distanceKm.toStringAsFixed(2)} km')
        ..writeln('• Durasi total: ${_formatDuration(run.elapsed.inSeconds)}')
        ..writeln('• Waktu bergerak: ${_formatDuration(run.movingTime.inSeconds)}')
        ..writeln('• Pace rata-rata: ${_paceFromRun(run)}')
        ..writeln('• Titik GPS diterima/ditolak: ${run.acceptedPoints}/${run.rejectedPoints}');
    }

    final List<RunSplit> validSplits = run.splits
        .where((RunSplit split) => split.paceSecondsPerKm > 0 && split.paceSecondsPerKm <= 3600)
        .toList(growable: false);
    if (validSplits.length >= 2) {
      final RunSplit fastest = validSplits.reduce(
        (RunSplit a, RunSplit b) => a.paceSecondsPerKm <= b.paceSecondsPerKm ? a : b,
      );
      final RunSplit slowest = validSplits.reduce(
        (RunSplit a, RunSplit b) => a.paceSecondsPerKm >= b.paceSecondsPerKm ? a : b,
      );
      if (english) {
        result
          ..writeln('• Fastest split: km ${fastest.kilometer}, ${fastest.paceText}')
          ..writeln('• Slowest split: km ${slowest.kilometer}, ${slowest.paceText}')
          ..writeln('• Gap between the fastest and slowest split: ${_formatDuration(slowest.paceSecondsPerKm - fastest.paceSecondsPerKm)} per km');
      } else {
        result
          ..writeln('• Split tercepat: km ${fastest.kilometer}, ${fastest.paceText}')
          ..writeln('• Split terlambat: km ${slowest.kilometer}, ${slowest.paceText}')
          ..writeln('• Selisih antar split ekstrem: ${_formatDuration(slowest.paceSecondsPerKm - fastest.paceSecondsPerKm)} per km');
      }
    } else {
      result.writeln(english
          ? '• Splits: not enough complete 1 km splits to compare pace consistency.'
          : '• Split: belum cukup split 1 km lengkap untuk membandingkan kestabilan pace.');
    }

    if (run.distanceKm < 0.1) {
      result.writeln(english
          ? '\nThe distance is under 100 m, so the pace is not reliable enough to assess. GPS can fluctuate near buildings or trees.'
          : '\nJarak masih di bawah 100 m, jadi pace belum cukup kuat untuk dinilai. GPS dapat berfluktuasi, terutama di dekat gedung atau pepohonan.');
    } else {
      result.writeln(english
          ? '\nSuggestion: use this session as a baseline. Compare several runs in similar conditions before concluding that your performance has improved or declined.'
          : '\nSaran: gunakan sesi ini sebagai catatan dasar. Bandingkan beberapa sesi dengan jarak dan kondisi serupa sebelum menyimpulkan ada peningkatan atau penurunan performa.');
    }
    return result.toString();
  }

  String _explainSplits(List<RunSession> runs, {required bool english}) {
    if (runs.isEmpty) {
      return english
          ? 'Splits divide an activity into distance segments, commonly 1 km each. A split pace of 5:30/km means one kilometre took about 5 minutes 30 seconds. There are no saved splits to analyse yet.'
          : 'Split membagi aktivitas menjadi bagian jarak, biasanya setiap 1 km. Pace split 5:30/km artinya satu kilometer ditempuh sekitar 5 menit 30 detik. Belum ada split milikmu yang tersimpan untuk dianalisis.';
    }

    final RunSession run = runs.first;
    if (run.splits.isEmpty) {
      return english
          ? 'Your latest session of ${run.distanceKm.toStringAsFixed(2)} km has no complete 1 km splits yet. A split is the time for each distance segment; for example, 5:30/km means each kilometre takes about 5 minutes 30 seconds. A longer run with reliable GPS reception may produce more splits.'
          : 'Sesi terakhirmu sejauh ${run.distanceKm.toStringAsFixed(2)} km belum memiliki split 1 km yang lengkap. Split adalah durasi untuk tiap bagian jarak; misalnya 5:30/km berarti setiap kilometer membutuhkan sekitar 5 menit 30 detik. Rekam jarak yang lebih panjang di area dengan sinyal GPS baik untuk memperoleh lebih banyak split.';
    }

    final StringBuffer result = StringBuffer()
      ..writeln(english
          ? 'Splits from your latest ${run.distanceKm.toStringAsFixed(2)} km session:'
          : 'Split pada sesi terakhir (${run.distanceKm.toStringAsFixed(2)} km):');
    for (final RunSplit split in run.splits.take(10)) {
      result.writeln(english
          ? '• Km ${split.kilometer}: ${split.paceText}, duration ${_formatDuration(split.durationSeconds)}'
          : '• Km ${split.kilometer}: ${split.paceText}, durasi ${_formatDuration(split.durationSeconds)}');
    }
    result
      ..writeln()
      ..writeln(english
          ? 'A smaller time value means a faster pace. Large differences between kilometres can come from effort, terrain, stops, or GPS variation. Do not assume they directly represent a change in fitness.'
          : 'Pace yang angka waktunya lebih kecil berarti lebih cepat. Selisih besar antarkilometer bisa disebabkan perubahan usaha, medan, berhenti, atau variasi GPS. Jangan langsung menganggapnya sebagai perubahan kebugaran.');
    return result.toString();
  }

  String _explainPace(List<RunSession> runs, {required bool english}) {
    if (runs.isEmpty) {
      return english
          ? 'Pace is the time required to cover one kilometre, not speed in km/h. For example, 6:00/km means one kilometre takes six minutes. No saved pace data was found yet. Once you save a run, I can show the average pace from that session.'
          : 'Pace adalah waktu untuk menempuh satu kilometer, bukan kecepatan dalam km/jam. Contoh: 6:00/km berarti 1 km ditempuh dalam 6 menit. Belum ada data pace milikmu yang tersimpan. Setelah sesi lari tersimpan, saya bisa menampilkan pace rata-rata dari catatan tersebut.';
    }

    final RunSession run = runs.first;
    return english
        ? 'Your latest session: ${_paceFromRun(run, english: true)} over ${run.distanceKm.toStringAsFixed(2)} km in ${_formatDuration(run.elapsed.inSeconds)}.\n\nA pace of 5:00/km is faster than 6:00/km because each kilometre takes less time. If pace is unavailable or the distance is very short, do not judge your fitness from early GPS readings. Compare several similar sessions instead of relying on a single run.'
        : 'Pace pada sesi terakhirmu: ${_paceFromRun(run)} untuk jarak ${run.distanceKm.toStringAsFixed(2)} km dalam ${_formatDuration(run.elapsed.inSeconds)}.\n\nPace 5:00/km lebih cepat daripada 6:00/km karena waktu per kilometernya lebih pendek. Jika pace belum tersedia atau jarak masih sangat pendek, jangan menilai kemampuan dari angka GPS awal. Untuk mengetahui progres, bandingkan beberapa sesi serupa, bukan hanya satu lari.';
  }

  String _analyzeConsistency(List<RunSession> runs, {required bool english}) {
    if (runs.isEmpty) {
      return english
          ? 'There is no saved activity history to measure consistency yet. Save a few sessions first. I can then calculate the number of sessions and total distance from the available history.'
          : 'Belum ada riwayat aktivitas yang bisa digunakan untuk menghitung konsistensi. Simpan beberapa sesi lari terlebih dahulu. Setelah itu, saya bisa menghitung jumlah sesi dan total jarak berdasarkan riwayat akun yang tersedia.';
    }

    final DateTime now = DateTime.now();
    final DateTime weekStart = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    final List<RunSession> weekRuns = runs.where((RunSession run) {
      final DateTime date = run.startedAt.toLocal();
      return !date.isBefore(weekStart) && !date.isAfter(now);
    }).toList(growable: false);
    final double weeklyKm = weekRuns.fold<double>(
      0,
      (double total, RunSession run) => total + run.distanceKm,
    );
    final int allDistanceSessions = runs.length;

    return english
        ? 'Summary of the last 7 days from saved data:\n'
            '• Sessions: ${weekRuns.length}\n'
            '• Total distance: ${weeklyKm.toStringAsFixed(2)} km\n'
            '• Sessions available for analysis: $allDistanceSessions (up to the 8 most recent records loaded).\n\n'
            'These numbers include only workouts recorded in the app. Aim for a realistic schedule you can sustain, with recovery days, rather than making a large jump in distance.'
        : 'Ringkasan 7 hari terakhir berdasarkan data tersimpan:\n'
            '• Jumlah sesi: ${weekRuns.length}\n'
            '• Total jarak: ${weeklyKm.toStringAsFixed(2)} km\n'
            '• Sesi yang tersedia untuk analisis: $allDistanceSessions (maksimal 8 catatan terbaru yang dimuat).\n\n'
            'Angka ini hanya mencakup latihan yang tercatat di aplikasi, bukan aktivitas yang lupa direkam. Untuk konsistensi, prioritaskan jadwal realistis yang dapat dipertahankan dan hari pemulihan, bukan menambah jarak besar sekaligus.';
  }

  String _trainingAdvice(List<RunSession> runs, {required bool english}) {
    if (runs.isEmpty) {
      return english
          ? 'To get started, choose a comfortable run-walk duration, warm up gently, and finish with an easy walk. Begin with a schedule you can repeat, include rest days, and increase duration gradually. After a few sessions are saved, I can use your actual distance and pace to make the guidance more relevant.'
          : 'Untuk memulai, pilih durasi lari-jalan yang terasa nyaman, lakukan pemanasan ringan, dan akhiri dengan jalan pelan. Mulailah dari jadwal yang mudah diulang, sisipkan hari istirahat, lalu tambah durasi secara bertahap. Setelah beberapa sesi tersimpan, saya bisa menggunakan jarak dan pace aktual untuk membuat saran yang lebih relevan.';
    }

    final RunSession latest = runs.first;
    final String pace = _paceFromRun(latest, english: english);
    final String recentData = english
        ? 'Your latest session covered ${latest.distanceKm.toStringAsFixed(2)} km at an average pace of $pace.'
        : 'Sesi terakhir tercatat ${latest.distanceKm.toStringAsFixed(2)} km dengan pace rata-rata $pace.';
    final int daysSince = DateTime.now().difference(latest.startedAt.toLocal()).inDays;

    if (daysSince <= 1) {
      if (english) {
        return '$recentData Since that run was ${daysSince == 0 ? 'today' : 'yesterday'}, consider resting or choosing a very easy activity if your legs still feel tired. The next session does not need to be faster.\n\nIf you feel recovered, try an easy run at an effort where you can speak in full sentences. Add faster sessions only after your base and recovery are consistent.';
      }
      return '$recentData Karena lari terakhir baru dilakukan ${daysSince == 0 ? 'hari ini' : 'kemarin'}, pilih istirahat atau aktivitas sangat ringan bila kaki masih lelah. Sesi berikutnya tidak harus lebih cepat.\n\nJika terasa pulih, lakukan lari mudah pada effort yang masih memungkinkanmu berbicara dengan kalimat lengkap. Tambahkan latihan cepat hanya setelah dasar dan pemulihan terasa baik.';
    }

    return english
        ? '$recentData\n\nSuggested next session: an easy run at an effort where you can speak in full sentences. Prioritise a sustainable duration rather than chasing your fastest pace. Increase volume gradually, include recovery days, and stop if concerning symptoms occur.'
        : '$recentData\n\nSaran sesi berikutnya: lakukan lari mudah dengan effort yang masih memungkinkanmu berbicara dalam kalimat lengkap. Utamakan durasi yang dapat dipertahankan, bukan mengejar pace tercepat. Naikkan volume sedikit demi sedikit, beri hari pemulihan, dan hentikan sesi bila muncul gejala yang mengkhawatirkan.';
  }

  String _shortLatestSummary(RunSession run, {bool english = false}) {
    return english
        ? 'Latest session: ${run.distanceKm.toStringAsFixed(2)} km, duration ${_formatDuration(run.elapsed.inSeconds)}, pace ${_paceFromRun(run, english: true)}.'
        : 'Sesi terakhir: ${run.distanceKm.toStringAsFixed(2)} km, durasi ${_formatDuration(run.elapsed.inSeconds)}, pace ${_paceFromRun(run)}.';
  }

  String _paceFromRun(RunSession run, {bool english = false}) {
    final double? pace = run.averagePaceSecondsPerKm;
    if (pace == null || !pace.isFinite || pace <= 0 || pace > 3600 || run.distanceKm < 0.1) {
      return english ? 'not available yet' : 'belum tersedia';
    }
    return '${_formatPace(pace.round())}/km';
  }

  double? _extractDistanceKm(String text) {
    final RegExpMatch? match = RegExp(r'(\d+(?:[.,]\d+)?)\s*(km|k)\b').firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!.replaceAll(',', '.'));
  }

  int? _extractTargetMinutes(String text) {
    final RegExpMatch? subMatch = RegExp(r'\b(?:sub|under|below)\s*-?\s*(\d{1,3})\b').firstMatch(text);
    if (subMatch != null) return int.tryParse(subMatch.group(1)!);

    final RegExpMatch? minuteMatch = RegExp(
      r'(\d{1,3})\s*(?:menit|mnt|minutes?|mins?)\b',
    ).firstMatch(text);
    if (minuteMatch != null) return int.tryParse(minuteMatch.group(1)!);

    final RegExpMatch? timeMatch = RegExp(r'\b(\d{1,2}):(\d{2})\b').firstMatch(text);
    if (timeMatch != null) {
      final int minutes = int.tryParse(timeMatch.group(1)!) ?? 0;
      final int seconds = int.tryParse(timeMatch.group(2)!) ?? 0;
      if (seconds < 60) return minutes + (seconds / 60).round();
    }
    return null;
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((String keyword) => text.contains(keyword));
  }

  String _formatPace(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int totalSeconds) {
    final int safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
    final int hours = safeSeconds ~/ 3600;
    final int minutes = (safeSeconds % 3600) ~/ 60;
    final int seconds = safeSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime value) {
    final String day = value.day.toString().padLeft(2, '0');
    final String month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _distanceLabel(double distanceKm) {
    if (distanceKm == distanceKm.roundToDouble()) {
      return '${distanceKm.toInt()} km';
    }
    return '${distanceKm.toStringAsFixed(2)} km';
  }
}
