import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;

import '../../services/app_language_service.dart';

import '../../services/lokasi_service.dart';
import 'services/heart_rate_service.dart';
import 'models/run_session.dart';
import 'run_route_map_view.dart';

class ActivityStartConfig {
  final RunActivityType activityType;
  final RunEnvironment environment;
  final IntervalRunPlan? intervalPlan;
  final double? targetDistanceKm;
  final double? targetPaceSecondsPerKm;
  final bool paceNotificationsEnabled;
  final List<RunPoint> plannedRoute;

  const ActivityStartConfig({
    required this.activityType,
    required this.environment,
    required this.intervalPlan,
    this.targetDistanceKm,
    this.targetPaceSecondsPerKm,
    this.paceNotificationsEnabled = false,
    this.plannedRoute = const <RunPoint>[],
  });
}

enum _ActivityMode { run, interval, walk }

class ActivitySetupPage extends StatefulWidget {
  const ActivitySetupPage({
    super.key,
    required this.onStart,
    this.plannedRoute = const <RunPoint>[],
    this.onClearPlannedRoute,
  });

  final ValueChanged<ActivityStartConfig> onStart;
  final List<RunPoint> plannedRoute;
  final VoidCallback? onClearPlannedRoute;

  @override
  State<ActivitySetupPage> createState() => ActivitySetupPageState();
}

class ActivitySetupPageState extends State<ActivitySetupPage> {
  String _text(String indonesia, String english) =>
      AppLanguageService.text(context, indonesia, english);
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
  bool _paceNotificationsEnabled = false;
  bool _searchingHeartRate = false;
  String? _heartRateDeviceName;

  @override
  void initState() {
    super.initState();
    _heartRateDeviceName = HeartRateService.instance.connectedDeviceName.value;
  }

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
        if (mounted) setState(() => _locationMessage = _text('Aktifkan lokasi perangkat untuk melihat posisi saat ini.', 'Turn on your device location to see your current position.'));
        await Geolocator.openLocationSettings();
        return;
      }
      final bool permission = await LokasiService.mintaIzin();
      if (!permission) {
        if (mounted) setState(() => _locationMessage = _text('Izin lokasi diperlukan untuk aktivitas luar ruangan.', 'Location permission is required for outdoor activities.'));
        await permissions.openAppSettings();
        return;
      }
      final Position? position = await LokasiService.ambilSatuTitik();
      if (!mounted) return;
      if (position == null || !position.latitude.isFinite || !position.longitude.isFinite) {
        setState(() => _locationMessage = _text('Posisi belum tersedia. Coba di area terbuka.', 'Your position is unavailable. Try an open area.'));
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
        _locationMessage = _text('Lokasi ditemukan • akurasi ±${position.accuracy.round()} m', 'Location found • accuracy ±${position.accuracy.round()} m');
      });
    } catch (_) {
      if (mounted) setState(() => _locationMessage = _text('Tidak dapat membaca lokasi. Coba lagi.', 'Unable to read location. Try again.'));
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool indoor = _environment == RunEnvironment.indoor;
    final Color teksSekunder = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: Text(_text('Rekam aktivitas', 'Record activity'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          children: <Widget>[
            Text(
              _text('Pilih aktivitas', 'Choose an activity'),
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
                  plannedRoute: widget.plannedRoute,
                  laps: const <RunLap100m>[],
                  height: 240,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(child: Text(_locationMessage ?? _text('Peta dan posisi GPS sebelum mulai.', 'Map and GPS position before you start.'), style: TextStyle(color: teksSekunder, fontSize: 12))),
                  IconButton(
                    tooltip: _text('Perbarui lokasi', 'Refresh location'),
                    onPressed: _loadingLocation ? null : loadLocation,
                    icon: _loadingLocation
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.my_location_rounded, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
              if (widget.plannedRoute.length > 1) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.route_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _text('Rute terencana akan ditampilkan di GPS langsung.', 'The planned route will appear on the live GPS screen.'),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: _text('Lepas rute', 'Remove route'),
                        onPressed: widget.onClearPlannedRoute,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 20),
            _sectionTitle(_text('Lokasi aktivitas', 'Activity location')),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.outdoor,
                  title: _text('Luar ruangan', 'Outdoor'),
                  subtitle: 'GPS',
                  onTap: () {
                    setState(() => _environment = RunEnvironment.outdoor);
                    loadLocation();
                  },
                )),
                const SizedBox(width: 10),
                Expanded(child: _choiceCard(
                  selected: _environment == RunEnvironment.indoor,
                  title: _text('Dalam ruangan', 'Indoor'),
                  subtitle: _text('Jarak manual', 'Manual distance'),
                  onTap: () => setState(() {
                    _environment = RunEnvironment.indoor;
                    _currentLocation = null;
                    _locationMessage = null;
                  }),
                )),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle(_text('Jenis aktivitas', 'Activity type')),
            const SizedBox(height: 10),
            _choiceCard(
              selected: _mode == _ActivityMode.run,
              title: _text('Lari biasa', 'Run'),
              subtitle: _text('Jarak, pace, rute, dan elevasi.', 'Distance, pace, route, and elevation.'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.run),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.interval,
              title: _text('Lari interval', 'Interval run'),
              subtitle: _text('Atur kerja dan pemulihan.', 'Set work and recovery intervals.'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.interval),
            ),
            const SizedBox(height: 9),
            _choiceCard(
              selected: _mode == _ActivityMode.walk,
              title: _text('Berjalan', 'Walk'),
              subtitle: _text('Rekam perjalanan berjalan.', 'Track a walking session.'),
              horizontal: true,
              onTap: () => setState(() => _mode = _ActivityMode.walk),
            ),
            const SizedBox(height: 20),
            _sectionTitle(_text('Target aktivitas (opsional)', 'Activity targets (optional)')),
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
                    _text('Opsional. Isi jarak dan pace target.', 'Optional. Set a target distance and pace.'),
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
                          decoration: InputDecoration(
                            labelText: _text('Jarak target (km)', 'Target distance (km)'),
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
                          decoration: InputDecoration(
                            labelText: _text('Pace target (m:ss/km)', 'Target pace (m:ss/km)'),
                            hintText: '6:00',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _paceNotificationsEnabled,
                    onChanged: (bool value) => setState(
                      () => _paceNotificationsEnabled = value,
                    ),
                    title: Text(_text('Pacer setiap menit', 'Minute-by-minute pacer')),
                    subtitle: Text(
                      _text(
                        'Notifikasi pace target muncul setiap menit selama aktivitas berjalan. Isi jarak dan pace target untuk memakai fitur ini.',
                        'Get a pace-target notification every minute while tracking. Enter both a target distance and pace to use this feature.',
                      ),
                      style: TextStyle(color: teksSekunder, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _searchingHeartRate ? null : _toggleHeartRateDevice,
              icon: _searchingHeartRate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      HeartRateService.instance.isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.favorite_border_rounded,
                    ),
              label: Text(
                _searchingHeartRate
                    ? _text('Mencari perangkat HR...', 'Scanning for HR devices...')
                    : HeartRateService.instance.isConnected
                        ? _text('Putuskan ${_heartRateDeviceName ?? 'sensor HR'}', 'Disconnect ${_heartRateDeviceName ?? 'HR sensor'}')
                        : _text('Sambungkan sensor HR Bluetooth', 'Connect a Bluetooth HR sensor'),
              ),
            ),
            Text(
              _text(
                'Mendukung sensor Bluetooth yang menyediakan layanan Heart Rate standar. Sebagian jam pintar perlu menyalakan fitur siaran detak jantung.',
                'Supports Bluetooth sensors exposing the standard Heart Rate service. Some smartwatches require heart-rate broadcast to be enabled.',
              ),
              style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.35),
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
                    Text(
                      _text('Pengaturan interval', 'Interval settings'),
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
                      segments: <ButtonSegment<IntervalMeasure>>[
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.time,
                          label: Text(_text('Berdasarkan waktu', 'By time')),
                        ),
                        ButtonSegment<IntervalMeasure>(
                          value: IntervalMeasure.distance,
                          label: Text(_text('Berdasarkan jarak', 'By distance')),
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
                          Expanded(child: _numberField(_text('Kerja (detik)', 'Work (seconds)'), _workSeconds)),
                          const SizedBox(width: 10),
                          Expanded(child: _numberField(_text('Pulih (detik)', 'Recovery (seconds)'), _recoverySeconds)),
                        ],
                      ),
                    ] else ...<Widget>[
                      if (indoor)
                        Text(
                          _text('Interval berbasis jarak membutuhkan jarak GPS selama sesi. Pilih Luar ruangan untuk memakai mode ini.', 'Distance-based intervals need GPS distance during the session. Select Outdoor to use this mode.'),
                          style: TextStyle(color: teksSekunder, fontSize: 12),
                        )
                      else
                        Row(
                          children: <Widget>[
                            Expanded(child: _numberField(_text('Kerja (meter)', 'Work (meters)'), _workDistance)),
                            const SizedBox(width: 10),
                            Expanded(child: _numberField(_text('Pulih (meter)', 'Recovery (meters)'), _recoveryDistance)),
                          ],
                        ),
                    ],
                    const SizedBox(height: 10),
                    _numberField(_text('Jumlah ulangan', 'Repetitions'), _repetitions),
                  ],
                ),
              ),
            ],
            if (indoor) ...<Widget>[
              const SizedBox(height: 12),
              Text(_text('Mode dalam ruangan tidak meminta GPS. Saat selesai, masukkan jarak dari treadmill atau alat yang digunakan.', 'Indoor mode does not use GPS. Enter the distance from your treadmill or equipment when you finish.'), style: TextStyle(color: teksSekunder, fontSize: 12, height: 1.4)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _start,
              child: Text(_text('Mulai aktivitas', 'Start activity')),
            ),
            const SizedBox(height: 8),
            Text(_text('Untuk GPS yang lebih akurat, mulai di area terbuka.', 'For better GPS accuracy, start in an open area.'), textAlign: TextAlign.center, style: TextStyle(color: teksSekunder, fontSize: 11, height: 1.4)),
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
            _text('Mode dalam ruangan', 'Indoor mode'),
            style: TextStyle(
              color: teks,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _text('GPS dinonaktifkan. Waktu tetap direkam; jarak dapat dimasukkan saat selesai.', 'GPS is disabled. Time is still recorded; distance can be entered when you finish.'),
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

  Future<void> _toggleHeartRateDevice() async {
    final HeartRateService service = HeartRateService.instance;
    if (service.isConnected) {
      await service.disconnect();
      if (mounted) {
        setState(() => _heartRateDeviceName = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Sensor HR terputus.', 'HR sensor disconnected.'))),
        );
      }
      return;
    }

    setState(() => _searchingHeartRate = true);
    try {
      final List<HeartRateDevice> devices = await service.scanForDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text(
                'Sensor tidak ditemukan. Pastikan sensor aktif dan menyiarkan Heart Rate Bluetooth.',
                'No sensor found. Make sure it is on and advertising Bluetooth Heart Rate.',
              ),
            ),
          ),
        );
        return;
      }

      final HeartRateDevice? selected = await showModalBottomSheet<HeartRateDevice>(
        context: context,
        showDragHandle: true,
        builder: (BuildContext sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                _text('Pilih sensor detak jantung', 'Choose a heart-rate sensor'),
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ...devices.map(
                (HeartRateDevice device) => ListTile(
                  leading: const Icon(Icons.bluetooth_rounded),
                  title: Text(device.name),
                  subtitle: Text('Signal ${device.rssi} dBm'),
                  onTap: () => Navigator.of(sheetContext).pop(device),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;

      await service.connect(selected);
      if (!mounted) return;
      setState(() => _heartRateDeviceName = selected.name);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text('Terhubung ke ${selected.name}.', 'Connected to ${selected.name}.'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _text('Sensor HR gagal disambungkan: $error', 'Could not connect to the HR sensor: $error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _searchingHeartRate = false);
    }
  }

  void _start() {
    double? targetDistanceKm;
    double? targetPaceSecondsPerKm;
    final String targetDistanceText = _targetDistanceKm.text.trim();
    final String targetPaceText = _targetPace.text.trim();
    if (targetDistanceText.isNotEmpty || targetPaceText.isNotEmpty) {
      if (targetDistanceText.isEmpty || targetPaceText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Isi jarak dan pace target, atau kosongkan keduanya.', 'Enter both target distance and pace, or leave both empty.'))),
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
          SnackBar(content: Text(_text('Jarak target harus 0,1–100 km dan pace gunakan format m:ss/km, misalnya 6:00.', 'Target distance must be 0.1–100 km and pace must use m:ss/km, for example 6:00.'))),
        );
        return;
      }
    }

    if (_paceNotificationsEnabled && targetPaceSecondsPerKm == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Isi jarak dan pace target untuk mengaktifkan pacer.',
              'Enter a target distance and pace to enable the pacer.',
            ),
          ),
        ),
      );
      return;
    }

    IntervalRunPlan? plan;
    if (_mode == _ActivityMode.interval) {
      final int? repetitions = int.tryParse(_repetitions.text.trim());
      if (repetitions == null || repetitions < 1 || repetitions > 30) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_text('Jumlah ulangan harus 1–30.', 'Repetitions must be between 1 and 30.'))),
        );
        return;
      }

      if (_intervalMeasure == IntervalMeasure.time) {
        final int? work = int.tryParse(_workSeconds.text.trim());
        final int? recovery = int.tryParse(_recoverySeconds.text.trim());
        if (work == null || work < 10 || work > 3600 ||
            recovery == null || recovery < 5 || recovery > 3600) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_text('Kerja harus 10–3600 detik, pemulihan 5–3600 detik.', 'Work must be 10–3600 seconds and recovery 5–3600 seconds.')),
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
            SnackBar(
              content: Text(_text('Interval berbasis jarak saat ini membutuhkan GPS luar ruangan.', 'Distance-based intervals require outdoor GPS.')),
            ),
          );
          return;
        }
        if (workMeters == null || workMeters < 50 || workMeters > 20000 ||
            recoveryMeters == null || recoveryMeters < 0 || recoveryMeters > 20000) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_text('Jarak kerja 50–20.000 m dan pemulihan 0–20.000 m.', 'Work distance must be 50–20,000 m and recovery distance 0–20,000 m.')),
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
      paceNotificationsEnabled: _paceNotificationsEnabled,
      plannedRoute: widget.plannedRoute,
    ));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lokasi baru dimuat ketika pengguna membuka alur rekam, bukan saat aplikasi
    // pertama kali diluncurkan. RootShell memanggil loadLocation secara eksplisit.
  }
}
