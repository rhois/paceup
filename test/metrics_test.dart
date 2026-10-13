import 'package:flutter_test/flutter_test.dart';
import 'package:paceup/core/geo.dart';
import 'package:paceup/core/metrics.dart';
import 'package:paceup/data/models/models.dart';

/// Titik bantu: membuat [RunPoint] pada jarak & waktu tertentu.
RunPoint p({
  required double lat,
  required double lon,
  required int second,
  double speed = 3.0,
  double altitude = 0,
  required double delta,
}) =>
    RunPoint(
      lat: lat,
      lon: lon,
      recordedAt: DateTime(2026, 1, 1).add(Duration(seconds: second)),
      speedMps: speed,
      altitude: altitude,
      distanceDelta: delta,
    );

void main() {
  group('Geo', () {
    test('jarak Haversine akurat pada jarak pendek', () {
      // ~111.19 m per 0.001 derajat lintang.
      final d = Geo.distance(-6.200000, 106.800000, -6.201000, 106.800000);
      expect(d, closeTo(111.2, 1.0));
    });

    test('jarak nol untuk titik yang sama', () {
      expect(Geo.distance(1, 2, 1, 2), 0);
    });

    test('bearing menghadap utara = 0 derajat', () {
      expect(Geo.bearing(-6.20, 106.80, -6.19, 106.80), closeTo(0, 0.5));
    });
  });

  group('GpsFilter', () {
    test('fix pertama selalu diterima dan tidak menambah jarak', () {
      final f = GpsFilter();
      final fix = f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      expect(fix.accepted, isTrue);
      expect(fix.distanceDelta, 0);
      expect(f.cumulativeDistance, 0);
    });

    test('menolak fix dengan akurasi buruk', () {
      final f = GpsFilter();
      f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      final bad = f.process(RawFix(
        lat: -6.201,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
        accuracy: 80,
      ));
      expect(bad.accepted, isFalse);
      expect(bad.rejectReason, contains('akurasi'));
    });

    test('menolak lompatan sinyal (teleport)', () {
      final f = GpsFilter();
      f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      // 0.01 derajat ~ 1.1 km dalam 4 detik -> tidak wajar.
      final jump = f.process(RawFix(
        lat: -6.21,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
        accuracy: 5,
      ));
      expect(jump.accepted, isFalse);
    });

    test('drift kecil saat diam tidak menambah jarak', () {
      final f = GpsFilter();
      f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      final still = f.process(RawFix(
        lat: -6.200005,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
        accuracy: 5,
      ));
      expect(still.accepted, isTrue);
      expect(still.moving, isFalse);
      expect(f.cumulativeDistance, 0);
    });

    test('bergerak maju menambah akumulasi jarak', () {
      final f = GpsFilter();
      f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      // ~11 m ke utara dalam 4 detik (~2.8 m/s) -> wajar.
      f.process(RawFix(
        lat: -6.2001,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1, 0, 0, 4),
        accuracy: 5,
      ));
      expect(f.cumulativeDistance, closeTo(11.1, 1.0));
    });

    test('reset mengosongkan akumulasi', () {
      final f = GpsFilter();
      f.process(RawFix(
        lat: -6.2,
        lon: 106.8,
        timestamp: DateTime(2026, 1, 1),
        accuracy: 5,
      ));
      f.reset();
      expect(f.cumulativeDistance, 0);
      expect(f.last, isNull);
    });
  });

  group('MetricsEngine', () {
    test('menghitung jarak, waktu, dan pace dengan benar', () {
      // 10 titik x 100 m = 1000 m dalam 300 detik => pace 5:00/km.
      final points = <RunPoint>[
        for (var i = 0; i <= 10; i++)
          p(
            lat: -6.2,
            lon: 106.8,
            second: i * 30,
            delta: i == 0 ? 0 : 100,
          ),
      ];
      final m = MetricsEngine.compute(points);
      expect(m.distanceMeters, closeTo(1000, 0.01));
      expect(m.avgMovingPaceSecPerKm, closeTo(300, 1));
      expect(m.splits.length, 1);
      expect(m.splits.first.paceSecPerKm, closeTo(300, 1));
    });

    test('memecah aktivitas menjadi split per kilometer', () {
      // 2500 m, 100 m per 30 detik.
      final points = <RunPoint>[
        for (var i = 0; i <= 25; i++)
          p(lat: -6.2, lon: 106.8, second: i * 30, delta: i == 0 ? 0 : 100),
      ];
      final m = MetricsEngine.compute(points);
      expect(m.distanceMeters, closeTo(2500, 0.01));
      expect(m.splits.length, 3);
      expect(m.splits[0].partial, isFalse);
      expect(m.splits[1].partial, isFalse);
      expect(m.splits[2].partial, isTrue);
      expect(m.splits[2].distanceMeters, closeTo(500, 0.01));
    });

    test('menemukan split terbaik, mengabaikan pecahan terakhir', () {
      final points = <RunPoint>[
        // 1 km pertama pelan (400 s), 1 km kedua cepat (250 s), sisa 200 m.
        for (var i = 0; i <= 10; i++)
          p(lat: -6.2, lon: 106.8, second: i * 40, delta: i == 0 ? 0 : 100),
        for (var i = 11; i <= 20; i++)
          p(lat: -6.2, lon: 106.8, second: 400 + (i - 10) * 25, delta: 100),
        for (var i = 21; i <= 22; i++)
          p(lat: -6.2, lon: 106.8, second: 650 + (i - 20) * 25, delta: 100),
      ];
      final m = MetricsEngine.compute(points);
      expect(m.bestSplit, isNotNull);
      expect(m.bestSplit!.index, 2);
      expect(m.bestSplit!.paceSecPerKm, closeTo(250, 3));
    });

    test('menghitung elevasi dengan ambang noise 2 m', () {
      final points = <RunPoint>[
        p(lat: -6.2, lon: 106.8, second: 0, delta: 0, altitude: 100),
        // +1 m -> noise, diabaikan.
        p(lat: -6.2, lon: 106.8, second: 30, delta: 100, altitude: 101),
        // +10 m -> dihitung.
        p(lat: -6.2, lon: 106.8, second: 60, delta: 100, altitude: 111),
        // -6 m -> dihitung sebagai turun.
        p(lat: -6.2, lon: 106.8, second: 90, delta: 100, altitude: 105),
      ];
      final m = MetricsEngine.compute(points);
      expect(m.elevationGain, closeTo(10, 0.01));
      expect(m.elevationLoss, closeTo(6, 0.01));
    });

    test('waktu bergerak memisahkan segmen berhenti', () {
      final points = <RunPoint>[
        p(lat: -6.2, lon: 106.8, second: 0, delta: 0, speed: 3),
        p(lat: -6.2, lon: 106.8, second: 30, delta: 100, speed: 3.3),
        // 60 detik berdiri di tempat.
        p(lat: -6.2, lon: 106.8, second: 90, delta: 0, speed: 0.2),
        p(lat: -6.2, lon: 106.8, second: 120, delta: 100, speed: 3.3),
      ];
      final m = MetricsEngine.compute(points);
      expect(m.movingDuration.inSeconds, closeTo(60, 1));
      expect(m.elapsedDuration.inSeconds, 120);
      expect(m.stoppedDuration.inSeconds, closeTo(60, 1));
    });

    test('estimasi kalori: laju per menit naik seiring intensitas', () {
      // Jarak sama (5 km). Yang lebih cepat menghabiskan waktu lebih singkat,
      // sehingga total kalorinya justru bisa lebih kecil — itu wajar secara
      // fisiologis. Yang penting: laju kalori PER MENIT harus lebih tinggi.
      final slow = MetricsEngine.estimateCalories(
        distanceMeters: 5000,
        movingSeconds: 2400, // 40 menit (~7,5 km/jam)
        weightKg: 70,
        avgSpeedMps: 2.0,
      );
      final fast = MetricsEngine.estimateCalories(
        distanceMeters: 5000,
        movingSeconds: 1200, // 20 menit (~15 km/jam)
        weightKg: 70,
        avgSpeedMps: 4.2,
      );

      final slowPerMinute = slow / 40;
      final fastPerMinute = fast / 20;
      expect(fastPerMinute, greaterThan(slowPerMinute));
      expect(slow, greaterThan(0));
      expect(fast, greaterThan(0));
    });

    test('estimasi kalori naik dengan berat badan', () {
      final light = MetricsEngine.estimateCalories(
        distanceMeters: 5000,
        movingSeconds: 1800,
        weightKg: 55,
        avgSpeedMps: 2.8,
      );
      final heavy = MetricsEngine.estimateCalories(
        distanceMeters: 5000,
        movingSeconds: 1800,
        weightKg: 90,
        avgSpeedMps: 2.8,
      );
      expect(heavy, greaterThan(light));
    });

    test('VO2max dari jarak & waktu', () {
      // 2400 m dalam 12 menit = 200 m/menit -> 15*3.33+3.5 = 53.5.
      final v = MetricsEngine.vo2max(
        distanceMeters: 2400,
        movingSeconds: 720,
      );
      expect(v, closeTo(53.5, 0.5));
    });

    test('aktivitas kosong menghasilkan metrik nol', () {
      final m = MetricsEngine.compute(const []);
      expect(m.isEmpty, isTrue);
      expect(m.distanceMeters, 0);
      expect(m.splits, isEmpty);
    });
  });

  group('Formatting', () {
    test('formatPace', () {
      expect(formatPace(300), '5:00');
      expect(formatPace(332), '5:32');
      expect(formatPace(0), '--:--');
    });

    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 24, seconds: 7)),
        '1:24:07',
      );
    });

    test('formatDistance', () {
      expect(formatDistance(10420), '10,42 km');
    });
  });

  group('PolylineCodec', () {
    test('encode lalu decode mengembalikan koordinat semula', () {
      final points = [
        p(lat: -6.2, lon: 106.8, second: 0, delta: 0),
        p(lat: -6.21, lon: 106.81, second: 10, delta: 1000),
      ];
      final encoded = PolylineCodec.encode(points);
      final decoded = PolylineCodec.decode(encoded);
      expect(decoded.length, 2);
      expect(decoded[0].$1, closeTo(-6.2, 1e-5));
      expect(decoded[0].$2, closeTo(106.8, 1e-5));
      expect(decoded[1].$1, closeTo(-6.21, 1e-5));
      expect(decoded[1].$2, closeTo(106.81, 1e-5));
    });
  });

  group('Activity model', () {
    test('deteksi jenis aktivitas dari kecepatan', () {
      expect(detectActivityType(4), ActivityType.walk);
      expect(detectActivityType(10), ActivityType.run);
      expect(detectActivityType(12, hilly: true), ActivityType.trailRun);
      expect(detectActivityType(25), ActivityType.ride);
    });

    test('pace dihitung ulang bila kosong', () {
      final a = Activity(
        id: 'x',
        userId: 'u',
        type: ActivityType.run,
        startedAt: DateTime(2026),
        distanceMeters: 10000,
        movingSeconds: 3000,
      );
      expect(a.paceSecPerKm, closeTo(300, 0.01));
      expect(a.avgSpeedKmh, closeTo(12, 0.01));
    });

    test('serialisasi JSON bolak-balik mempertahankan data', () {
      final original = Activity(
        id: 'a1',
        userId: 'u1',
        type: ActivityType.trailRun,
        startedAt: DateTime(2026, 3, 1, 6, 30),
        title: 'Trail pagi',
        distanceMeters: 12345.6,
        movingSeconds: 4200,
        elapsedSeconds: 4500,
        elevationGain: 320,
        avgPaceSecPerKm: 340,
        points: [
          p(lat: -6.2, lon: 106.8, second: 0, delta: 0),
          p(lat: -6.21, lon: 106.81, second: 10, delta: 1400),
        ],
      );
      final restored = Activity.fromJson(original.toJson(includePoints: true));
      expect(restored.id, original.id);
      expect(restored.type, ActivityType.trailRun);
      expect(restored.title, 'Trail pagi');
      expect(restored.distanceMeters, closeTo(12345.6, 0.001));
      expect(restored.points.length, 2);
      expect(restored.startedAt, original.startedAt);
    });
  });
}
