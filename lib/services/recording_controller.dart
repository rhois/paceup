import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:uuid/uuid.dart';

import '../core/geo.dart';
import '../core/metrics.dart';
import '../data/models/models.dart';
import 'location_service.dart';

/// Status perekaman yang dipakai UI untuk menggambar tombol & layar.
enum RecordingStatus { idle, preparing, recording, paused, finished }

extension RecordingStatusX on RecordingStatus {
  bool get isActive =>
      this == RecordingStatus.recording || this == RecordingStatus.paused;
  String get label => switch (this) {
        RecordingStatus.idle => 'SIAP',
        RecordingStatus.preparing => 'MENCARI SINYAL…',
        RecordingStatus.recording => 'MEREKAM',
        RecordingStatus.paused => 'DIJEDA',
        RecordingStatus.finished => 'SELESAI',
      };
}

/// Pengendali perekaman aktivitas.
///
/// Tanggung jawab:
/// * Mengalirkan fix GPS dari [LocationService] ke [GpsFilter].
/// * Menghitung jarak, pace, kecepatan, elevasi, kalori secara real time.
/// * Menyediakan jeda (pause) & auto-pause saat pengguna berhenti.
/// * Menyimpan hasil akhir menjadi [Activity] (+ titik GPS).
///
/// Kelas ini sengaja tidak tahu apa-apa soal backend; penyimpanan dilakukan
/// oleh lapisan repository melalui callback [onFinish].
class RecordingController extends ChangeNotifier {
  RecordingController({
    LocationService? locationService,
    GpsFilterConfig filterConfig = const GpsFilterConfig(),
    this.autoPauseEnabled = true,
    this.autoPauseSpeedThreshold = 0.7, // m/s (~2.5 km/jam)
    this.autoResumeSpeedThreshold = 1.1, // m/s
  })  : _location = locationService ?? LocationService(),
        _filter = GpsFilter(config: filterConfig);

  final LocationService _location;
  final GpsFilter _filter;
  final _uuid = const Uuid();

  // --- konfigurasi ---
  final bool autoPauseEnabled;
  final double autoPauseSpeedThreshold;
  final double autoResumeSpeedThreshold;

  // --- state ---
  RecordingStatus _status = RecordingStatus.idle;
  ActivityType _type = ActivityType.run;
  final List<RunPoint> _points = [];
  double _distanceMeters = 0;  Duration _movingDuration = Duration.zero;
  Duration _elapsedDuration = Duration.zero;
  double _currentSpeedMps = 0;
  double _maxSpeedMps = 0;
  double _elevationGain = 0;
  double _elevationLoss = 0;
  double _lastAltitude = 0;
  double _currentPaceSecPerKm = 0;
  int _cadence = 0;
  double _accuracy = 0;
  int _acceptedPoints = 0;
  int _rejectedPoints = 0;
  String? _lastRejectReason;
  DateTime? _startedAt;
  StreamSubscription<RawFix>? _sub;
  Timer? _autoPauseTimer;
  bool _autoPaused = false;
  final List<int> _recentCadence = [];

  /// Jenis aktivitas terdeteksi otomatis (dapat diubah pengguna).
  bool _typeAutoDetected = true;

  // --- getter ---
  RecordingStatus get status => _status;
  ActivityType get type => _type;
  List<RunPoint> get points => List.unmodifiable(_points);
  double get distanceMeters => _distanceMeters;
  Duration get movingDuration => _movingDuration;
  Duration get elapsedDuration => _elapsedDuration;
  double get currentSpeedKmh => _currentSpeedMps * 3.6;
  double get maxSpeedKmh => _maxSpeedMps * 3.6;
  double get currentPaceSecPerKm => _currentPaceSecPerKm;
  double get elevationGain => _elevationGain;
  double get elevationLoss => _elevationLoss;
  int get cadence => _cadence;
  double get accuracy => _accuracy;
  int get acceptedPoints => _acceptedPoints;
  int get rejectedPoints => _rejectedPoints;
  String? get lastRejectReason => _lastRejectReason;
  DateTime? get startedAt => _startedAt;
  bool get isAutoPaused => _autoPaused;
  bool get isEmpty => _distanceMeters < 5 && _points.length < 3;

  /// Pace rata-rata (detik/km) sepanjang sesi.
  double get avgPaceSecPerKm {
    if (_distanceMeters <= 0) return 0;
    return _movingDuration.inMilliseconds / 1000.0 / (_distanceMeters / 1000.0);
  }

  double get avgSpeedKmh {
    final h = _movingDuration.inMilliseconds / 3600000.0;
    if (h <= 0) return 0;
    return (_distanceMeters / 1000.0) / h;
  }

  int get calories => MetricsEngine.estimateCalories(
        distanceMeters: _distanceMeters,
        movingSeconds: _movingDuration.inMilliseconds / 1000.0,
        weightKg: _weightKg,
        avgSpeedMps: avgSpeedKmh / 3.6,
      );

  double _weightKg = 65;

  /// Berat badan dipakai untuk kalori & VO2max.
  set weightKg(double v) {
    _weightKg = v <= 0 ? 65 : v;
    notifyListeners();
  }

  /// Split yang sudah selesai (per km).
  List<Split> get splits =>
      MetricsEngine.computeSplits(_points, 1000).where((s) => !s.partial).toList();

  /// Ringkasan metrik saat ini — dipakai halaman ringkasan & simpan.
  RunMetrics get metrics => MetricsEngine.compute(
        _points,
        weightKg: _weightKg,
        avgHeartRate: 0,
      );

  /// Pola kecepatan (km/jam) untuk grafik kecil di layar rekam.
  double get accuracyQuality {
    if (_accuracy <= 0) return 0;
    return (1 - (_accuracy / 35).clamp(0, 1)).toDouble();
  }

  // ------------------------------------------------------------------ setup
  /// Siapkan GPS sebelum merekam (tanpa mengubah status ke recording).
  Future<void> prepare() async {
    if (_status.isActive) return;
    _status = RecordingStatus.preparing;
    notifyListeners();
    try {
      await _location.ensurePermission();
      final fix = await _location.currentFix();
      if (fix != null) {
        _accuracy = fix.accuracy;
        _lastAltitude = fix.altitude;
        // Titik awal tidak dihitung sebagai jarak.
        _filter.reset();
        _points
          ..clear()
          ..add(RunPoint(
            lat: fix.lat,
            lon: fix.lon,
            recordedAt: fix.timestamp,
            altitude: fix.altitude,
            accuracy: fix.accuracy,
          ));
        _filter.process(fix);
      }
    } catch (e) {
      _status = RecordingStatus.idle;
      notifyListeners();
      rethrow;
    }
  }

  /// Ubah jenis aktivitas secara manual (matikan auto-detect).
  void setType(ActivityType type, {bool manual = true}) {
    _type = type;
    if (manual) _typeAutoDetected = false;
    notifyListeners();
  }

  /// Mulai merekam. Memanggil [prepare] bila perlu.
  Future<void> start() async {
    if (_status.isActive) return;
    if (_points.isEmpty) {
      await prepare();
    }
    _startedAt ??= DateTime.now();
    _status = RecordingStatus.recording;
    _autoPaused = false;
    notifyListeners();

    await _location.start();
    _sub?.cancel();
    _sub = _location.fixes.listen(_onFix, onError: (Object e) {
      debugPrint('GPS error: $e');
    });
    _startTimer();
  }

  /// Alias agar mudah dipakai dari UI.
  Future<void> startNow() => start();

  void pause() {
    if (_status != RecordingStatus.recording) return;
    _status = RecordingStatus.paused;
    _filter.reset(); // hindari lompatan jarak setelah jeda
    notifyListeners();
  }

  void resume() {
    if (_status != RecordingStatus.paused) return;
    _status = RecordingStatus.recording;
    _autoPaused = false;
    notifyListeners();
  }

  void togglePause() {
    if (_status == RecordingStatus.recording) {
      pause();
    } else if (_status == RecordingStatus.paused) {
      resume();
    }
  }

  /// Hentikan perekaman dan kembalikan aktivitas siap simpan.
  Future<Activity> stop({String? title}) async {
    _autoPauseTimer?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _location.stop();
    _status = RecordingStatus.finished;
    notifyListeners();
    return buildActivity(title: title);
  }

  /// Bangun objek [Activity] dari metrik terkini.
  Activity buildActivity({String? title, String description = ''}) {
    final m = metrics;
    return Activity(
      id: _uuid.v4(),
      userId: 'me',
      type: _type,
      startedAt: _startedAt ?? DateTime.now(),
      title: title ?? _defaultTitle(),
      description: description,
      distanceMeters: m.distanceMeters,
      movingSeconds: m.movingDuration.inSeconds,
      elapsedSeconds: m.elapsedDuration.inSeconds,
      elevationGain: m.elevationGain,
      elevationLoss: m.elevationLoss,
      avgPaceSecPerKm: m.avgMovingPaceSecPerKm,
      maxSpeedKmh: m.maxSpeedKmh,
      avgHeartRate: m.avgHeartRate,
      avgCadenceSpm: m.avgCadenceSpm,
      calories: m.calories,
      mapPolyline: PolylineCodec.encode(_points),
      points: List.of(_points),
      createdAt: DateTime.now(),
    );
  }

  /// Buang sesi berjalan (mis. pengguna menekan "buang").
  void discard() {
    _autoPauseTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _location.stop();
    _filter.reset();
    _points.clear();
    _distanceMeters = 0;
    _movingDuration = Duration.zero;
    _elapsedDuration = Duration.zero;
    _currentSpeedMps = 0;
    _maxSpeedMps = 0;
    _elevationGain = 0;
    _elevationLoss = 0;
    _currentPaceSecPerKm = 0;
    _acceptedPoints = 0;
    _rejectedPoints = 0;
    _lastRejectReason = null;
    _startedAt = null;
    _recentCadence.clear();
    _cadence = 0;
    _status = RecordingStatus.idle;
    _typeAutoDetected = true;
    _autoPaused = false;
    notifyListeners();
  }

  // ------------------------------------------------------------------- loop
  void _onFix(RawFix raw) {
    if (_status != RecordingStatus.recording) return;

    final filtered = _filter.process(raw);
    _accuracy = raw.accuracy;

    if (!filtered.accepted) {
      _rejectedPoints++;
      _lastRejectReason = filtered.rejectReason;
      notifyListeners();
      return;
    }

    _acceptedPoints++;
    _lastRejectReason = null;

    if (filtered.moving) {
      _distanceMeters = filtered.cumulativeDistance;
      _currentSpeedMps = filtered.speedMps;
      if (filtered.speedMps > _maxSpeedMps) _maxSpeedMps = filtered.speedMps;

      // Pace sesaat dari kecepatan terhalus.
      _currentPaceSecPerKm =
          filtered.speedMps > 0.5 ? 1000 / filtered.speedMps : 0;

      // Elevasi dengan ambang noise 2 m.
      if (_lastAltitude != 0 && raw.altitude != 0) {
        final d = raw.altitude - _lastAltitude;
        if (d >= 2) {
          _elevationGain += d;
        } else if (d <= -2) {
          _elevationLoss += d.abs();
        }
      }
      if (raw.altitude != 0) _lastAltitude = raw.altitude;

      _pushCadence(_estimateCadence(filtered.speedMps));
      _points.add(RunPoint(
        lat: filtered.lat,
        lon: filtered.lon,
        recordedAt: filtered.timestamp,
        altitude: raw.altitude,
        speedMps: filtered.speedMps,
        distanceDelta: filtered.distanceDelta,
        accuracy: raw.accuracy,
        cadence: _cadence,
      ));

      // Deteksi jenis aktivitas otomatis pada 20 detik pertama.
      if (_typeAutoDetected && _movingDuration.inSeconds <= 20) {
        final detected = detectActivityType(avgSpeedKmh);
        if (detected != _type && avgSpeedKmh > 4) {
          _type = detected;
        }
      }

      _handleAutoPause(filtered.speedMps);
    } else {
      // Berhenti: catat sebagai titik agar elapsed time tetap akurat.
      _currentSpeedMps = 0;
      _currentPaceSecPerKm = 0;
      _points.add(RunPoint(
        lat: filtered.lat,
        lon: filtered.lon,
        recordedAt: filtered.timestamp,
        altitude: raw.altitude,
        speedMps: 0,
        distanceDelta: 0,
        accuracy: raw.accuracy,
      ));
    }

    _recomputeDurations();
    notifyListeners();
  }

  void _recomputeDurations() {
    if (_points.length < 2) return;
    var movingMs = 0;
    var elevGain = 0.0;
    var elevLoss = 0.0;
    for (var i = 1; i < _points.length; i++) {
      final prev = _points[i - 1];
      final cur = _points[i];
      final dt = cur.recordedAt.difference(prev.recordedAt).inMilliseconds;
      if (dt <= 0) continue;
      final segSpeed = cur.speedMps > 0
          ? cur.speedMps
          : cur.distanceDelta / (dt / 1000.0);
      if (segSpeed >= autoPauseSpeedThreshold) movingMs += dt;

      if (prev.altitude != 0 && cur.altitude != 0) {
        final d = cur.altitude - prev.altitude;
        if (d >= 2) elevGain += d;
        if (d <= -2) elevLoss += d.abs();
      }
    }
    _movingDuration = Duration(milliseconds: movingMs);
    _elapsedDuration =
        _points.last.recordedAt.difference(_points.first.recordedAt);
    _elevationGain = elevGain;
    _elevationLoss = elevLoss;
  }

  /// Auto-pause: hentikan hitungan saat pengguna benar-benar berhenti.
  void _handleAutoPause(double speed) {
    if (!autoPauseEnabled) return;

    if (!_autoPaused && speed < autoPauseSpeedThreshold) {
      _autoPauseTimer?.cancel();
      _autoPauseTimer = Timer(const Duration(seconds: 10), () {
        if (_status != RecordingStatus.recording) return;
        if (_currentSpeedMps < autoPauseSpeedThreshold) {
          _autoPaused = true;
          notifyListeners();
        }
      });
    } else if (_autoPaused && speed > autoResumeSpeedThreshold) {
      _autoPauseTimer?.cancel();
      _autoPaused = false;
      notifyListeners();
    } else if (speed >= autoPauseSpeedThreshold) {
      _autoPauseTimer?.cancel();
    }
  }

  /// Timer 1 detik supaya durasi tetap berjalan walau GPS tidak update
  /// (mis. saat pengguna berhenti di bawah pohon).
  void _startTimer() {
    _autoPauseTimer?.cancel();
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (_status == RecordingStatus.idle ||
          _status == RecordingStatus.finished) {
        t.cancel();
        return;
      }
      if (_status == RecordingStatus.recording &&
          _points.isNotEmpty &&
          !_autoPaused) {
        _elapsedDuration =
            DateTime.now().difference(_points.first.recordedAt);
        notifyListeners();
      }
    });
  }

  void _pushCadence(int value) {
    if (value <= 0) return;
    _recentCadence.add(value);
    if (_recentCadence.length > 8) _recentCadence.removeAt(0);
    _cadence =
        (_recentCadence.reduce((a, b) => a + b) / _recentCadence.length).round();
  }

  /// Perkirakan langkah per menit dari kecepatan.
  ///
  /// Pelari umumnya punya panjang langkah ~0.9-1.4 m dan cadence 160-190 spm.
  /// Estimasi ini menggantikan sensor pedometer (yang butuh izin tambahan
  /// dan tidak selalu tersedia).
  int _estimateCadence(double speedMps) {
    if (speedMps < 0.8) return 0;
    final stride = 0.75 + math.min(speedMps, 5.0) * 0.13;
    final spm = (speedMps / stride) * 60;
    return spm.clamp(120, 210).round();
  }

  String _defaultTitle() {
    final hour = (_startedAt ?? DateTime.now()).hour;
    final slot = switch (hour) {
      < 11 => 'Morning run',
      < 15 => 'Midday run',
      < 19 => 'Afternoon run',
      _ => 'Evening run',
    };
    return slot;
  }

  bool _disposed = false;

  @override
  void dispose() {
    // Idempotent: Riverpod bisa memanggil dispose sekali lagi saat container
    // dibuang (mis. hot restart atau penutupan aplikasi).
    if (_disposed) return;
    _disposed = true;
    _autoPauseTimer?.cancel();
    _sub?.cancel();
    _location.dispose();
    super.dispose();
  }
}

/// Format pace "5:32" untuk ditampilkan besar di UI.
String paceLabel(double secPerKm) {
  if (secPerKm <= 0 || !secPerKm.isFinite) return "--'--";
  return "${formatPace(secPerKm)}'";
}

/// Status izin lokasi untuk ditampilkan di UI.
Future<LocationPermission> currentPermission() =>
    Geolocator.checkPermission();
