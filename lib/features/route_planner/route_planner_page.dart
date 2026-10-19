import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../theme/volt_theme.dart';

/// Perencana rute dengan beberapa titik singgah.
class RoutePlannerPage extends StatefulWidget {
  const RoutePlannerPage({super.key, required this.active});

  /// GPS baru diminta ketika pengguna benar-benar membuka tab rute.
  final bool active;

  @override
  State<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends State<RoutePlannerPage> {
  final MapController _mapController = MapController();
  static const LatLng _pusatAwal = LatLng(-7.7956, 110.3695);

  final List<LatLng> _titikRute = <LatLng>[];
  List<LatLng> _jalur = <LatLng>[];
  double? _jarakMeter;
  double? _elevasiNaik;
  double? _elevasiTurun;
  String? _tingkatKesulitan;
  String? _pesanError;
  bool _sedangMenghitung = false;
  bool _sedangMengambilLokasi = false;
  int _nomorPermintaan = 0;
  Timer? _penundaHitung;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _aktifkanPerencanaRute();
    }
  }

  @override
  void didUpdateWidget(covariant RoutePlannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _aktifkanPerencanaRute();
    }
  }

  void _aktifkanPerencanaRute() {
    // Jika belum ada titik rute, cari lokasi sekarang setiap kali tab dibuka.
    // Ini juga memberi kesempatan mencoba ulang jika GPS sebelumnya gagal.
    if (_titikRute.isEmpty && !_sedangMengambilLokasi) {
      unawaited(_gunakanLokasiSaatIni(jadikanTitikAwal: true));
    }
  }

  @override
  void dispose() {
    _penundaHitung?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _pilihTitik(LatLng titik) {
    if (_titikRute.length >= 10) {
      setState(() => _pesanError = 'Maksimal 10 titik dalam satu rute.');
      return;
    }

    _penundaHitung?.cancel();
    _nomorPermintaan++; // Abaikan hasil hitung dari susunan titik sebelumnya.
    setState(() {
      _titikRute.add(titik);
      _hapusHasilRute();
      _pesanError = null;
      _sedangMenghitung = false;
    });

    // Setelah titik kedua dan seterusnya dipilih, perkiraan diperbarui
    // otomatis agar pengguna tidak perlu menekan tombol hitung.
    if (_titikRute.length >= 2) {
      _penundaHitung?.cancel();
      _penundaHitung = Timer(
        const Duration(milliseconds: 450),
        () => unawaited(_hitungRute()),
      );
    }
  }

  void _hapusHasilRute() {
    _jalur = <LatLng>[];
    _jarakMeter = null;
    _elevasiNaik = null;
    _elevasiTurun = null;
    _tingkatKesulitan = null;
  }

  void _urungkanTitikTerakhir() {
    if (_titikRute.isEmpty) return;
    _penundaHitung?.cancel();
    _nomorPermintaan++; // Hasil lama tidak boleh menggantikan rute terbaru.
    setState(() {
      _titikRute.removeLast();
      _hapusHasilRute();
      _pesanError = null;
      _sedangMenghitung = false;
    });
    if (_titikRute.length >= 2) {
      _penundaHitung?.cancel();
      _penundaHitung = Timer(
        const Duration(milliseconds: 350),
        () => unawaited(_hitungRute()),
      );
    }
  }

  void _hapusSemuaTitik() {
    _penundaHitung?.cancel();
    _nomorPermintaan++;
    setState(() {
      _titikRute.clear();
      _hapusHasilRute();
      _pesanError = null;
      _sedangMenghitung = false;
    });
  }

  Future<void> _gunakanLokasiSaatIni({
    bool jadikanTitikAwal = false,
  }) async {
    if (_sedangMengambilLokasi) return;
    _penundaHitung?.cancel();
    _nomorPermintaan++;
    setState(() {
      _sedangMenghitung = false;
      _sedangMengambilLokasi = true;
      _pesanError = null;
    });

    try {
      final bool layananAktif = await Geolocator.isLocationServiceEnabled();
      if (!layananAktif) {
        throw Exception('Aktifkan layanan lokasi pada ponsel.');
      }

      LocationPermission izin = await Geolocator.checkPermission();
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }
      if (izin == LocationPermission.denied ||
          izin == LocationPermission.deniedForever) {
        throw Exception('Izin lokasi belum diberikan.');
      }

      final Position posisi = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final LatLng titik = LatLng(posisi.latitude, posisi.longitude);
      if (!mounted) return;

      setState(() {
        if (jadikanTitikAwal && _titikRute.isEmpty) {
          _titikRute.add(titik);
        } else if (!jadikanTitikAwal) {
          if (_titikRute.isEmpty) {
            _titikRute.add(titik);
          } else {
            _titikRute[0] = titik;
          }
        }
        _hapusHasilRute();
        _pesanError = null;
      });
      _mapController.move(titik, 15);

      if (_titikRute.length >= 2) {
        unawaited(_hitungRute());
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _pesanError = error.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _sedangMengambilLokasi = false);
    }
  }

  Future<void> _hitungRute() async {
    if (_titikRute.length < 2) return;

    final int nomorPermintaan = ++_nomorPermintaan;
    final List<LatLng> titikPermintaan = List<LatLng>.of(_titikRute);

    setState(() {
      _sedangMenghitung = true;
      _pesanError = null;
    });

    try {
      final String koordinat = titikPermintaan
          .map((LatLng titik) => '${titik.longitude},${titik.latitude}')
          .join(';');
      final Uri alamatRute = Uri.parse(
        'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
        '$koordinat',
      ).replace(queryParameters: <String, String>{
        'overview': 'full',
        'geometries': 'geojson',
        'steps': 'false',
        'alternatives': 'false',
      });

      final http.Response jawaban = await http
          .get(
            alamatRute,
            headers: const <String, String>{'User-Agent': 'VoltStride/2.0'},
          )
          .timeout(const Duration(seconds: 25));

      if (jawaban.statusCode != 200) {
        throw Exception('Rute belum bisa dihitung. Coba lagi sebentar.');
      }

      final Map<String, dynamic> data =
          jsonDecode(jawaban.body) as Map<String, dynamic>;
      final List<dynamic> daftarRute =
          data['routes'] as List<dynamic>? ?? <dynamic>[];
      if (data['code'] != 'Ok' || daftarRute.isEmpty) {
        throw Exception(
          'Jalur tidak ditemukan. Coba pilih titik yang dekat jalan atau jalur.',
        );
      }

      final Map<String, dynamic> rute =
          daftarRute.first as Map<String, dynamic>;
      final Map<String, dynamic> geometri =
          rute['geometry'] as Map<String, dynamic>;
      final List<dynamic> koordinatJalur =
          geometri['coordinates'] as List<dynamic>;
      final List<LatLng> jalurBaru = koordinatJalur.map((dynamic nilai) {
        final List<dynamic> xy = nilai as List<dynamic>;
        return LatLng(
          (xy[1] as num).toDouble(),
          (xy[0] as num).toDouble(),
        );
      }).toList(growable: false);

      if (jalurBaru.length < 2) {
        throw Exception('Data jalur dari layanan peta belum lengkap.');
      }

      final double jarakBaru = (rute['distance'] as num).toDouble();
      double? elevasiNaik;
      double? elevasiTurun;
      try {
        final List<double> ketinggian = await _ambilPerkiraanElevasi(jalurBaru);
        if (ketinggian.length >= 2) {
          double naik = 0;
          double turun = 0;
          for (int i = 1; i < ketinggian.length; i++) {
            final double perubahan = ketinggian[i] - ketinggian[i - 1];
            // Abaikan perubahan kecil agar gangguan data tidak membesar-besarkan
            // jumlah elevasi.
            if (perubahan >= 3) naik += perubahan;
            if (perubahan <= -3) turun += perubahan.abs();
          }
          elevasiNaik = naik;
          elevasiTurun = turun;
        }
      } catch (_) {
        // Jarak rute masih bisa ditampilkan saat layanan elevasi gagal.
      }

      if (!mounted || nomorPermintaan != _nomorPermintaan) return;
      final String kesulitan = _tentukanKesulitan(
        jarakMeter: jarakBaru,
        elevasiNaik: elevasiNaik,
        elevasiTurun: elevasiTurun,
      );

      setState(() {
        _jalur = jalurBaru;
        _jarakMeter = jarakBaru;
        _elevasiNaik = elevasiNaik;
        _elevasiTurun = elevasiTurun;
        _tingkatKesulitan = kesulitan;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _jalur.isEmpty) return;
        try {
          _mapController.fitCamera(
            CameraFit.coordinates(
              coordinates: _jalur,
              padding: const EdgeInsets.all(42),
              maxZoom: 16,
            ),
          );
        } catch (_) {
          // Peta mungkin belum selesai membuat kamera.
        }
      });
    } catch (error) {
      if (mounted && nomorPermintaan == _nomorPermintaan) {
        setState(() {
          _pesanError = error.toString().replaceFirst('Exception: ', '');
          _jalur = <LatLng>[];
          _jarakMeter = null;
          _elevasiNaik = null;
          _elevasiTurun = null;
          _tingkatKesulitan = null;
        });
      }
    } finally {
      if (mounted && nomorPermintaan == _nomorPermintaan) {
        setState(() => _sedangMenghitung = false);
      }
    }
  }

  String _tentukanKesulitan({
    required double jarakMeter,
    required double? elevasiNaik,
    required double? elevasiTurun,
  }) {
    final double jarakKm = jarakMeter / 1000;
    final double elevasiPositif = elevasiNaik ?? 0;
    final double elevasiNegatif = elevasiTurun ?? 0;
    final double elevasiPerKm =
        jarakKm > 0 ? elevasiPositif / jarakKm : 0;

    // Tingkat kesulitan adalah perkiraan dari jarak, tanjakan, turunan,
    // dan perubahan elevasi per kilometer.
    if (jarakKm >= 25 ||
        elevasiPositif >= 500 ||
        elevasiNegatif >= 600 ||
        elevasiPerKm >= 25) {
      return 'Hard';
    }
    if (jarakKm >= 10 ||
        elevasiPositif >= 200 ||
        elevasiNegatif >= 250 ||
        elevasiPerKm >= 12) {
      return 'Intermediate';
    }
    return 'Easy';
  }

  Future<List<double>> _ambilPerkiraanElevasi(List<LatLng> jalur) async {
    final List<LatLng> sampel = _ambilSampel(jalur, 24);
    final String lokasi = sampel
        .map((LatLng titik) => '${titik.latitude},${titik.longitude}')
        .join('|');
    final Uri uri = Uri.https(
      'api.open-elevation.com',
      '/api/v1/lookup',
      <String, String>{'locations': lokasi},
    );
    final http.Response jawaban = await http
        .get(uri, headers: const <String, String>{'User-Agent': 'VoltStride/2.0'})
        .timeout(const Duration(seconds: 20));

    if (jawaban.statusCode != 200) {
      throw Exception('Data elevasi belum tersedia.');
    }

    final Map<String, dynamic> data =
        jsonDecode(jawaban.body) as Map<String, dynamic>;
    final List<dynamic> hasil =
        data['results'] as List<dynamic>? ?? <dynamic>[];
    return hasil
        .map((dynamic item) =>
            (item as Map<String, dynamic>)['elevation'] as num)
        .map((num nilai) => nilai.toDouble())
        .toList(growable: false);
  }

  List<LatLng> _ambilSampel(List<LatLng> jalur, int jumlahMaksimum) {
    if (jalur.length <= jumlahMaksimum) return jalur;
    final List<LatLng> hasil = <LatLng>[];
    for (int i = 0; i < jumlahMaksimum; i++) {
      final double posisi = i * (jalur.length - 1) / (jumlahMaksimum - 1);
      hasil.add(jalur[posisi.round()]);
    }
    return hasil;
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color text = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Rencanakan rute')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    _titikRute.isEmpty
                        ? 'Mengambil lokasi awal…'
                        : '${_titikRute.length} titik dipilih',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _sedangMengambilLokasi
                      ? null
                      : () => unawaited(_gunakanLokasiSaatIni()),
                  child: Text(
                    _sedangMengambilLokasi ? 'Mencari GPS…' : 'Lokasi saya',
                  ),
                ),
                IconButton(
                  tooltip: 'Urungkan titik terakhir',
                  onPressed:
                      _titikRute.isEmpty ? null : _urungkanTitikTerakhir,
                  icon: const Icon(Icons.undo),
                ),
                IconButton(
                  tooltip: 'Hapus semua titik',
                  onPressed: _titikRute.isEmpty ? null : _hapusSemuaTitik,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _pusatAwal,
                initialZoom: 13,
                minZoom: 3,
                maxZoom: 19,
                onTap: (TapPosition tap, LatLng titik) => _pilihTitik(titik),
              ),
              children: <Widget>[
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.voltstride',
                  maxNativeZoom: 19,
                ),
                if (_jalur.length > 1)
                  PolylineLayer(
                    polylines: <Polyline>[
                      Polyline(
                        points: _jalur,
                        strokeWidth: 5,
                        color: const Color(0xFF171717),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: <Marker>[
                    for (int i = 0; i < _titikRute.length; i++)
                      Marker(
                        point: _titikRute[i],
                        width: 38,
                        height: 38,
                        child: _penanda(
                          i == 0
                              ? 'A'
                              : i == _titikRute.length - 1
                                  ? 'B'
                                  : '$i',
                        ),
                      ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 18),
            decoration: BoxDecoration(
              color: surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_pesanError != null) ...<Widget>[
                  Text(
                    _pesanError!,
                    style: TextStyle(color: text, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_sedangMenghitung)
                  const LinearProgressIndicator(minHeight: 2),
                if (_jarakMeter != null) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _hasilUkuran(
                          'Jarak rute',
                          _formatJarak(_jarakMeter!),
                        ),
                      ),
                      Expanded(
                        child: _hasilUkuran(
                          'Elevasi +',
                          _elevasiNaik == null
                              ? '--'
                              : '+${_elevasiNaik!.round()} m',
                        ),
                      ),
                      Expanded(
                        child: _hasilUkuran(
                          'Elevasi −',
                          _elevasiTurun == null
                              ? '--'
                              : '−${_elevasiTurun!.round()} m',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Text(
                        'Kesulitan',
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: text),
                        ),
                        child: Text(
                          _tingkatKesulitan ?? '--',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_titikRute.length < 2) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Ketuk peta untuk menambah titik berikutnya.',
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _penanda(String label) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 2),
        shape: BoxShape.circle,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _hasilUkuran(String label, String nilai) {
    final Color text = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).hintColor,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          nilai,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: text,
          ),
        ),
      ],
    );
  }

  String _formatJarak(double meter) {
    if (meter >= 1000) return '${(meter / 1000).toStringAsFixed(2)} km';
    return '${meter.round()} m';
  }
}
