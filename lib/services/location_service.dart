import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' hide ActivityType;
import 'package:geolocator/geolocator.dart' as geo show ActivityType;

import '../core/geo.dart';

/// Kesalahan terkait izin/sensor lokasi.
class LocationException implements Exception {
  const LocationException(this.message, {this.permanent = false});

  final String message;
  final bool permanent;

  @override
  String toString() => message;
}

/// Pembungkus Geolocator: izin, stream posisi, dan konversi ke [RawFix].
class LocationService {
  LocationService({
    this.interval = const Duration(seconds: 2),
    this.distanceFilterMeters = 2,
  });

  /// Interval update. 2 detik cukup untuk lari (tidak boros baterai).
  final Duration interval;

  /// Jarang update bila tidak bergerak lebih dari ini.
  final double distanceFilterMeters;

  StreamSubscription<RawFix>? _sub;
  final _controller = StreamController<RawFix>.broadcast();

  /// Stream fix GPS mentah.
  Stream<RawFix> get fixes => _controller.stream;

  bool get isTracking => _sub != null;

  /// Pastikan layanan lokasi aktif dan izin diberikan.
  Future<void> ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'GPS/nonaktif. Nyalakan layanan lokasi untuk mulai merekam.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException('Izin lokasi ditolak.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Izin lokasi ditolak permanen. Aktifkan lewat Pengaturan.',
        permanent: true,
      );
    }
  }

  /// Ambil satu posisi terkini (untuk menyiapkan UI sebelum mulai).
  Future<RawFix?> currentFix() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _toFix(pos);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      return last == null ? null : _toFix(last);
    }
  }

  /// Mulai mengalirkan posisi.
  Future<void> start() async {
    if (_sub != null) return;
    await ensurePermission();

    final settings = defaultTargetPlatform == TargetPlatform.iOS
        ? AppleSettings(
            accuracy: LocationAccuracy.best,
            activityType: geo.ActivityType.fitness,
            distanceFilter: distanceFilterMeters.round(),
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          )
        : AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: distanceFilterMeters.round(),
            intervalDuration: interval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'PaceUp sedang merekam',
              notificationText: 'Aktivitasmu sedang dilacak di latar belakang.',
              notificationChannelName: 'Perekaman aktivitas',
              enableWakeLock: true,
              setOngoing: true,
            ),
          );

    _sub = Geolocator.getPositionStream(locationSettings: settings)
        .map(_toFix)
        .listen(_controller.add, onError: (Object e) {
      _controller.addError(e);
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  RawFix _toFix(Position p) => RawFix(
        lat: p.latitude,
        lon: p.longitude,
        timestamp: p.timestamp,
        accuracy: p.accuracy,
        altitude: p.altitude,
        speed: p.speed < 0 ? 0 : p.speed,
        heading: p.heading < 0 ? 0 : p.heading,
      );
}
