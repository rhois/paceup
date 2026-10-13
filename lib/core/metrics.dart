import 'dart:math' as math;

import '../data/models/models.dart';

/// Satu pecahan (split) per kilometer atau per mil.
class Split {
  const Split({
    required this.index,
    required this.distanceMeters,
    required this.duration,
    required this.elevationGain,
    this.partial = false,
  });

  /// 1, 2, 3, ... (menandai kilometer/mil ke berapa).
  final int index;
  final double distanceMeters;
  final Duration duration;
  final double elevationGain;

  /// True untuk pecahan terakhir yang belum genap 1 km.
  final bool partial;

  /// Pace dalam detik per km.
  double get paceSecPerKm {
    if (distanceMeters <= 0) return 0;
    return duration.inMilliseconds / 1000.0 / (distanceMeters / 1000.0);
  }

  /// Pace dalam detik per mil.
  double get paceSecPerMile => paceSecPerKm * 1.609344;

  double get speedKmh {
    final h = duration.inMilliseconds / 3600000.0;
    if (h <= 0) return 0;
    return (distanceMeters / 1000.0) / h;
  }
}

/// Kumpulan metrik hasil perhitungan sebuah aktivitas.
class RunMetrics {
  const RunMetrics({
    required this.distanceMeters,
    required this.movingDuration,
    required this.elapsedDuration,
    required this.elevationGain,
    required this.elevationLoss,
    required this.splits,
    required this.bestSplit,
    required this.avgPaceSecPerKm,
    required this.avgMovingPaceSecPerKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.calories,
    required this.avgCadenceSpm,
    required this.avgHeartRate,
    required this.stoppedDuration,
    required this.pointCount,
  });

  final double distanceMeters;
  final Duration movingDuration;
  final Duration elapsedDuration;
  final double elevationGain;
  final double elevationLoss;
  final List<Split> splits;
  final Split? bestSplit;
  final double avgPaceSecPerKm;
  final double avgMovingPaceSecPerKm;
  final double avgSpeedKmh;
  final double maxSpeedKmh;
  final int calories;
  final int avgCadenceSpm;
  final int avgHeartRate;
  final Duration stoppedDuration;
  final int pointCount;

  bool get isEmpty => distanceMeters < 1 || pointCount < 2;
}

/// Mesin perhitungan metrik lari.
///
/// Semua fungsi di sini murni (pure) sehingga mudah diuji dan tidak
/// bergantung pada UI. Ini inti dari "deteksi lari, jarak, pace, dan
/// lainnya".
class MetricsEngine {
  const MetricsEngine._();

  /// Ambang elevasi untuk menghindari noise barometer (meter).
  static const double _elevationNoiseThreshold = 2.0;

  /// Hitung seluruh metrik dari daftar titik aktivitas.
  ///
  /// [weightKg] dipakai untuk estimasi kalori, [splitUnitMeters] = 1000 untuk
  /// km dan 1609.344 untuk mil.
  static RunMetrics compute(
    List<RunPoint> points, {
    double? weightKg,
    double splitUnitMeters = 1000,
    int? avgHeartRate,
  }) {
    if (points.length < 2) {
      return _empty(points.length);
    }

    final ordered = [...points]..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));

    var distance = 0.0;
    var movingMs = 0;
    var stoppedMs = 0;
    var elevationGain = 0.0;
    var elevationLoss = 0.0;
    var maxSpeed = 0.0;
    var speedSum = 0.0;
    var speedSamples = 0;
    final speedBySeg = <double>[];

    for (var i = 1; i < ordered.length; i++) {
      final prev = ordered[i - 1];
      final cur = ordered[i];
      if (cur.distanceDelta <= 0 && cur.speedMps <= 0) {
        continue;
      }
      distance += cur.distanceDelta;

      final dt = cur.recordedAt.difference(prev.recordedAt).inMilliseconds;
      if (dt <= 0) continue;

      final segSpeed = cur.speedMps > 0 ? cur.speedMps : cur.distanceDelta / (dt / 1000.0);
      speedBySeg.add(segSpeed);

      // Auto-pause: segmen < 0.7 m/s (~2.5 km/jam) dianggap berhenti.
      if (segSpeed < 0.7) {
        stoppedMs += dt;
      } else {
        movingMs += dt;
      }

      if (segSpeed > maxSpeed) maxSpeed = segSpeed;
      if (segSpeed > 0.5) {
        speedSum += segSpeed;
        speedSamples++;
      }

      final dAlt = cur.altitude - prev.altitude;
      if (dAlt > 0 && cur.altitude != 0 && prev.altitude != 0) {
        if (dAlt >= _elevationNoiseThreshold) elevationGain += dAlt;
      } else if (dAlt < 0 && cur.altitude != 0 && prev.altitude != 0) {
        if (dAlt.abs() >= _elevationNoiseThreshold) elevationLoss += dAlt.abs();
      }
    }

    final elapsedMs = ordered.last.recordedAt
        .difference(ordered.first.recordedAt)
        .inMilliseconds;
    if (movingMs == 0) movingMs = elapsedMs;

    final splits = computeSplits(ordered, splitUnitMeters);
    final best = _bestSplit(splits);

    final avgPace = distance > 0 ? (elapsedMs / 1000.0) / (distance / 1000.0) : 0.0;
    final avgMovingPace =
        distance > 0 ? (movingMs / 1000.0) / (distance / 1000.0) : 0.0;
    final avgSpeed = speedSamples > 0 ? speedSum / speedSamples : 0.0;

    final cadenceSamples =
        ordered.where((p) => p.cadence > 0).map((p) => p.cadence).toList();
    final avgCadence = cadenceSamples.isEmpty
        ? 0
        : (cadenceSamples.reduce((a, b) => a + b) / cadenceSamples.length).round();

    final hrSamples =
        ordered.where((p) => p.heartRate > 0).map((p) => p.heartRate).toList();
    final avgHr = avgHeartRate ??
        (hrSamples.isEmpty
            ? 0
            : (hrSamples.reduce((a, b) => a + b) / hrSamples.length).round());

    return RunMetrics(
      distanceMeters: distance,
      movingDuration: Duration(milliseconds: movingMs),
      elapsedDuration: Duration(milliseconds: elapsedMs),
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      splits: splits,
      bestSplit: best,
      avgPaceSecPerKm: avgPace,
      avgMovingPaceSecPerKm: avgMovingPace,
      avgSpeedKmh: avgSpeed * 3.6,
      maxSpeedKmh: maxSpeed * 3.6,
      calories: estimateCalories(
        distanceMeters: distance,
        movingSeconds: movingMs / 1000.0,
        weightKg: weightKg ?? 65,
        avgSpeedMps: avgSpeed,
      ),
      avgCadenceSpm: avgCadence,
      avgHeartRate: avgHr,
      stoppedDuration: Duration(milliseconds: stoppedMs),
      pointCount: ordered.length,
    );
  }

  /// Pecah aktivitas menjadi split per [unitMeters].
  ///
  /// Bila satu segmen GPS melewati batas 1 km, titik potongnya diinterpolasi
  /// agar pace tiap split akurat.
  static List<Split> computeSplits(
    List<RunPoint> points,
    double unitMeters,
  ) {
    if (points.length < 2 || unitMeters <= 0) return const [];

    final splits = <Split>[];
    var accDist = 0.0;
    var accMs = 0;
    var accGain = 0.0;
    var index = 1;

    void flush(bool partial) {
      if (accDist <= 0) return;
      splits.add(Split(
        index: index++,
        distanceMeters: accDist,
        duration: Duration(milliseconds: accMs),
        elevationGain: accGain,
        partial: partial,
      ));
    }

    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final segDist = cur.distanceDelta;
      final segMs = cur.recordedAt.difference(prev.recordedAt).inMilliseconds;
      if (segDist <= 0 || segMs <= 0) {
        if (segDist <= 0) {
          // Tetap catat waktu berhenti pada split berjalan.
          accMs += segMs > 0 ? segMs : 0;
        }
        continue;
      }

      var remaining = segDist;
      var consumedMs = 0;

      while (accDist + remaining >= unitMeters) {
        final need = unitMeters - accDist;
        final ratio = need / segDist;
        final msForNeed = (segMs * ratio).round() - consumedMs;
        accDist += need;
        accMs += math.max(msForNeed, 0);
        accGain += elevDelta(prev.altitude, cur.altitude) * ratio;
        consumedMs += math.max(msForNeed, 0);
        flush(false);
        accDist = 0;
        accMs = 0;
        accGain = 0;
        remaining -= need;
      }

      if (remaining > 0) {
        accDist += remaining;
        accMs += math.max(segMs - consumedMs, 0);
        accGain += elevDelta(prev.altitude, cur.altitude) * (remaining / segDist);
      }
    }

    flush(true);
    return splits;
  }

  /// Beda elevasi yang layak dihitung (abaikan noise < 2 m).
  static double elevDelta(double a, double b) {
    if (a == 0 || b == 0) return 0;
    final d = b - a;
    return d >= _elevationNoiseThreshold ? d : 0;
  }

  static Split? _bestSplit(List<Split> splits) {
    Split? best;
    for (final s in splits) {
      if (s.partial) continue;
      if (best == null || s.paceSecPerKm < best.paceSecPerKm) best = s;
    }
    return best;
  }

  /// Estimasi kalori berbasis MET sederhana (berbasis pace & berat badan).
  ///
  /// MET: jalan santai ~3.5, lari 8 km/jam ~8.3, lari 12 km/jam ~11.8.
  static int estimateCalories({
    required double distanceMeters,
    required double movingSeconds,
    required double weightKg,
    required double avgSpeedMps,
  }) {
    if (movingSeconds <= 0) return 0;
    final kmh = avgSpeedMps * 3.6;
    final met = switch (kmh) {
      < 5.5 => 3.5,
      < 6.5 => 6.0,
      < 8.0 => 8.3,
      < 9.7 => 9.8,
      < 11.3 => 11.0,
      < 12.9 => 11.8,
      < 14.5 => 12.8,
      < 16.1 => 14.5,
      _ => 16.0,
    };
    // kcal = MET * 3.5 * kg / 200 * menit
    final kcal = met * 3.5 * weightKg / 200.0 * (movingSeconds / 60.0);
    return kcal.round();
  }

  /// Estimasi VO2max dari performa lari (formula Uth–Sørensen).
  static double vo2max({
    required double distanceMeters,
    required double movingSeconds,
  }) {
    if (distanceMeters <= 0 || movingSeconds <= 0) return 0;
    final minutes = movingSeconds / 60.0;
    final speedMpm = distanceMeters / minutes;
    return 15 * (speedMpm / 60.0) + 3.5;
  }

  static RunMetrics _empty(int pointCount) => RunMetrics(
        distanceMeters: 0,
        movingDuration: Duration.zero,
        elapsedDuration: Duration.zero,
        elevationGain: 0,
        elevationLoss: 0,
        splits: const [],
        bestSplit: null,
        avgPaceSecPerKm: 0,
        avgMovingPaceSecPerKm: 0,
        avgSpeedKmh: 0,
        maxSpeedKmh: 0,
        calories: 0,
        avgCadenceSpm: 0,
        avgHeartRate: 0,
        stoppedDuration: Duration.zero,
        pointCount: pointCount,
      );
}

/// Format pace "5:32 /km".
String formatPace(double secPerKm) {
  if (secPerKm <= 0 || !secPerKm.isFinite) return '--:--';
  final total = secPerKm.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Format durasi "1:24:07" atau "24:07".
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Format jarak "10,42 km".
String formatDistance(double meters, {int decimals = 2}) {
  final km = meters / 1000.0;
  return '${km.toStringAsFixed(decimals).replaceAll('.', ',')} km';
}
