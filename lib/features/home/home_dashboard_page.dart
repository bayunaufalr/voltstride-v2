import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../../services/app_language_service.dart';
import '../running/models/run_session.dart';
import '../running/run_route_map_view.dart';
import '../running/run_detail_page.dart';
import '../running/services/run_history_repository.dart';

class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({
    super.key,
    required this.onRecord,
    required this.onHistory,
  });

  final VoidCallback onRecord;
  final VoidCallback onHistory;

  @override
  State<HomeDashboardPage> createState() => HomeDashboardPageState();
}

class HomeDashboardPageState extends State<HomeDashboardPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);
  Future<List<RunSession>> _sessionsFuture =
      RunHistoryRepository.instance.getAll();

  Future<void> reload() async {
    final Future<List<RunSession>> value =
        RunHistoryRepository.instance.getAll();
    if (mounted) setState(() => _sessionsFuture = value);
    try {
      await value;
    } catch (_) {
      // FutureBuilder menampilkan keadaan saat data belum bisa dibaca.
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
                  _sectionHeader(_text('Aktivitas terbaru', 'Recent activity'), _text('Lihat semua', 'View all'), widget.onHistory),
                  const SizedBox(height: 12),
                  if (sorted.isEmpty)
                    _emptyActivity()
                  else
                    ...sorted.take(3).map(_activityCard),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        _text('Beranda', 'Home'),
        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _weeklyRhythm(List<RunSession> sessions, DateTime now) {
    final Set<String> active = sessions
        .map((RunSession item) => _dayKey(item.startedAt.toLocal()))
        .toSet();
    final List<String> names = Localizations.localeOf(context).languageCode == 'en'
        ? <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : <String>['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    final DateTime monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text(_text('Aktivitas minggu ini', 'Activity this week'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
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
                    Text(names[index], style: TextStyle(color: Theme.of(context).hintColor, fontSize: 11)),
                    const SizedBox(height: 8),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: done ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: today ? Border.all(color: VoltWarna.teksPutih, width: 1.5) : null,
                      ),
                      child: done
                          ? Icon(Icons.check_rounded, color: Theme.of(context).colorScheme.surface, size: 19)
                          : Text('${date.day}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _weeklySummary(double distanceKm, Duration duration, double ascent) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _metricCard(_text('Jarak', 'Distance'), '${distanceKm.toStringAsFixed(2)} km'),
        ),
        const SizedBox(width: 8),
        Expanded(child: _metricCard(_text('Waktu gerak', 'Moving time'), _shortDuration(duration))),
        const SizedBox(width: 8),
        Expanded(child: _metricCard(_text('Elevasi', 'Elevation'), '+${ascent.round()} m')),
      ],
    );
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _recordButton() {
    return OutlinedButton(
      onPressed: widget.onRecord,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        side: BorderSide(color: Theme.of(context).colorScheme.onSurface, width: 1.2),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.add_rounded, size: 27),
          const SizedBox(width: 10),
          Text(_text('Rekam aktivitas', 'Record activity'), style: const TextStyle(fontSize: 16)),
          const Spacer(),
          const Icon(Icons.chevron_right),
        ],
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

  String _activityLabel(RunSession session) {
    if (session.activityType == RunActivityType.walk) return _text('Berjalan', 'Walk');
    if (session.intervalPlan != null) return _text('Lari interval', 'Interval run');
    return _text('Lari', 'Run');
  }

  String _environmentLabel(RunSession session) =>
      session.environment == RunEnvironment.outdoor
          ? _text('Luar ruangan', 'Outdoor')
          : _text('Dalam ruangan', 'Indoor');

  Widget _activityCard(RunSession session) {
    final String date = '${session.startedAt.toLocal().day.toString().padLeft(2, '0')}/'
        '${session.startedAt.toLocal().month.toString().padLeft(2, '0')}/'
        '${session.startedAt.toLocal().year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => RunDetailPage(session: session),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${_activityLabel(session)} • ${_environmentLabel(session)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(date, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
                if (session.route.length > 1) ...<Widget>[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: IgnorePointer(
                      child: RunRouteMapView(
                        key: ValueKey<String>('home-map-${session.startedAt.toIso8601String()}'),
                        route: session.route,
                        laps: const <RunLap100m>[],
                        height: 150,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    _activityMetric(session.distanceText, _text('km', 'km')),
                    _activityMetric(session.elapsedText, _text('waktu', 'time')),
                    _activityMetric(session.averagePaceText, _text('pace/km', 'pace/km')),
                    if (session.elevationStats.hasAltitudeData)
                      _activityMetric('+${session.elevationStats.totalAscentMeters.round()} m', _text('Elevasi', 'Elevation')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityMetric(String value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900))),
          Text(label, style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
        ],
      ),
    );
  }

  Widget _emptyActivity() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: <Widget>[
          Text(
            _text('Belum ada aktivitas.', 'No activities yet.'),
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            _text('Aktivitas selesai akan muncul di sini.', 'Completed activities will appear here.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).hintColor,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_text('Riwayat belum dapat dimuat.', 'Activity history could not be loaded.')),
              const SizedBox(height: 12),
              FilledButton(onPressed: reload, child: Text(_text('Coba lagi', 'Try again'))),
            ],
          ),
        ),
      );

  String _dayKey(DateTime value) => '${value.year}-${value.month}-${value.day}';

  String _shortDuration(Duration value) {
    if (value.inHours > 0) {
      final String jam = Localizations.localeOf(context).languageCode == 'en' ? 'h' : 'j';
      final String menit = Localizations.localeOf(context).languageCode == 'en' ? 'min' : 'm';
      return '${value.inHours}$jam ${value.inMinutes.remainder(60)}$menit';
    }
    if (value.inMinutes > 0) {
      final String unit = Localizations.localeOf(context).languageCode == 'en' ? 'min' : 'm';
      return '${value.inMinutes}$unit';
    }
    return Localizations.localeOf(context).languageCode == 'en'
        ? '${value.inSeconds}s'
        : '${value.inSeconds}d';
  }
}
