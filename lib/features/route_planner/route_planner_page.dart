import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../theme/volt_theme.dart';

enum _TitikYangDipilih { awal, tujuan }

/// Perencana rute sederhana dengan peta OpenStreetMap dan layanan rute publik.
/// Jarak mengikuti jalur yang dikembalikan layanan; elevasi adalah perkiraan.
class RoutePlannerPage extends StatefulWidget {
  const RoutePlannerPage({super.key});

  @override
  State<RoutePlannerPage> createState() => _RoutePlannerPageState();
}

class _RoutePlannerPageState extends State<RoutePlannerPage> {
  final MapController _mapController = MapController();
  static const LatLng _pusatAwal = LatLng(-7.7956, 110.3695);

  LatLng? _titikAwal;
  LatLng? _titikTujuan;
  List<LatLng> _jalur = <LatLng>[];
  double? _jarakMeter;
  double? _elevasiNaik;
  double? _elevasiTurun;
  _TitikYangDipilih _yangDipilih = _TitikYangDipilih.awal;
  bool _sedangMenghitung = false;
  bool _sedangMengambilLokasi = false;
  String? _pesanError;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _pilihTitik(LatLng titik) {
    setState(() {
      if (_yangDipilih == _TitikYangDipilih.awal) {
        _titikAwal = titik;
      } else {
        _titikTujuan = titik;
      }
      _jalur = <LatLng>[];
      _jarakMeter = null;
      _elevasiNaik = null;
      _elevasiTurun = null;
      _pesanError = null;
    });
  }

  Future<void> _gunakanLokasiSaatIni() async {
    setState(() {
      _sedangMengambilLokasi = true;
      _pesanError = null;
    });
    try {
      final bool layananAktif = await Geolocator.isLocationServiceEnabled();
      if (!layananAktif) {
        throw Exception('Aktifkan layanan lokasi pada ponsel terlebih dahulu.');
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
        _titikAwal = titik;
        _yangDipilih = _TitikYangDipilih.tujuan;
        _jalur = <LatLng>[];
        _jarakMeter = null;
        _elevasiNaik = null;
        _elevasiTurun = null;
      });
      _mapController.move(titik, 15);
    } catch (error) {
      if (mounted) {
        setState(() => _pesanError = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _sedangMengambilLokasi = false);
    }
  }

  Future<void> _hitungRute() async {
    final LatLng? awal = _titikAwal;
    final LatLng? tujuan = _titikTujuan;
    if (awal == null || tujuan == null) {
      setState(() => _pesanError = 'Pilih titik awal dan tujuan pada peta.');
      return;
    }

    setState(() {
      _sedangMenghitung = true;
      _pesanError = null;
      _elevasiNaik = null;
      _elevasiTurun = null;
    });

    try {
      // Layanan rute jalan kaki publik. Layanan dapat membatasi permintaan.
      final Uri alamatRute = Uri.parse(
        'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
        '${awal.longitude},${awal.latitude};'
        '${tujuan.longitude},${tujuan.latitude}',
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
        throw Exception('Layanan peta tidak merespons. Coba lagi nanti.');
      }

      final Map<String, dynamic> data =
          jsonDecode(jawaban.body) as Map<String, dynamic>;
      final List<dynamic> daftarRute = data['routes'] as List<dynamic>? ??
          <dynamic>[];
      if (data['code'] != 'Ok' || daftarRute.isEmpty) {
        throw Exception('Rute jalan kaki tidak ditemukan antara kedua titik.');
      }
      final Map<String, dynamic> rute =
          daftarRute.first as Map<String, dynamic>;
      final Map<String, dynamic> geometri =
          rute['geometry'] as Map<String, dynamic>;
      final List<dynamic> koordinat = geometri['coordinates'] as List<dynamic>;
      final List<LatLng> titikRute = koordinat.map((dynamic nilai) {
        final List<dynamic> xy = nilai as List<dynamic>;
        return LatLng((xy[1] as num).toDouble(), (xy[0] as num).toDouble());
      }).toList(growable: false);

      if (titikRute.length < 2) {
        throw Exception('Data jalur dari layanan peta belum lengkap.');
      }

      final double jarakMeter = (rute['distance'] as num).toDouble();
      double? naik;
      double? turun;
      try {
        final List<double> ketinggian = await _ambilPerkiraanElevasi(titikRute);
        if (ketinggian.length >= 2) {
          naik = 0;
          turun = 0;
          for (int i = 1; i < ketinggian.length; i++) {
            final double perubahan = ketinggian[i] - ketinggian[i - 1];
            // Abaikan perubahan kecil agar noise data elevasi tidak dihitung.
            if (perubahan >= 3) naik += perubahan;
            if (perubahan <= -3) turun += perubahan.abs();
          }
        }
      } catch (_) {
        // Jarak rute tetap bisa ditampilkan jika sumber elevasi sedang gagal.
      }

      if (!mounted) return;
      setState(() {
        _jalur = titikRute;
        _jarakMeter = jarakMeter;
        _elevasiNaik = naik;
        _elevasiTurun = turun;
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
          // Peta bisa belum selesai membuat kamera pada frame pertama.
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _pesanError = error.toString().replaceFirst('Exception: ', '');
          _jalur = <LatLng>[];
          _jarakMeter = null;
        });
      }
    } finally {
      if (mounted) setState(() => _sedangMenghitung = false);
    }
  }

  Future<List<double>> _ambilPerkiraanElevasi(List<LatLng> route) async {
    final List<LatLng> sampel = _ambilSampel(route, 24);
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
    final List<dynamic> hasil = data['results'] as List<dynamic>? ?? <dynamic>[];
    return hasil
        .map((dynamic item) =>
            (item as Map<String, dynamic>)['elevation'] as num)
        .map((num nilai) => nilai.toDouble())
        .toList(growable: false);
  }

  List<LatLng> _ambilSampel(List<LatLng> route, int jumlahMaksimum) {
    if (route.length <= jumlahMaksimum) return route;
    final List<LatLng> hasil = <LatLng>[];
    for (int i = 0; i < jumlahMaksimum; i++) {
      final double posisi = i * (route.length - 1) / (jumlahMaksimum - 1);
      hasil.add(route[posisi.round()]);
    }
    return hasil;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rencanakan rute')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(
                          () => _yangDipilih = _TitikYangDipilih.awal,
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _yangDipilih == _TitikYangDipilih.awal
                              ? VoltWarna.surface
                              : Colors.white,
                        ),
                        child: Text(
                          _titikAwal == null ? 'Pilih titik awal' : 'Ubah titik awal',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(
                          () => _yangDipilih = _TitikYangDipilih.tujuan,
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: _yangDipilih == _TitikYangDipilih.tujuan
                              ? VoltWarna.surface
                              : Colors.white,
                        ),
                        child: Text(
                          _titikTujuan == null ? 'Pilih tujuan' : 'Ubah tujuan',
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Pilih: ${_yangDipilih == _TitikYangDipilih.awal ? 'titik awal' : 'tujuan'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: VoltWarna.teksAbu,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          _sedangMengambilLokasi ? null : _gunakanLokasiSaatIni,
                      child: Text(
                        _sedangMengambilLokasi ? 'Mengambil lokasi…' : 'Lokasi saya',
                      ),
                    ),
                  ],
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
                ),
                if (_jalur.length > 1)
                  PolylineLayer(
                    polylines: <Polyline>[
                      Polyline(
                        points: _jalur,
                        strokeWidth: 4,
                        color: Colors.black,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: <Marker>[
                    if (_titikAwal case final LatLng awal)
                      Marker(
                        point: awal,
                        width: 34,
                        height: 34,
                        child: _penanda('A'),
                      ),
                    if (_titikTujuan case final LatLng tujuan)
                      Marker(
                        point: tujuan,
                        width: 34,
                        height: 34,
                        child: _penanda('B'),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: <SourceAttribution>[
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: VoltWarna.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_pesanError != null) ...<Widget>[
                  Text(
                    _pesanError!,
                    style: const TextStyle(fontSize: 12, color: Colors.black),
                  ),
                  const SizedBox(height: 8),
                ],
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
                          'Naik',
                          _elevasiNaik == null
                              ? '--'
                              : '${_elevasiNaik!.round()} m',
                        ),
                      ),
                      Expanded(
                        child: _hasilUkuran(
                          'Turun',
                          _elevasiTurun == null
                              ? '--'
                              : '${_elevasiTurun!.round()} m',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Elevasi adalah perkiraan perubahan naik-turun sepanjang rute, bukan ketinggian dari permukaan laut.',
                    style: TextStyle(color: VoltWarna.teksAbu, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sedangMenghitung ? null : _hitungRute,
                    child: Text(
                      _sedangMenghitung ? 'Menghitung rute…' : 'Hitung rute',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _penanda(String huruf) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.white, width: 2),
        shape: BoxShape.circle,
      ),
      child: Text(
        huruf,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _hasilUkuran(String label, String nilai) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(color: VoltWarna.teksAbu, fontSize: 11)),
        const SizedBox(height: 3),
        Text(nilai, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
      ],
    );
  }

  String _formatJarak(double meter) {
    if (meter >= 1000) return '${(meter / 1000).toStringAsFixed(2)} km';
    return '${meter.round()} m';
  }
}
