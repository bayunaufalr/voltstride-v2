import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../running/models/run_session.dart';

/// Ringkasan kemampuan dan kebutuhan pemulihan dari data aktivitas tersimpan.
/// Angka pada kartu adalah perkiraan berbasis latihan, bukan penilaian medis.
class TrainingInsightsCard extends StatelessWidget {
  const TrainingInsightsCard({
    super.key,
    required this.sessions,
    required this.age,
  });

  final List<RunSession> sessions;
  final int? age;

  @override
  Widget build(BuildContext context) {
    final Color garis = Theme.of(context).dividerColor;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    final List<RunSession> lari = sessions
        .where((RunSession session) =>
            session.activityType == RunActivityType.run &&
            session.distanceKm >= 1 &&
            session.movingTime.inSeconds > 0)
        .toList(growable: false);
    final double? paceTerbaik = _paceTerbaik(lari);
    final double? cooperMeters = paceTerbaik == null
        ? null
        : (720 * 1000 / paceTerbaik);
    final double? vo2Cooper = cooperMeters == null
        ? null
        : ((cooperMeters - 504.9) / 44.73).clamp(0, 70).toDouble();
    final int? beepLevel = vo2Cooper == null || age == null
        ? null
        : _perkiraanBeepLevel(vo2Cooper, age!);
    final double? paceUntukPrediksi = _paceDariData(lari);
    final String prediksi24 = paceUntukPrediksi == null
        ? '--'
        : _formatDuration(
            (paceUntukPrediksi * 2.4).round(),
          );
    final int? indeksKemampuan = _indeksKemampuan(lari);
    final double beban7Hari = _bebanPadaRentang(
      sessions,
      DateTime.now().subtract(const Duration(days: 7)),
      DateTime.now(),
    );
    final double bebanSebelumnya = _bebanPadaRentang(
      sessions,
      DateTime.now().subtract(const Duration(days: 28)),
      DateTime.now().subtract(const Duration(days: 7)),
    ) / 3;
    final int indeksBeban = (100 * beban7Hari / (beban7Hari + 240))
        .round()
        .clamp(0, 100)
        .toInt();
    final int? indeksLelah = bebanSebelumnya <= 0
        ? null
        : (100 * beban7Hari / (bebanSebelumnya * 2))
            .round()
            .clamp(0, 100)
            .toInt();
    final RunSession? terbaru = sessions.isEmpty ? null : sessions.first;
    final int menitAktif = terbaru == null
        ? 0
        : (terbaru.movingTime > Duration.zero
                ? terbaru.movingTime
                : terbaru.elapsed)
            .inMinutes;
    final int airMinimum =
        math.max(150, (menitAktif / 60 * 400).round()).toInt();
    final int airMaksimum =
        math.max(250, (menitAktif / 60 * 800).round()).toInt();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Kondisi latihan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _barisNilai(
            context,
            judul: 'Indeks kemampuan lari',
            nilai: indeksKemampuan == null ? '--' : '$indeksKemampuan/100',
            progress: indeksKemampuan == null ? 0 : indeksKemampuan / 100,
            catatan: lari.isEmpty ? 'Belum cukup data lari.' : 'Dari jarak, pace, dan rutinitas latihan.',
          ),
          const SizedBox(height: 12),
          _barisNilai(
            context,
            judul: 'Beban latihan 7 hari',
            nilai: '$indeksBeban/100',
            progress: indeksBeban / 100,
            catatan: '${beban7Hari.round()} poin dalam 7 hari terakhir.',
          ),
          const SizedBox(height: 12),
          _barisNilai(
            context,
            judul: 'Indeks kelelahan',
            nilai: indeksLelah == null ? '--' : '$indeksLelah/100',
            progress: indeksLelah == null ? 0 : indeksLelah / 100,
            catatan: indeksLelah == null
                ? 'Belum cukup data pembanding.'
                : indeksLelah >= 70
                    ? 'Beban lebih tinggi dari kebiasaan sebelumnya.'
                    : 'Dihitung dari latihan tersimpan.',
          ),
          const SizedBox(height: 8),
          Text(
            'Skor ini berdasarkan data latihan, bukan ukuran medis.',
            style: TextStyle(fontSize: 11, color: teksSekunder),
          ),
          const Divider(height: 26),
          const Text(
            'Prediksi tes lari',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _barisTes(
            context,
            'Cooper test (perkiraan VO₂max)',
            vo2Cooper == null
                ? 'Belum cukup data'
                : '${vo2Cooper.toStringAsFixed(1)} ml/kg/menit',
          ),
          _barisTes(
            context,
            'Lari 12 menit',
            cooperMeters == null
                ? 'Belum cukup data'
                : '${(cooperMeters / 1000).toStringAsFixed(2)} km',
          ),
          _barisTes(
            context,
            'Beep test 20 m',
            beepLevel == null
                ? (age == null
                    ? 'Lengkapi tanggal lahir di profil'
                    : 'Belum cukup data')
                : 'Sekitar level $beepLevel',
          ),
          _barisTes(context, 'Lari 2,4 km', prediksi24),
          const SizedBox(height: 4),
          Text(
            'Perkiraan dari latihan tersimpan; hasil tes langsung bisa berbeda.',
            style: TextStyle(fontSize: 11, color: teksSekunder),
          ),
          const Divider(height: 26),
          const Text(
            'Setelah aktivitas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            terbaru == null
                ? 'Simpan aktivitas untuk melihat saran pemulihan.'
                : 'Perkiraan minum: $airMinimum–$airMaksimum ml berdasarkan durasi aktivitas terakhir.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Gizi: sertakan karbohidrat dan protein, misalnya nasi dengan telur/tempe serta buah.',
          ),
          const SizedBox(height: 6),
          Text(
            'Air dan gizi: perkiraan umum, bukan aturan medis.',
            style: TextStyle(fontSize: 11, color: teksSekunder),
          ),
        ],
      ),
    );
  }

  Widget _barisNilai(
    BuildContext context, {
    required String judul,
    required String nilai,
    required double progress,
    required String catatan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                judul,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 5),
        LinearProgressIndicator(
          value: progress.clamp(0, 1).toDouble(),
          minHeight: 5,
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        const SizedBox(height: 4),
        Text(
          catatan,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _barisTes(BuildContext context, String nama, String hasil) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(nama)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              hasil,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  double? _paceTerbaik(List<RunSession> lari) {
    final List<double> paces = lari
        .where((RunSession session) => session.distanceKm >= 2)
        .map((RunSession session) =>
            session.movingTime.inSeconds / session.distanceKm)
        .where((double pace) => pace.isFinite && pace >= 150 && pace <= 1200)
        .toList(growable: false);
    if (paces.isEmpty) return null;
    return paces.reduce((double a, double b) => math.min(a, b).toDouble());
  }

  double? _paceDariData(List<RunSession> lari) {
    if (lari.isEmpty) return null;
    final RunSession sesi = lari.reduce((RunSession a, RunSession b) {
      final double paceA = a.movingTime.inSeconds / a.distanceKm;
      final double paceB = b.movingTime.inSeconds / b.distanceKm;
      return paceA <= paceB ? a : b;
    });
    final double pace = sesi.movingTime.inSeconds / sesi.distanceKm;
    if (!pace.isFinite || pace <= 0 || pace > 1200) return null;
    return pace;
  }

  int? _indeksKemampuan(List<RunSession> lari) {
    if (lari.isEmpty) return null;
    final double jarakTerjauh = lari
        .map((RunSession sesi) => sesi.distanceKm)
        .reduce((double a, double b) => math.max(a, b).toDouble());
    final double bagianJarak =
        (jarakTerjauh / 21.1 * 35).clamp(0, 35).toDouble();
    final double? pace = _paceTerbaik(lari);
    final double bagianPace = pace == null
        ? 0
        : ((600 - pace) / 480 * 35).clamp(0, 35).toDouble();
    final DateTime mulai = DateTime.now().subtract(const Duration(days: 56));
    final Set<int> mingguAktif = lari
        .where((RunSession sesi) => sesi.startedAt.isAfter(mulai))
        .map((RunSession sesi) =>
            sesi.startedAt.difference(mulai).inDays ~/ 7)
        .toSet();
    final double bagianKonsistensi = mingguAktif.length / 8 * 30;
    return (bagianJarak + bagianPace + bagianKonsistensi)
        .round()
        .clamp(0, 100)
        .toInt();
  }

  int _perkiraanBeepLevel(double vo2, int ageYears) {
    // Ini hanya perkiraan kasar, bukan pengganti beep test langsung.
    final double penyebut = 3.238 + (0.1536 * ageYears);
    final double kecepatan =
        (vo2 - 31.025 + (3.248 * ageYears)) / penyebut;
    return (1 + ((kecepatan - 8.5) / 0.5).round())
        .clamp(1, 21)
        .toInt();
  }

  double _bebanPadaRentang(
    List<RunSession> data,
    DateTime mulai,
    DateTime selesai,
  ) {
    return data.where((RunSession session) {
      final DateTime waktu = session.startedAt.toLocal();
      return !waktu.isBefore(mulai) && waktu.isBefore(selesai);
    }).fold<double>(0, (double total, RunSession session) {
      final Duration waktuGerak = session.movingTime > Duration.zero
          ? session.movingTime
          : session.elapsed;
      final double pengali = session.activityType == RunActivityType.walk
          ? 0.65
          : (session.intervalPlan == null ? 1.0 : 1.3);
      final double menit = waktuGerak.inSeconds / 60.0;
      final double elevasi = session.elevationStats.totalAscentMeters / 20;
      return total + (menit * pengali) + elevasi;
    });
  }

  String _formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
