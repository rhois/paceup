import 'dart:math' as math;

/// Utilitas geospasial: jarak, bearing, penyaringan & penghalusan sinyal GPS.
class Geo {
  const Geo._();

  static const double earthRadiusMeters = 6371008.8;

  /// Jarak Haversine (meter) antara dua koordinat.
  static double distance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  /// Arah gerak (0-360 derajat) dari titik 1 ke titik 2.
  static double bearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = _rad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_rad(lat2));
    final x = math.cos(_rad(lat1)) * math.sin(_rad(lat2)) -
        math.sin(_rad(lat1)) * math.cos(_rad(lat2)) * math.cos(dLon);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Interpolasi linier antara dua titik (untuk mencari titik potong 1 km).
  static (double, double) lerp(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    double t,
  ) {
    return (lat1 + (lat2 - lat1) * t, lon1 + (lon2 - lon1) * t);
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static double _deg(double rad) => rad * 180.0 / math.pi;
}

/// Titik GPS mentah dari perangkat, sebelum difilter.
class RawFix {
  const RawFix({
    required this.lat,
    required this.lon,
    required this.timestamp,
    this.accuracy = 0,
    this.altitude = 0,
    this.speed = 0,
    this.heading = 0,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;

  /// Akurasi horizontal dalam meter (semakin kecil semakin baik).
  final double accuracy;

  /// Ketinggian dalam meter (dari barometer/GPS).
  final double altitude;

  /// Kecepatan dari OS dalam m/s (bisa 0 bila tidak tersedia).
  final double speed;
  final double heading;
}

/// Parameter penyaringan sinyal GPS.
class GpsFilterConfig {
  const GpsFilterConfig({
    this.maxAccuracyMeters = 35,
    this.minDistanceMeters = 3,
    this.maxSpeedMps = 12.5, // ~45 km/jam: di atas ini dianggap bukan lari
    this.maxJumpMeters = 150,
    this.smoothingWindow = 5,
  });

  /// Buang fix dengan akurasi lebih buruk dari ini.
  final double maxAccuracyMeters;

  /// Abaikan pergerakan mikro di bawah ambang ini (GPS drift saat diam).
  final double minDistanceMeters;

  /// Batas kecepatan wajar untuk aktivitas lari/jalan kaki.
  final double maxSpeedMps;

  /// Lompatan koordinat tak wajar antar fix.
  final double maxJumpMeters;

  /// Jumlah titik untuk rata-rata bergerak.
  final int smoothingWindow;

  GpsFilterConfig copyWith({
    double? maxAccuracyMeters,
    double? minDistanceMeters,
    double? maxSpeedMps,
    double? maxJumpMeters,
    int? smoothingWindow,
  }) {
    return GpsFilterConfig(
      maxAccuracyMeters: maxAccuracyMeters ?? this.maxAccuracyMeters,
      minDistanceMeters: minDistanceMeters ?? this.minDistanceMeters,
      maxSpeedMps: maxSpeedMps ?? this.maxSpeedMps,
      maxJumpMeters: maxJumpMeters ?? this.maxJumpMeters,
      smoothingWindow: smoothingWindow ?? this.smoothingWindow,
    );
  }
}

/// Hasil pemrosesan satu fix GPS.
class FilteredFix {
  const FilteredFix({
    required this.lat,
    required this.lon,
    required this.timestamp,
    required this.altitude,
    required this.distanceDelta,
    required this.speedMps,
    required this.cumulativeDistance,
    required this.accepted,
    this.rejectReason,
    this.moving = true,
  });

  final double lat;
  final double lon;
  final DateTime timestamp;
  final double altitude;

  /// Jarak tambahan (meter) yang disumbangkan fix ini.
  final double distanceDelta;

  /// Kecepatan sesaat (m/s) hasil penghalusan.
  final double speedMps;

  /// Akumulasi jarak (meter) sampai fix ini.
  final double cumulativeDistance;

  /// False bila fix ditolak sebagai noise.
  final bool accepted;

  final String? rejectReason;
  final bool moving;
}

/// Menyaring dan menghaluskan aliran titik GPS.
///
/// Strategi:
/// 1. Tolak fix dengan akurasi buruk.
/// 2. Tolak lompatan koordinat atau kecepatan yang tidak wajar (kendaraan).
/// 3. Abaikan pergerakan di bawah ambang (drift saat berhenti).
/// 4. Haluskan kecepatan dengan rata-rata bergerak (EMA + window).
///
/// Ini pendekatan yang dipakai aplikasi pelacak lari pada umumnya: efisien,
/// tanpa dependensi native tambahan, dan cukup stabil untuk perhitungan
/// jarak/pace.
class GpsFilter {
  GpsFilter({this.config = const GpsFilterConfig()});

  final GpsFilterConfig config;

  FilteredFix? _last;
  double _cumulative = 0;
  final List<double> _speedWindow = [];
  double _emaSpeed = 0;

  /// Titik terakhir yang diterima (null bila belum ada).
  FilteredFix? get last => _last;

  double get cumulativeDistance => _cumulative;

  void reset() {
    _last = null;
    _cumulative = 0;
    _speedWindow.clear();
    _emaSpeed = 0;
  }

  /// Proses satu fix. Mengembalikan fix dengan status [FilteredFix.accepted].
  FilteredFix process(RawFix raw) {
    final prev = _last;

    if (raw.accuracy > 0 && raw.accuracy > config.maxAccuracyMeters) {
      return _reject(raw, 'akurasi rendah (${raw.accuracy.toStringAsFixed(0)} m)');
    }

    if (prev == null) {
      _last = FilteredFix(
        lat: raw.lat,
        lon: raw.lon,
        timestamp: raw.timestamp,
        altitude: raw.altitude,
        distanceDelta: 0,
        speedMps: raw.speed,
        cumulativeDistance: 0,
        accepted: true,
      );
      return _last!;
    }

    final dt =
        raw.timestamp.difference(prev.timestamp).inMilliseconds / 1000.0;
    if (dt <= 0) {
      return _reject(raw, 'timestamp tidak valid');
    }

    final dist = Geo.distance(prev.lat, prev.lon, raw.lat, raw.lon);
    final impliedSpeed = dist / dt;

    // Lompatan koordinat / kecepatan tidak wajar -> kemungkinan sinyal
    // "teleport" atau pengguna sedang berkendara.
    if (dist > config.maxJumpMeters && impliedSpeed > config.maxSpeedMps) {
      return _reject(raw, 'lompatan sinyal ${dist.toStringAsFixed(0)} m');
    }
    if (impliedSpeed > config.maxSpeedMps) {
      return _reject(raw, 'kecepatan tidak wajar '
          '${(impliedSpeed * 3.6).toStringAsFixed(1)} km/jam');
    }

    // Drift saat diam: cukup perbarui titik acuan, tapi jangan tambah jarak.
    if (dist < config.minDistanceMeters) {
      final still = FilteredFix(
        lat: raw.lat,
        lon: raw.lon,
        timestamp: raw.timestamp,
        altitude: raw.altitude,
        distanceDelta: 0,
        speedMps: 0,
        cumulativeDistance: _cumulative,
        accepted: true,
        moving: false,
      );
      _last = still;
      _pushSpeed(0);
      return still;
    }

    _cumulative += dist;
    _pushSpeed(impliedSpeed);

    // Kecepatan titik ini = campuran kecepatan OS (bila ada) & hasil hitung.
    final measured = raw.speed > 0 ? (raw.speed + impliedSpeed) / 2 : impliedSpeed;
    final smoothed = _emaSpeed == 0 ? measured : (_emaSpeed * 0.7 + measured * 0.3);
    _emaSpeed = smoothed;

    final fix = FilteredFix(
      lat: raw.lat,
      lon: raw.lon,
      timestamp: raw.timestamp,
      altitude: raw.altitude,
      distanceDelta: dist,
      speedMps: smoothed,
      cumulativeDistance: _cumulative,
      accepted: true,
    );
    _last = fix;
    return fix;
  }

  FilteredFix _reject(RawFix raw, String reason) {
    final prev = _last;
    return FilteredFix(
      lat: raw.lat,
      lon: raw.lon,
      timestamp: raw.timestamp,
      altitude: raw.altitude,
      distanceDelta: 0,
      speedMps: prev?.speedMps ?? 0,
      cumulativeDistance: _cumulative,
      accepted: false,
      rejectReason: reason,
    );
  }

  void _pushSpeed(double v) {
    _speedWindow.add(v);
    if (_speedWindow.length > config.smoothingWindow) {
      _speedWindow.removeAt(0);
    }
  }

  /// Kecepatan rata-rata dari jendela terakhir.
  double get windowedSpeed {
    if (_speedWindow.isEmpty) return 0;
    final sum = _speedWindow.reduce((a, b) => a + b);
    return sum / _speedWindow.length;
  }
}
