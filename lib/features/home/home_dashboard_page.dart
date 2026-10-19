import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../running/models/run_session.dart';
import '../running/run_route_map_view.dart';
import '../running/services/run_history_repository.dart';

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({
    super.key,
    required this.onRecord,
    required this.onHistory,
    required this.onProgress,
  });

  final VoidCallback onRecord;
  final VoidCallback onHistory;
  final VoidCallback onProgress;

  @override
  State<HomeDashboardPage> createState() => HomeDashboardPageState();
}

class HomeDashboardPageState extends State<HomeDashboardPage> {
  Future<List<RunSession>> _sessionsFuture =
      RunHistoryRepository.instance.getAll();

  Future<void> reload() async {
    final Future<List<RunSession>> value =
        RunHistoryRepository.instance.getAll();
    if (mounted) setState(() => _sessionsFuture = value);
    try {
      await value;
    } catch (_) {
      // FutureBuilder displays the error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<RunSession>>(
          future: _sessionsFuture,
          builder: (BuildContext context,
              AsyncSnapshot<List<RunSession>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _errorView();
            }
            final List<RunSession> sessions =
                snapshot.data ?? <RunSession>[];
            final DateTime now = DateTime.now();
            final DateTime monday = DateTime(now.year, now.month, now.day)
                .subtract(Duration(days: now.weekday - 1));
            final List<RunSession> week = sessions
                .where((RunSession item) =>
                    !item.startedAt.isBefore(monday) &&
                    item.startedAt.isBefore(monday.add(const Duration(days: 7)))
                )
                .toList(growable: false);
            final double distanceKm = week.fold<double>(
                0, (double total, RunSession item) => total + item.distanceKm);
            final Duration duration = week.fold<Duration>(
                Duration.zero,
                (Duration total, RunSession item) => total + item.movingTime);
            final double ascent = week.fold<double>(
              0,
              (double total, RunSession item) =>
                  total + item.elevationStats.totalAscentMeters,
            );
            final List<RunSession> sorted = List<RunSession>.of(sessions)
              ..sort((RunSession a, RunSession b) =>
                  b.startedAt.compareTo(a.startedAt));
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: <Widget>[
                  _header(),
                  const SizedBox(height: 20),
                  _weeklyRhythm(week, now),
                  const SizedBox(height: 16),
                  _weeklySummary(distanceKm, duration, ascent),
                  const SizedBox(height: 18),
                  _recordButton(),
                  const SizedBox(height: 24),
                  _sectionHeader('Aktivitas terbaru', 'Lihat semua', widget.onHistory),
                  const SizedBox(height: 12),
                  if (sorted.isEmpty)
                    _emptyActivity()
                  else
                    ...sorted.take(3).map(_activityCard),
                  const SizedBox(height: 18),
                  _progressLink(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: <Color>[VoltWarna.aksen, VoltWarna.violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.bolt_rounded, color: VoltWarna.latar, size: 29),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('VoltStride', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              Text('Gerak hari ini, progres berikutnya.', style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Kemajuan pribadi',
          onPressed: widget.onProgress,
          icon: const Icon(Icons.insights_rounded),
        ),
      ],
    );
  }

  Widget _weeklyRhythm(List<RunSession> sessions, DateTime now) {
    final Set<String> active = sessions
        .map((RunSession item) => _dayKey(item.startedAt.toLocal()))
        .toSet();
    const List<String> names = <String>['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final DateTime monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final int activeDays = active.length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: Text('Ritme minggu ini', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
              Text('$activeDays/7 hari', style: const TextStyle(color: VoltWarna.aksen, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List<Widget>.generate(7, (int index) {
              final DateTime date = monday.add(Duration(days: index));
              final bool done = active.contains(_dayKey(date));
              final bool today = date.year == now.year && date.month == now.month && date.day == now.day;
              return Expanded(
                child: Column(
                  children: <Widget>[
                    Text(names[index], style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11)),
                    const SizedBox(height: 8),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? VoltWarna.aksen : VoltWarna.surface,
                        border: today ? Border.all(color: VoltWarna.teksPutih, width: 1.5) : null,
                      ),
                      child: done
                          ? const Icon(Icons.check_rounded, color: VoltWarna.latar, size: 19)
                          : Text('${date.day}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 13),
          Text(
            activeDays == 0
                ? 'Belum ada aktivitas minggu ini. Mulai dari sesi yang nyaman.'
                : 'Konsistensi dibangun dari latihan yang bisa kamu ulangi.',
            style: const TextStyle(color: VoltWarna.teksAbu, height: 1.35, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _weeklySummary(double distanceKm, Duration duration, double ascent) {
    return Row(
      children: <Widget>[
        Expanded(child: _metricCard('Jarak', '${distanceKm.toStringAsFixed(2)} km', Icons.route_rounded)),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Waktu gerak', _shortDuration(duration), Icons.timer_outlined)),
        const SizedBox(width: 10),
        Expanded(child: _metricCard('Naik', '${ascent.round()} m', Icons.trending_up_rounded)),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: VoltWarna.aksen, size: 18),
          const SizedBox(height: 12),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _recordButton() {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: widget.onRecord,
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            colors: <Color>[VoltWarna.aksen, Color(0xFF76D4FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x3338BDF8), blurRadius: 22, offset: Offset(0, 8)),
          ],
        ),
        child: const Row(
          children: <Widget>[
            Icon(Icons.radio_button_checked_rounded, color: VoltWarna.latar, size: 32),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Rekam aktivitas', style: TextStyle(color: VoltWarna.latar, fontSize: 18, fontWeight: FontWeight.w900)),
                  SizedBox(height: 3),
                  Text('Lari, interval, atau berjalan', style: TextStyle(color: VoltWarna.latar, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: VoltWarna.latar),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String action, VoidCallback onTap) {
    return Row(
      children: <Widget>[
        Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }

  Widget _activityCard(RunSession session) {
    final String date = '${session.startedAt.day.toString().padLeft(2, '0')}/'
        '${session.startedAt.month.toString().padLeft(2, '0')}/'
        '${session.startedAt.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VoltWarna.kartu,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VoltWarna.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: VoltWarna.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(session.activityType == RunActivityType.walk ? Icons.directions_walk_rounded : Icons.directions_run_rounded, color: VoltWarna.aksen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('${session.displayLabel} • ${session.environment.label}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(date, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: VoltWarna.teksAbu),
            ],
          ),
          if (session.route.length > 1) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: RunRouteMapView(
                key: ValueKey<String>('home-map-${session.startedAt.toIso8601String()}'),
                route: session.route,
                laps: const <RunLap100m>[],
                height: 150,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _activityMetric(session.distanceText, 'km'),
              _activityMetric(session.elapsedText, 'waktu'),
              _activityMetric(session.averagePaceText, 'pace/km'),
              if (session.elevationStats.hasAltitudeData)
                _activityMetric('${session.elevationStats.totalAscentMeters.round()}', 'naik m'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _activityMetric(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          Text(label, style: const TextStyle(fontSize: 10, color: VoltWarna.teksAbu)),
        ],
      ),
    );
  }

  Widget _emptyActivity() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: VoltWarna.kartu, borderRadius: BorderRadius.circular(20), border: Border.all(color: VoltWarna.border)),
      child: const Column(
        children: <Widget>[
          Icon(Icons.route_outlined, size: 38, color: VoltWarna.teksAbu),
          SizedBox(height: 10),
          Text('Aktivitas pertama menunggu dimulai', style: TextStyle(fontWeight: FontWeight.w800)),
          SizedBox(height: 5),
          Text('Selesai merekam sesi untuk melihat peta dan ringkasannya di sini.', textAlign: TextAlign.center, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _progressLink() {
    return OutlinedButton.icon(
      onPressed: widget.onProgress,
      icon: const Icon(Icons.insights_rounded),
      label: const Text('Lihat kemajuan dan rekor pribadi'),
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('Riwayat belum dapat dimuat.'),
              const SizedBox(height: 12),
              FilledButton(onPressed: reload, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );

  String _dayKey(DateTime value) => '${value.year}-${value.month}-${value.day}';

  String _shortDuration(Duration value) {
    if (value.inHours > 0) return '${value.inHours}j ${value.inMinutes.remainder(60)}m';
    if (value.inMinutes > 0) return '${value.inMinutes}m';
    return '${value.inSeconds}d';
  }
}
