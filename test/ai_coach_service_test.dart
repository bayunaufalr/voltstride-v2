import 'package:flutter_test/flutter_test.dart';
import 'package:voltstride/features/ai_coach/ai_coach_service.dart';
import 'package:voltstride/features/running/models/run_session.dart';

void main() {
  const AiCoachService service = AiCoachService();

  RunSession sampleRun({
    DateTime? startedAt,
    double distanceMeters = 5000,
    int elapsedSeconds = 1800,
    double? paceSecondsPerKm = 360,
    List<RunSplit> splits = const <RunSplit>[],
  }) {
    return RunSession(
      startedAt: startedAt ?? DateTime(2026, 10, 8, 6),
      finishedAt: DateTime(2026, 10, 8, 6, 30),
      distanceMeters: distanceMeters,
      elapsed: Duration(seconds: elapsedSeconds),
      movingTime: Duration(seconds: elapsedSeconds),
      averagePaceSecondsPerKm: paceSecondsPerKm,
      currentPaceSecondsPerKm: null,
      gpsAccuracyMeters: 8,
      acceptedPoints: 42,
      rejectedPoints: 2,
      route: const <RunPoint>[],
      splits: splits,
    );
  }

  group('AiCoachService lokal', () {
    test('rencana 10K sub-50 dihitung tanpa endpoint eksternal', () {
      final String reply = service.generateLocalReply(
        message: 'Bantu rencanakan 10K sub-50',
        recentRuns: const <RunSession>[],
      );

      expect(reply, contains('Target waktu: di bawah 50 menit'));
      expect(reply, contains('4:58/km'));
      expect(reply, contains('49:40'));
    });

    test('memberi tahu jika belum ada sesi tersimpan', () {
      final String reply = service.generateLocalReply(
        message: 'Analisis lari terakhir saya',
        recentRuns: const <RunSession>[],
      );

      expect(reply, contains('Belum ada sesi lari tersimpan'));
    });

    test('menganalisis jarak dan pace sesi terbaru', () {
      final String reply = service.generateLocalReply(
        message: 'Analisis lari terakhir saya',
        recentRuns: <RunSession>[
          sampleRun(distanceMeters: 5000, paceSecondsPerKm: 360),
        ],
      );

      expect(reply, contains('5.00 km'));
      expect(reply, contains('6:00/km'));
      expect(reply, contains('Titik GPS diterima/ditolak: 42/2'));
    });

    test('menjelaskan split tersimpan', () {
      final String reply = service.generateLocalReply(
        message: 'Jelaskan split saya',
        recentRuns: <RunSession>[
          sampleRun(
            splits: const <RunSplit>[
              RunSplit(
                kilometer: 1,
                durationSeconds: 350,
                paceSecondsPerKm: 350,
                distanceMeters: 1000,
              ),
            ],
          ),
        ],
      );

      expect(reply, contains('Km 1'));
      expect(reply, contains('5:50/km'));
    });

    test('mengutamakan keselamatan untuk gejala serius', () {
      final String reply = service.generateLocalReply(
        message: 'Saya sesak napas saat berlari',
        recentRuns: const <RunSession>[],
      );

      expect(reply, contains('Hentikan latihan sekarang'));
    });
  });
}
