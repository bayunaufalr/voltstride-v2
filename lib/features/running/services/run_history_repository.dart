import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/run_session.dart';

/// Pesan khusus ketika aktivitas sudah aman tersimpan di perangkat,
/// tetapi proses pengiriman ke akun cloud belum berhasil.
class RunSyncException implements Exception {
  const RunSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Penyimpanan riwayat lari lokal berbasis SQLite.
///
/// Database disimpan di app-private storage Android. Data tetap ada setelah
/// aplikasi ditutup atau perangkat direstart, kecuali data aplikasi dihapus,
/// aplikasi dihapus instalasinya, atau sistem/perangkat menghapus data aplikasi.
class RunHistoryRepository {
  RunHistoryRepository._();

  static final RunHistoryRepository instance = RunHistoryRepository._();

  static const String _databaseName = 'voltstride_runs.db';
  static const String _tableName = 'run_sessions';
  static const int _databaseVersion = 6;
  static const String _backupFormat = 'voltstride-run-history';
  static const int _backupVersion = 1;

  Database? _database;

  /// ID akun yang sedang masuk. Jika Firebase belum siap, data tetap bisa
  /// diuji sebagai data lokal tanpa mencampurnya dengan akun sungguhan.
  String? get _akunAktifId {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  String get _pemilikPenyimpanan => _akunAktifId ?? 'guest';

  CollectionReference<Map<String, dynamic>> _koleksiAktivitas(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('runSessions');
  }

  String _idDokumenAktivitas(RunSession session) =>
      session.startedAt.toUtc().microsecondsSinceEpoch.toString();

  Future<void> _tulisAktivitasLokal(
    Database db,
    RunSession session,
    String pemilik,
  ) async {
    final Map<String, Object?> data = session.toStorageMap();
    data['userId'] = pemilik;
    await db.insert(
      _tableName,
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static const List<String> _kolomJsonUntukCloud = <String>[
    'routeJson',
    'splitsJson',
    'hundredMeterLapsJson',
    'intervalPlanJson',
    'activityMetricsJson',
  ];

  /// Memampatkan data GPS sebelum dikirim agar dokumen Firestore tidak mudah
  /// melewati batas ukuran. Salinan SQLite tetap memakai JSON biasa.
  Map<String, dynamic> _buatDataCloud(RunSession session) {
    final Map<String, Object?> data = session.toStorageMap();
    for (final String kolom in _kolomJsonUntukCloud) {
      final Object? nilai = data[kolom];
      if (nilai is String && nilai.isNotEmpty) {
        final List<int> hasilKompresi = gzip.encode(utf8.encode(nilai));
        data[kolom] = 'gz1:${base64Encode(hasilKompresi)}';
      }
    }
    data['versiKompresi'] = 1;

    // Periksa ukuran sebelum menambahkan waktu dari server.
    final Map<String, Object?> cekUkuran = Map<String, Object?>.from(data)
      ..['diperbaruiPada'] = '';
    final int ukuranBytes = utf8.encode(jsonEncode(cekUkuran)).length;
    if (ukuranBytes > 850 * 1024) {
      throw const RunSyncException(
        'Data aktivitas terlalu besar untuk satu catatan akun. Data asli tetap aman di perangkat.',
      );
    }

    data['diperbaruiPada'] = FieldValue.serverTimestamp();
    return Map<String, dynamic>.from(data);
  }

  /// Membuka kembali data JSON terkompresi. Data lama yang belum dikompres
  /// tetap dapat dibaca karena hanya nilai dengan awalan gz1: yang diproses.
  Map<String, Object?> _bukaDataCloud(Map<String, dynamic> dataCloud) {
    final Map<String, Object?> data = Map<String, Object?>.from(dataCloud);
    for (final String kolom in _kolomJsonUntukCloud) {
      final Object? nilai = data[kolom];
      if (nilai is! String || !nilai.startsWith('gz1:')) continue;
      try {
        final List<int> bytes = base64Decode(nilai.substring(4));
        data[kolom] = utf8.decode(gzip.decode(bytes));
      } on FormatException {
        throw const FormatException(
          'Data aktivitas dari akun tidak dapat dibaca. Coba sinkronkan kembali.',
        );
      }
    }
    return data;
  }

  Future<void> _unggahAktivitas(RunSession session, String uid) async {
    try {
      await _koleksiAktivitas(uid)
          .doc(_idDokumenAktivitas(session))
          .set(_buatDataCloud(session), SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const RunSyncException(
        'Aktivitas tersimpan di perangkat, tetapi sinkronisasi belum terkonfirmasi. Periksa internet lalu coba sinkronkan lagi dari tab Anda.',
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const RunSyncException(
          'Aktivitas tersimpan di perangkat, tetapi Firebase menolak akses. Periksa aturan Firestore pada users/{uid}/runSessions.',
        );
      }
      if (error.code == 'resource-exhausted') {
        throw const RunSyncException(
          'Batas pemakaian Firebase tercapai. Aktivitas tetap tersimpan di perangkat.',
        );
      }
      if (error.code == 'invalid-argument' || error.code == 'out-of-range') {
        throw const RunSyncException(
          'Firebase menolak ukuran atau format data aktivitas. Data asli tetap aman di perangkat.',
        );
      }
      if (error.code == 'unavailable' || error.code == 'deadline-exceeded') {
        throw const RunSyncException(
          'Aktivitas tersimpan di perangkat, tetapi Firebase tidak dapat dijangkau. Periksa koneksi lalu coba lagi.',
        );
      }
      throw RunSyncException(
        'Aktivitas tersimpan di perangkat, tetapi belum tersinkron ke akun (kode ${error.code}).',
      );
    } on RunSyncException {
      rethrow;
    } catch (error) {
      // Tampilkan penyebab tambahan agar masalah tidak selalu terlihat sebagai
      // kegagalan internet, padahal bisa berasal dari format data atau layanan.
      final String detail = error.toString();
      final String detailRingkas = detail.length > 180
          ? '${detail.substring(0, 180)}…'
          : detail;
      throw RunSyncException(
        'Aktivitas tetap tersimpan di perangkat, tetapi belum tersinkron. '
        'Rincian: $detailRingkas',
      );
    }
  }

  Future<void> _hapusAktivitasLokal(
    Database db,
    RunSession session, {
    required String pemilik,
    String? waktuMulaiDiDatabase,
  }) async {
    // Untuk baris guest, gunakan teks tanggal persis dari SQLite. Ini mencegah
    // salinan lama tertinggal karena format tanggal berbeda saat dibaca ulang.
    await db.delete(
      _tableName,
      where: 'startedAt = ? AND userId = ?',
      whereArgs: <Object?>[
        waktuMulaiDiDatabase ?? session.startedAt.toUtc().toIso8601String(),
        pemilik,
      ],
    );
  }

  Future<List<RunSession>> _bacaAktivitasLokal(
    Database db, {
    required String pemilik,
  }) async {
    final List<Map<String, Object?>> rows = await db.query(
      _tableName,
      where: 'userId = ?',
      whereArgs: <Object?>[pemilik],
      orderBy: 'startedAt DESC',
    );
    return rows.map(RunSession.fromStorageMap).toList(growable: false);
  }

  Future<String> get databasePath async {
    final String basePath = await getDatabasesPath();
    return path.join(basePath, _databaseName);
  }

  Future<Database> get _db async {
    final Database? current = _database;
    if (current != null && current.isOpen) return current;

    final String databasePath = await this.databasePath;
    final Database opened = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            startedAt TEXT NOT NULL,
            userId TEXT NOT NULL DEFAULT 'guest',
            finishedAt TEXT,
            distanceMeters REAL NOT NULL,
            elapsedMilliseconds INTEGER NOT NULL,
            movingMilliseconds INTEGER NOT NULL,
            averagePaceSecondsPerKm REAL,
            currentPaceSecondsPerKm REAL,
            gpsAccuracyMeters REAL,
            acceptedPoints INTEGER NOT NULL,
            rejectedPoints INTEGER NOT NULL,
            routeJson TEXT NOT NULL,
            splitsJson TEXT NOT NULL,
            hundredMeterLapsJson TEXT NOT NULL DEFAULT '[]',
            intervalPlanJson TEXT,
            activityType TEXT NOT NULL DEFAULT 'run',
            environment TEXT NOT NULL DEFAULT 'outdoor',
            activityMetricsJson TEXT NOT NULL DEFAULT '{}',
            PRIMARY KEY (startedAt, userId)
          )
        ''');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN hundredMeterLapsJson TEXT NOT NULL DEFAULT '[]'",
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN intervalPlanJson TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN activityType TEXT NOT NULL DEFAULT 'run'",
          );
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN environment TEXT NOT NULL DEFAULT 'outdoor'",
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN activityMetricsJson TEXT NOT NULL DEFAULT '{}'",
          );
        }
        if (oldVersion < 5) {
          // Riwayat lama diberi label guest agar tidak otomatis masuk ke akun
          // tertentu sebelum pemilik perangkat menyetujuinya.
          await db.execute(
            "ALTER TABLE $_tableName ADD COLUMN userId TEXT NOT NULL DEFAULT 'guest'",
          );
        }
        if (oldVersion < 6) {
          // Kunci gabungan mencegah dua akun di satu perangkat saling menimpa
          // jika kebetulan menyimpan aktivitas pada waktu mulai yang sama.
          await db.execute(
            'ALTER TABLE $_tableName RENAME TO ${_tableName}_previous',
          );
          await db.execute('''
            CREATE TABLE $_tableName (
              startedAt TEXT NOT NULL,
              userId TEXT NOT NULL DEFAULT 'guest',
              finishedAt TEXT,
              distanceMeters REAL NOT NULL,
              elapsedMilliseconds INTEGER NOT NULL,
              movingMilliseconds INTEGER NOT NULL,
              averagePaceSecondsPerKm REAL,
              currentPaceSecondsPerKm REAL,
              gpsAccuracyMeters REAL,
              acceptedPoints INTEGER NOT NULL,
              rejectedPoints INTEGER NOT NULL,
              routeJson TEXT NOT NULL,
              splitsJson TEXT NOT NULL,
              hundredMeterLapsJson TEXT NOT NULL DEFAULT '[]',
              intervalPlanJson TEXT,
              activityType TEXT NOT NULL DEFAULT 'run',
              environment TEXT NOT NULL DEFAULT 'outdoor',
              activityMetricsJson TEXT NOT NULL DEFAULT '{}',
              PRIMARY KEY (startedAt, userId)
            )
          ''');
          await db.execute('''
            INSERT INTO $_tableName (
              startedAt, userId, finishedAt, distanceMeters,
              elapsedMilliseconds, movingMilliseconds,
              averagePaceSecondsPerKm, currentPaceSecondsPerKm,
              gpsAccuracyMeters, acceptedPoints, rejectedPoints,
              routeJson, splitsJson, hundredMeterLapsJson,
              intervalPlanJson, activityType, environment, activityMetricsJson
            )
            SELECT
              startedAt, userId, finishedAt, distanceMeters,
              elapsedMilliseconds, movingMilliseconds,
              averagePaceSecondsPerKm, currentPaceSecondsPerKm,
              gpsAccuracyMeters, acceptedPoints, rejectedPoints,
              routeJson, splitsJson, hundredMeterLapsJson,
              intervalPlanJson, activityType, environment, activityMetricsJson
            FROM ${_tableName}_previous
          ''');
          await db.execute('DROP TABLE ${_tableName}_previous');
        }
      },
    );
    _database = opened;
    return opened;
  }

  /// Menyimpan aktivitas ke perangkat dan, bila sudah login, ke akun Firebase.
  Future<void> save(RunSession session) async {
    final Database db = await _db;
    final String? uid = _akunAktifId;
    final String pemilik = uid ?? 'guest';

    // Simpan di perangkat lebih dulu. Dengan begitu, rekaman GPS tidak hilang
    // hanya karena jaringan sedang bermasalah.
    await _tulisAktivitasLokal(db, session, pemilik);

    // Saat pengguna masuk, salin data yang sama ke ruang milik akun tersebut.
    if (uid != null) await _unggahAktivitas(session, uid);
  }

  /// Mengambil riwayat milik akun aktif, lalu memperbarui salinan lokal.
  /// Saat internet tidak tersedia, aplikasi tetap memakai data di perangkat.
  Future<List<RunSession>> getAll({int? limit}) async {
    final Database db = await _db;
    final String? uid = _akunAktifId;
    final String pemilik = uid ?? 'guest';
    final List<RunSession> aktivitasLokal = await _bacaAktivitasLokal(
      db,
      pemilik: pemilik,
    );

    if (uid == null) return _batasiRiwayat(aktivitasLokal, limit);

    final Map<String, RunSession> semuaAktivitas = <String, RunSession>{
      for (final RunSession session in aktivitasLokal)
        session.startedAt.toUtc().toIso8601String(): session,
    };

    try {
      Query<Map<String, dynamic>> permintaan = _koleksiAktivitas(uid)
          .orderBy('startedAt', descending: true);
      if (limit != null && limit > 0) {
        permintaan = permintaan.limit(limit);
      }

      final QuerySnapshot<Map<String, dynamic>> hasil = await permintaan
          .get()
          .timeout(const Duration(seconds: 10));
      final Set<String> idCloudTersedia = hasil.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> dokumen) => dokumen.id)
          .toSet();

      for (final QueryDocumentSnapshot<Map<String, dynamic>> dokumen
          in hasil.docs) {
        try {
          final RunSession session = RunSession.fromStorageMap(
            _bukaDataCloud(dokumen.data()),
          );
          final String kunci = session.startedAt.toUtc().toIso8601String();
          semuaAktivitas[kunci] = session;
          await _tulisAktivitasLokal(db, session, uid);
        } catch (_) {
          // Satu catatan yang rusak tidak boleh membuat seluruh riwayat hilang.
        }
      }

      // Tanpa batas jumlah, pencarian riwayat juga mencoba mengirim catatan
      // lokal yang belum ada di cloud. Ini membantu pemulihan setelah offline.
      if (limit == null && !hasil.metadata.isFromCache) {
        for (final RunSession session in aktivitasLokal) {
          if (idCloudTersedia.contains(_idDokumenAktivitas(session))) continue;
          try {
            await _unggahAktivitas(session, uid);
          } catch (_) {
            // Riwayat lokal tetap ditampilkan jika pengiriman masih gagal.
          }
        }
      }
    } catch (_) {
      // Jika cloud sedang tidak bisa diakses, tampilkan salinan lokal.
    }

    final List<RunSession> hasilAkhir = semuaAktivitas.values.toList()
      ..sort((RunSession a, RunSession b) => b.startedAt.compareTo(a.startedAt));
    return _batasiRiwayat(hasilAkhir, limit);
  }

  List<RunSession> _batasiRiwayat(List<RunSession> aktivitas, int? limit) {
    final List<RunSession> terurut = List<RunSession>.of(aktivitas)
      ..sort((RunSession a, RunSession b) => b.startedAt.compareTo(a.startedAt));
    if (limit == null || limit <= 0 || terurut.length <= limit) return terurut;
    return terurut.take(limit).toList(growable: false);
  }

  /// Menghapus aktivitas dari akun dan perangkat.
  Future<void> delete(DateTime startedAt) async {
    final Database db = await _db;
    final String? uid = _akunAktifId;

    if (uid != null) {
      try {
        await _koleksiAktivitas(uid)
            .doc(startedAt.toUtc().microsecondsSinceEpoch.toString())
            .delete()
            .timeout(const Duration(seconds: 10));
      } on TimeoutException {
        throw const RunSyncException(
          'Penghapusan dari akun belum terkonfirmasi. Data perangkat belum dihapus.',
        );
      } catch (_) {
        throw const RunSyncException(
          'Aktivitas belum dapat dihapus dari akun. Periksa koneksi internet lalu coba lagi.',
        );
      }
    }

    await db.delete(
      _tableName,
      where: 'startedAt = ? AND userId = ?',
      whereArgs: <Object?>[
        startedAt.toUtc().toIso8601String(),
        _pemilikPenyimpanan,
      ],
    );
  }

  /// Menghitung catatan perangkat yang belum beres dipindahkan ke akun.
  /// Catatan guest tetap dihitung meskipun sudah ada di cloud, karena salinan
  /// perangkatnya masih perlu dipindahkan ke pemilik akun lalu dibersihkan.
  Future<int> pendingSessionCount() async {
    final Database db = await _db;
    final String? uid = _akunAktifId;
    final List<Map<String, Object?>> guestRows = await db.query(
      _tableName,
      where: "userId = 'guest'",
      orderBy: 'startedAt ASC',
    );
    final List<RunSession> guestSessions = guestRows
        .map(RunSession.fromStorageMap)
        .toList(growable: false);

    if (uid == null) return guestSessions.length;

    final List<RunSession> aktivitasAkun = await _bacaAktivitasLokal(
      db,
      pemilik: uid,
    );

    try {
      final QuerySnapshot<Map<String, dynamic>> cloud =
          await _koleksiAktivitas(uid).get().timeout(
                const Duration(seconds: 10),
              );
      final Set<String> idCloud = cloud.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id)
          .toSet();
      final Set<String> menunggu = <String>{
        for (final RunSession session in guestSessions)
          _idDokumenAktivitas(session),
        for (final RunSession session in aktivitasAkun)
          if (!idCloud.contains(_idDokumenAktivitas(session)))
            _idDokumenAktivitas(session),
      };
      return menunggu.length;
    } catch (_) {
      // Bila cloud belum bisa diperiksa, jangan sembunyikan catatan lokal.
      return <String>{
        ...guestSessions.map(_idDokumenAktivitas),
        ...aktivitasAkun.map(_idDokumenAktivitas),
      }.length;
    }
  }

  /// Nama lama tetap disediakan untuk kode yang masih memakainya.
  Future<int> legacySessionCount() => pendingSessionCount();

  /// Memindahkan aktivitas lama dari perangkat ke akun yang sedang dibuka.
  /// Satu catatan yang gagal tidak menghentikan catatan lain yang bisa dipindah.
  /// Data guest baru dihapus setelah unggahan atau pemeriksaan cloud berhasil.
  Future<int> syncPendingSessionsToAccount() async {
    final String? uid = _akunAktifId;
    if (uid == null) {
      throw const RunSyncException(
        'Masuk ke akun sebelum memindahkan aktivitas.',
      );
    }

    final Database db = await _db;
    final List<Map<String, Object?>> guestRows = await db.query(
      _tableName,
      where: "userId = 'guest'",
      orderBy: 'startedAt ASC',
    );
    final List<Map<String, Object?>> akunRows = await db.query(
      _tableName,
      where: 'userId = ?',
      whereArgs: <Object?>[uid],
      orderBy: 'startedAt ASC',
    );

    final Map<String, RunSession> sesiPerId = <String, RunSession>{};
    final Map<String, String> waktuMulaiGuest = <String, String>{};
    final Set<String> idGuest = <String>{};

    // Utamakan data asli yang masih berlabel guest jika ada ID yang sama.
    for (final Map<String, Object?> row in guestRows) {
      final RunSession session = RunSession.fromStorageMap(row);
      final String id = _idDokumenAktivitas(session);
      sesiPerId[id] = session;
      idGuest.add(id);
      final Object? waktuMulai = row['startedAt'];
      if (waktuMulai is String) waktuMulaiGuest[id] = waktuMulai;
    }

    // Aktivitas milik akun juga diproses jika ada di perangkat tetapi belum
    // terkirim ke cloud. Jangan menimpa salinan guest yang mungkin lebih utuh.
    for (final Map<String, Object?> row in akunRows) {
      final RunSession session = RunSession.fromStorageMap(row);
      sesiPerId.putIfAbsent(_idDokumenAktivitas(session), () => session);
    }

    Set<String> idCloud = <String>{};
    bool pemeriksaanCloudBerhasil = false;
    try {
      final QuerySnapshot<Map<String, dynamic>> cloud =
          await _koleksiAktivitas(uid).get().timeout(
                const Duration(seconds: 10),
              );
      idCloud = cloud.docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id)
          .toSet();
      pemeriksaanCloudBerhasil = true;
    } catch (_) {
      // Jika daftar cloud tidak bisa dibaca, coba kirim satu per satu. Data
      // lokal tidak akan dihapus jika unggahannya gagal.
    }

    int jumlahBerhasil = 0;
    int jumlahGagal = 0;
    Object? kesalahanPertama;

    for (final MapEntry<String, RunSession> entri in sesiPerId.entries) {
      final String id = entri.key;
      final RunSession session = entri.value;
      final bool berasalDariGuest = idGuest.contains(id);
      final bool sudahAdaDiCloud = pemeriksaanCloudBerhasil && idCloud.contains(id);
      final bool perluDikirim = !sudahAdaDiCloud;

      try {
        // Jika data sudah ada di akun, cukup bereskan salinan guest di perangkat.
        // Pengiriman ulang hanya dilakukan bila dokumen belum ada atau daftar
        // cloud tidak berhasil dibaca.
        if (perluDikirim) {
          await _unggahAktivitas(session, uid);
          idCloud.add(id);
        }

        await _tulisAktivitasLokal(db, session, uid);
        if (berasalDariGuest) {
          await _hapusAktivitasLokal(
            db,
            session,
            pemilik: 'guest',
            waktuMulaiDiDatabase: waktuMulaiGuest[id],
          );
        }
        if (berasalDariGuest || perluDikirim) jumlahBerhasil++;
      } catch (error) {
        jumlahGagal++;
        kesalahanPertama ??= error;
        // Aktivitas ini tetap dipertahankan di perangkat dan tidak menghalangi
        // aktivitas lain yang masih bisa disinkronkan.
      }
    }

    if (jumlahGagal > 0) {
      final String detail = kesalahanPertama?.toString() ?? 'Penyebab belum diketahui.';
      throw RunSyncException(
        '$jumlahBerhasil aktivitas berhasil dipindahkan. '
        '$jumlahGagal aktivitas belum tersinkron dan tetap disimpan di perangkat. '
        'Rincian: $detail',
      );
    }

    return jumlahBerhasil;
  }

  /// Nama lama tetap didukung agar tombol pada versi terdahulu tidak rusak.
  Future<int> importLegacyHistoryToAccount() => syncPendingSessionsToAccount();

  /// Membuat file cadangan JSON yang bisa disimpan di luar data aplikasi.
  /// Cadangan tidak mengandung API key atau data akun.
  Future<String> exportBackupJson() async {
    final List<RunSession> sessions = await getAll();
    final Map<String, Object?> backup = <String, Object?>{
      'format': _backupFormat,
      'version': _backupVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sessionCount': sessions.length,
      'sessions': sessions
          .map((RunSession session) => session.toStorageMap())
          .toList(growable: false),
    };

    return const JsonEncoder.withIndent('  ').convert(backup);
  }

  /// Menggabungkan cadangan yang valid tanpa menghapus sesi yang sudah ada.
  /// Jika startedAt sama, sesi dari cadangan menggantikan baris dengan kunci itu.
  Future<int> importBackupJson(String contents) async {
    final dynamic decoded;
    try {
      decoded = jsonDecode(contents);
    } on FormatException {
      throw const FormatException('File bukan JSON cadangan yang valid.');
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _backupFormat ||
        decoded['version'] != _backupVersion ||
        decoded['sessions'] is! List<dynamic>) {
      throw const FormatException(
        'Format cadangan tidak cocok dengan VoltStride.',
      );
    }

    final List<dynamic> rawSessions = decoded['sessions'] as List<dynamic>;
    final List<RunSession> sessions = <RunSession>[];

    try {
      for (final dynamic raw in rawSessions) {
        if (raw is! Map<String, dynamic>) {
          throw const FormatException('Ada sesi dengan format yang salah.');
        }
        sessions.add(
          RunSession.fromStorageMap(Map<String, Object?>.from(raw)),
        );
      }
    } catch (error) {
      if (error is FormatException) rethrow;
      throw const FormatException(
        'Data sesi di dalam cadangan rusak atau tidak lengkap.',
      );
    }

    final Database db = await _db;
    final String? uid = _akunAktifId;
    final String pemilik = uid ?? 'guest';
    await db.transaction((Transaction transaction) async {
      for (final RunSession session in sessions) {
        final Map<String, Object?> data = session.toStorageMap();
        data['userId'] = pemilik;
        await transaction.insert(
          _tableName,
          data,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    if (uid != null) {
      for (final RunSession session in sessions) {
        await _unggahAktivitas(session, uid);
      }
    }

    return sessions.length;
  }

  /// Informasi diagnostik untuk membedakan database kosong dari database error.
  Future<Map<String, Object?>> diagnostics() async {
    final Database db = await _db;
    final String filePath = await databasePath;
    final File file = File(filePath);
    final List<Map<String, Object?>> countRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $_tableName WHERE userId = ?',
      <Object?>[_pemilikPenyimpanan],
    );
    final List<Map<String, Object?>> integrityRows =
        await db.rawQuery('PRAGMA quick_check');
    final List<Map<String, Object?>> versionRows =
        await db.rawQuery('SELECT sqlite_version() AS version');

    return <String, Object?>{
      'databasePath': filePath,
      'fileExists': await file.exists(),
      'fileSizeBytes': await file.exists() ? await file.length() : 0,
      'sessionCount': Sqflite.firstIntValue(countRows) ?? 0,
      'integrity': integrityRows.isEmpty
          ? 'unknown'
          : integrityRows.first.values.first.toString(),
      'sqliteVersion': versionRows.isEmpty
          ? 'unknown'
          : versionRows.first['version']?.toString() ?? 'unknown',
    };
  }

  Future<void> close() async {
    final Database? db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
