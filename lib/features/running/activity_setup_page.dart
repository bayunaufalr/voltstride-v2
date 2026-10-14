import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/lokasi_service.dart';
import '../../theme/volt_theme.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';

class ActivityStartConfig {
  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? intervalPlan;

  const ActivityStartConfig({
    required this.activityType,
    required this.environment,
    required this.intervalPlan,
  });
}

enum _ActivityMode { run, interval, walk }

class ActivitySetupPage extends StatefulWidget {
  const ActivitySetupPage({super.key, required this.onStart});

  final ValueChanged<ActivityStartConfig> onStart;

  @override
  State<ActivitySetupPage> createState() => ActivitySetupPageState();
}

class ActivitySetupPageState extends State<ActivitySetupPage> {
  RunEnvironment _environment = RunEnvironment.outdoor;
  _ActivityMode _mode = _ActivityMode.run;
  RunPoint? _currentLocation;
  bool _loadingLocation = false;
  String? _locationMessage;

  final TextEditingController _workSeconds = TextEditingController(text: '60');
  final TextEditingController _recoverySeconds = TextEditingController(text: '90');
  final TextEditingController _repetitions = TextEditingController(text: '6');

  @override
  void dispose() {
    _workSeconds.dispose();
    _recoverySeconds.dispose();
    _repetitions.dispose();
    super.dispose();
  }

  Future<void> loadLocation() async {
    if (_environment == RunEnvironment.indoor || _loadingLocation) return;
    setState(() {
      _loadingLocation = true;
      _locationMessage = null;
    });
    try {
      final bool enabled = await LokasiService.cekLayananAktif();
      if (!enabled) {
        if (mounted) setState(() => _locationMessage = 'Aktifkan lokasi perangkat untuk melihat posisi saat ini.');
        return;
      }
      final bool permission = await LokasiService.mintaIzin();
      if (!permission) {
        if (mounted) setState(() => _locationMessage = 'Izin lokasi diperlukan untuk aktivitas luar ruangan.');
        return;
      }
      final Position? position = await LokasiService.ambilSatuTitik();
      if (!mounted) return;
      if (position == null || !position.latitude.isFinite || !position.longitude.isFinite) {
        setState(() => _locationMessage = 'Posisi belum tersedia. Coba di area terbuka.');
        return;
      }
      setState(() {
        _currentLocation = RunPoint(
          latitude: position.latitude,
          longitude: position.longitude,
          timestamp: position.timestamp,
          accuracyMeters: position.accuracy,
          altitudeMeters: position.altitude.isFinite ? position.altitude : null,
          startsNewSegment: true,
        );
        _locationMessage = 'Lokasi ditemukan • akurasi ±${position.accuracy.round()} m';
      });
    } catch (_) {
      if (mounted) setState(() => _locationMessage = 'Tidak dapat membaca lokasi. Coba lagi.');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool indoor = _environment == RunEnvironment.indoor;
    return Scaffold(
      appBar: AppBar(title: const Text('Rekam aktivitas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            const Text('Siap bergerak?', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 6),
            const Text('Pilih aktivitas dan lokasi sebelum mulai merekam.', style: TextStyle(color: VoltWarna.teksAbu)),
            const SizedBox(height: 18),
            if (indoor)
              _indoorMapCard()
            else ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: RunRouteMapView(
                  key: ValueKey<String>('activity-start-${_currentLocation?.timestamp.toIso8601String() ?? 'empty'}'),
                  route: _currentLocation == null ? const <RunPoint>[] : <RunPoint>[_currentLocation!],
                  laps: const <RunLap100m>[],
                  height: 240,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: Text(_locationMessage ?? 'Peta dan posisi GPS sebelum mulai.', style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 12))),
                  IconButton(
                    tooltip: 'Perbarui lokasi',
                    onPressed: _loadingLocation ? null : loadLocation,
                    icon: _loadingLocation
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location_rounded, color: VoltWarna.aksen),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _sectionTitle('Lokasi aktivitas'),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.outdoor,
                  icon: Icons.wb_sunny_outlined,
                  title: 'Luar ruangan',
                  subtitle: 'Jarak dari GPS',
                  onTap: () {
                    setState(() => _environment = RunEnvironment.outdoor);
                    loadLocation();
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.indoor,
                  icon: Icons.fitness_center_rounded,
                  title: 'Dalam ruangan',
                  subtitle: 'Jarak manual',
                  onTap: () => setState(() {
                    _environment = RunEnvironment.indoor;
                    _currentLocation = null;
                    _locationMessage = null;
                  }),
                )),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('Jenis aktivitas'),
            const SizedBox(height: 10),
            _choiceCard(
              selected: _mode == _ActivityMode.run,
              icon: Icons.directions_run_rounded,
              title: 'Lari biasa',
              subtitle: 'Rekam jarak, pace, rute, dan elevasi.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.run),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.interval,
              icon: Icons.repeat_rounded,
              title: 'Lari interval',
              subtitle: 'Atur waktu kerja, pemulihan, dan pengulangan.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.interval),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.walk,
              icon: Icons.directions_walk_rounded,
              title: 'Berjalan',
              subtitle: 'Pelacakan jalan kaki dengan metrik serupa.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.walk),
            ),
            if (_mode == _ActivityMode.interval) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: VoltWarna.kartu, borderRadius: BorderRadius.circular(18), border: Border.all(color: VoltWarna.border)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Pengaturan interval', style: TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(child: _numberField('Kerja (detik)', _workSeconds)),
                        const SizedBox(width: 10),
                        Expanded(child: _numberField('Pulih (detik)', _recoverySeconds)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _numberField('Jumlah ulangan', _repetitions),
                  ],
                ),
              ),
            ],
            if (indoor) ...<Widget>[
              const SizedBox(height: 12),
              const Text('Mode dalam ruangan tidak meminta GPS. Saat selesai, masukkan jarak dari treadmill atau alat yang digunakan.', style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12, height: 1.4)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.radio_button_checked_rounded),
              label: const Text('Mulai aktivitas'),
            ),
            const SizedBox(height: 8),
            const Text('Untuk hasil GPS terbaik, mulai di area terbuka dan tunggu posisi memiliki akurasi yang baik.', textAlign: TextAlign.center, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _indoorMapCard() {
    return Container(
      height: 210,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: <Color>[Color(0xFF1D3240), Color(0xFF202943)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.directions_run_rounded, size: 48, color: VoltWarna.aksen),
          SizedBox(height: 12),
          Text('Mode dalam ruangan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          SizedBox(height: 5),
          Text('GPS dinonaktifkan. Waktu tetap direkam; jarak dapat dimasukkan saat selesai.', textAlign: TextAlign.center, style: TextStyle(color: VoltWarna.teksAbu, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool horizontal = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? VoltWarna.aksen.withValues(alpha: 0.12) : VoltWarna.kartu,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: selected ? VoltWarna.aksen : VoltWarna.border, width: selected ? 1.6 : 1),
        ),
        child: horizontal
            ? Row(
                children: <Widget>[
                  Icon(icon, color: selected ? VoltWarna.aksen : VoltWarna.teksAbu, size: 26),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11))])),
                  if (selected) const Icon(Icons.check_circle_rounded, color: VoltWarna.aksen),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, color: selected ? VoltWarna.aksen : VoltWarna.teksAbu, size: 25),
                  const SizedBox(height: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 10)),
                ],
              ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16));

  void _start() {
    IntervalRunPlan? plan;
    if (_mode == _ActivityMode.interval) {
      final int? work = int.tryParse(_workSeconds.text.trim());
      final int? recovery = int.tryParse(_recoverySeconds.text.trim());
      final int? repetitions = int.tryParse(_repetitions.text.trim());
      if (work == null || work < 10 || work > 3600 || recovery == null || recovery < 5 || recovery > 3600 || repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Atur kerja 10–3600 detik, pemulihan 5–3600 detik, dan ulangan 1–30.')));
        return;
      }
      plan = IntervalRunPlan(workSeconds: work, recoverySeconds: recovery, repetitions: repetitions);
    }
    widget.onStart(ActivityStartConfig(
      activityType: _mode == _ActivityMode.walk ? RunActivityType.walk : RunActivityType.run,
      environment: _environment,
      intervalPlan: plan,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lokasi baru dimuat ketika pengguna membuka alur rekam, bukan saat aplikasi
    // pertama kali diluncurkan. RootShell memanggil loadLocation secara eksplisit.
  }
}
