import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../services/lokasi_service.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';

class ActivityStartConfig {
  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? intervalPlan;
  final double? targetDistanceKm;
  final double? targetPaceSecondsPerKm;

  const ActivityStartConfig({
    required this.activityType,
    required this.environment,
    required this.intervalPlan,
    this.targetDistanceKm,
    this.targetPaceSecondsPerKm,
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
  IntervalMeasure _intervalMeasure = IntervalMeasure.time;
  RunPoint? _currentLocation;
  bool _loadingLocation = false;
  String? _locationMessage;

  final TextEditingController _workSeconds = TextEditingController(text: '60');
  final TextEditingController _recoverySeconds = TextEditingController(text: '90');
  final TextEditingController _repetitions = TextEditingController(text: '6');
  final TextEditingController _workDistance = TextEditingController(text: '400');
  final TextEditingController _recoveryDistance = TextEditingController(text: '200');
  final TextEditingController _targetDistanceKm = TextEditingController();
  final TextEditingController _targetPace = TextEditingController();

  @override
  void dispose() {
    _workSeconds.dispose();
    _recoverySeconds.dispose();
    _repetitions.dispose();
    _workDistance.dispose();
    _recoveryDistance.dispose();
    _targetDistanceKm.dispose();
    _targetPace.dispose();
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
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Rekam aktivitas')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            const Text(
              'Pilih aktivitas',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            if (indoor)
              _indoorMapCard()
            else ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.zero,
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
                  Expanded(child: Text(_locationMessage ?? 'Peta dan posisi GPS sebelum mulai.', style: TextStyle(color: teksSekunder, fontSize: 12))),
                  IconButton(
                    tooltip: 'Perbarui lokasi',
                    onPressed: _loadingLocation ? null : loadLocation,
                    icon: _loadingLocation
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location_rounded, color: Theme.of(context).colorScheme.primary),
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
                  title: 'Luar ruangan',
                  subtitle: 'GPS',
                  onTap: () {
                    setState(() => _environment = RunEnvironment.outdoor);
                    loadLocation();
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.indoor,
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
              title: 'Lari biasa',
              subtitle: 'Jarak, pace, rute, dan elevasi.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.run),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.interval,
              title: 'Lari interval',
              subtitle: 'Atur kerja dan pemulihan.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.interval),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.walk,
              title: 'Berjalan',
              subtitle: 'Rekam perjalanan berjalan.',
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.walk),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Target aktivitas (opsional)'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Opsional. Isi jarak dan pace target.',
                    style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _targetDistanceKm,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                          ],
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Jarak target (km)',
                            hintText: '5,0',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _targetPace,
                          keyboardType: TextInputType.text,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                          ],
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Pace target (m:ss/km)',
                            hintText: '6:00',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_mode == _ActivityMode.interval) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Pengaturan interval',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<IntervalMeasure>(
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            return states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface;
                          },
                        ),
                        backgroundColor:
                            WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                            return states.contains(WidgetState.selected)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surface;
                          },
                        ),
                        side: WidgetStatePropertyAll<BorderSide?>(
                          BorderSide(color: Theme.of(context).dividerColor),
                        ),
                        shape: const WidgetStatePropertyAll<OutlinedBorder?>(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero,
                          ),
                        ),
                      ),
                      segments: const <ButtonSegment<IntervalMeasure>>[
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.time,
                          label: Text('Berdasarkan waktu'),
                        ),
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.distance,
                          label: Text('Berdasarkan jarak'),
                        ),
                      ],
                      selected: <IntervalMeasure>{_intervalMeasure},
                      onSelectionChanged: (Set<IntervalMeasure> value) {
                        setState(() => _intervalMeasure = value.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_intervalMeasure == IntervalMeasure.time) ...<Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(child: _numberField('Kerja (detik)', _workSeconds)),
                          const SizedBox(width: 10),
                          Expanded(child: _numberField('Pulih (detik)', _recoverySeconds)),
                        ],
                      ),
                    ] else ...<Widget>[
                      if (indoor)
                        Text(
                          'Interval berbasis jarak membutuhkan jarak GPS selama sesi. Pilih Luar ruangan untuk memakai mode ini.',
                          style: TextStyle(color: teksSekunder, fontSize: 12),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(child: _numberField('Kerja (meter)', _workDistance)),
                            const SizedBox(width: 10),
                            Expanded(child: _numberField('Pulih (meter)', _recoveryDistance)),
                          ],
                        ),
                    ],
                    const SizedBox(height: 10),
                    _numberField('Jumlah ulangan', _repetitions),
                  ],
                ),
              ),
            ],
            if (indoor) ...<Widget>[
              const SizedBox(height: 12),
              Text('Mode dalam ruangan tidak meminta GPS. Saat selesai, masukkan jarak dari treadmill atau alat yang digunakan.', style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _start,
              child: const Text('Mulai aktivitas'),
            ),
            const SizedBox(height: 8),
            Text('Untuk GPS yang lebih akurat, mulai di area terbuka.', textAlign: TextAlign.center, style: TextStyle(color: teksSekunder, fontSize: 11, height: 1.4)),
          ],
        ),
      ),
    );
  }

  Widget _indoorMapCard() {
    final Color teks = Theme.of(context).colorScheme.onSurface;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      height: 210,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            'Mode dalam ruangan',
            style: TextStyle(
              color: teks,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'GPS dinonaktifkan. Waktu tetap direkam; jarak dapat dimasukkan saat selesai.',
            textAlign: TextAlign.center,
            style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _choiceCard({
    required bool selected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool horizontal = false,
  }) {
    final Color teks = Theme.of(context).colorScheme.onSurface;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    final Color warnaBorder = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).dividerColor;

    return InkWell(
      borderRadius: BorderRadius.zero,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: warnaBorder, width: selected ? 1.6 : 1),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      color: teks,
                      fontWeight: FontWeight.w800,
                      fontSize: horizontal ? 14 : 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: teksSekunder, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, isDense: true),
    );
  }

  Widget _sectionTitle(String title) => Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16));

  double? _parsePace(String raw) {
    final Match? match = RegExp(r'^(\d{1,2}):([0-5]\d)$').firstMatch(raw.trim());
    if (match == null) return null;
    final int minutes = int.parse(match.group(1)!);
    final int seconds = int.parse(match.group(2)!);
    final int totalSeconds = minutes * 60 + seconds;
    if (totalSeconds < 120 || totalSeconds > 3600) return null;
    return totalSeconds.toDouble();
  }

  void _start() {
    double? targetDistanceKm;
    double? targetPaceSecondsPerKm;
    final String targetDistanceText = _targetDistanceKm.text.trim();
    final String targetPaceText = _targetPace.text.trim();
    if (targetDistanceText.isNotEmpty || targetPaceText.isNotEmpty) {
      if (targetDistanceText.isEmpty || targetPaceText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Isi jarak dan pace target, atau kosongkan keduanya.')),
        );
        return;
      }
      targetDistanceKm = double.tryParse(targetDistanceText.replaceAll(',', '.'));
      targetPaceSecondsPerKm = _parsePace(targetPaceText);
      if (targetDistanceKm == null ||
          !targetDistanceKm.isFinite ||
          targetDistanceKm < 0.1 ||
          targetDistanceKm > 100 ||
          targetPaceSecondsPerKm == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jarak target harus 0,1–100 km dan pace gunakan format m:ss/km, misalnya 6:00.')),
        );
        return;
      }
    }

    IntervalRunPlan? plan;
    if (_mode == _ActivityMode.interval) {
      final int? repetitions = int.tryParse(_repetitions.text.trim());
      if (repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Jumlah ulangan harus 1–30.')),
        );
        return;
      }

      if (_intervalMeasure == IntervalMeasure.time) {
        final int? work = int.tryParse(_workSeconds.text.trim());
        final int? recovery = int.tryParse(_recoverySeconds.text.trim());
        if (work == null || work < 10 || work > 3600 ||
            recovery == null || recovery < 5 || recovery > 3600) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kerja harus 10–3600 detik, pemulihan 5–3600 detik.'),
            ),
          );
          return;
        }
        plan = IntervalRunPlan(
          workSeconds: work,
          recoverySeconds: recovery,
          repetitions: repetitions,
          measure: IntervalMeasure.time,
        );
      } else {
        final double? workMeters = double.tryParse(_workDistance.text.trim());
        final double? recoveryMeters = double.tryParse(_recoveryDistance.text.trim());
        if (_environment == RunEnvironment.indoor) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Interval berbasis jarak saat ini membutuhkan GPS luar ruangan.'),
            ),
          );
          return;
        }
        if (workMeters == null || workMeters < 50 || workMeters > 20000 ||
            recoveryMeters == null || recoveryMeters < 0 || recoveryMeters > 20000) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Jarak kerja 50–20.000 m dan pemulihan 0–20.000 m.'),
            ),
          );
          return;
        }
        plan = IntervalRunPlan(
          workSeconds: 60,
          recoverySeconds: 90,
          repetitions: repetitions,
          measure: IntervalMeasure.distance,
          workDistanceMeters: workMeters,
          recoveryDistanceMeters: recoveryMeters,
        );
      }
    }
    widget.onStart(ActivityStartConfig(
      activityType: _mode == _ActivityMode.walk ? RunActivityType.walk : RunActivityType.run,
      environment: _environment,
      intervalPlan: plan,
      targetDistanceKm: targetDistanceKm,
      targetPaceSecondsPerKm: targetPaceSecondsPerKm,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lokasi baru dimuat ketika pengguna membuka alur rekam, bukan saat aplikasi
    // pertama kali diluncurkan. RootShell memanggil loadLocation secara eksplisit.
  }
}
