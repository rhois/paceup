/// Model data inti aplikasi. Semuanya punya `toJson`/`fromJson` agar
/// kompatibel dengan Postgres/Supabase (mode remote) maupun SharedPreferences
/// (mode lokal/offline).
library;

import 'dart:convert';

enum ActivityType {
  run,
  trailRun,
  walk,
  hike,
  ride;

  String get label => switch (this) {
        ActivityType.run => 'Lari',
        ActivityType.trailRun => 'Trail Run',
        ActivityType.walk => 'Jalan',
        ActivityType.hike => 'Hiking',
        ActivityType.ride => 'Bersepeda',
      };

  String get emoji => switch (this) {
        ActivityType.run => '🏃',
        ActivityType.trailRun => '🏔️',
        ActivityType.walk => '🚶',
        ActivityType.hike => '🥾',
        ActivityType.ride => '🚴',
      };

  bool get isRunning =>
      this == ActivityType.run || this == ActivityType.trailRun;

  static ActivityType fromName(String? name) {
    return ActivityType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ActivityType.run,
    );
  }
}

/// Deteksi otomatis jenis aktivitas dari kecepatan rata-rata (km/jam).
///
/// Dipakai untuk "deteksi lari": saat pengguna menekan Start, aplikasi
/// menebak jenis aktivitas dari gerakan awal, lalu pengguna tetap bisa
/// mengubahnya.
ActivityType detectActivityType(double speedKmh, {bool hilly = false}) {
  if (speedKmh <= 0) return ActivityType.run;
  if (speedKmh < 6.5) return ActivityType.walk;
  if (speedKmh < 13.5) return hilly ? ActivityType.trailRun : ActivityType.run;
  return ActivityType.ride;
}

class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.displayName = '',
    this.avatarUrl,
    this.bio = '',
    this.city = '',
    this.weightKg = 65,
    this.heightCm = 170,
    this.isPrivate = false,
    this.createdAt,
    this.followerCount = 0,
    this.followingCount = 0,
    this.activityCount = 0,
    this.totalDistanceMeters = 0,
    this.totalElevationMeters = 0,
  });

  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String bio;
  final String city;
  final double weightKg;
  final double heightCm;
  final bool isPrivate;
  final DateTime? createdAt;
  final int followerCount;
  final int followingCount;
  final int activityCount;
  final double totalDistanceMeters;
  final double totalElevationMeters;

  String get name => displayName.isEmpty ? username : displayName;

  String get initials {
    final source = name.trim();
    if (source.isEmpty) return '?';
    final parts = source.split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.length <= 2 ? parts.first : parts.first.substring(0, 2);
    }
    return '${parts.first[0]}${parts[1][0]}';
  }

  String get locationLabel => city.isEmpty ? 'Lokasi belum diatur' : city;

  Profile copyWith({
    String? username,
    String? displayName,
    String? avatarUrl,
    String? bio,
    String? city,
    double? weightKg,
    double? heightCm,
    bool? isPrivate,
    int? followerCount,
    int? followingCount,
    int? activityCount,
    double? totalDistanceMeters,
    double? totalElevationMeters,
  }) {
    return Profile(
      id: id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      city: city ?? this.city,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      activityCount: activityCount ?? this.activityCount,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      totalElevationMeters: totalElevationMeters ?? this.totalElevationMeters,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
        'avatar_url': avatarUrl,
        'bio': bio,
        'city': city,
        'weight_kg': weightKg,
        'height_cm': heightCm,
        'is_private': isPrivate,
        'created_at': createdAt?.toIso8601String(),
        'follower_count': followerCount,
        'following_count': followingCount,
        'activity_count': activityCount,
        'total_distance_meters': totalDistanceMeters,
        'total_elevation_meters': totalElevationMeters,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        username: (json['username'] ?? 'runner') as String,
        displayName: (json['display_name'] ?? '') as String,
        avatarUrl: json['avatar_url'] as String?,
        bio: (json['bio'] ?? '') as String,
        city: (json['city'] ?? '') as String,
        weightKg: _d(json['weight_kg'], 65),
        heightCm: _d(json['height_cm'], 170),
        isPrivate: (json['is_private'] ?? false) as bool,
        createdAt: _dt(json['created_at']),
        followerCount: _i(json['follower_count']),
        followingCount: _i(json['following_count']),
        activityCount: _i(json['activity_count']),
        totalDistanceMeters: _d(json['total_distance_meters'], 0),
        totalElevationMeters: _d(json['total_elevation_meters'], 0),
      );
}

/// Satu titik rekaman GPS.
class RunPoint {
  const RunPoint({
    required this.lat,
    required this.lon,
    required this.recordedAt,
    this.altitude = 0,
    this.speedMps = 0,
    this.distanceDelta = 0,
    this.accuracy = 0,
    this.cadence = 0,
    this.heartRate = 0,
    this.paused = false,
  });

  final double lat;
  final double lon;
  final DateTime recordedAt;
  final double altitude;
  final double speedMps;
  final double distanceDelta;
  final double accuracy;
  final int cadence;
  final int heartRate;
  final bool paused;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'recorded_at': recordedAt.toIso8601String(),
        'altitude': altitude,
        'speed_mps': speedMps,
        'distance_delta': distanceDelta,
        'accuracy': accuracy,
        'cadence': cadence,
        'heart_rate': heartRate,
        'paused': paused,
      };

  factory RunPoint.fromJson(Map<String, dynamic> json) => RunPoint(
        lat: _d(json['lat'], 0),
        lon: _d(json['lon'], 0),
        recordedAt: _dt(json['recorded_at']) ?? DateTime.now(),
        altitude: _d(json['altitude'], 0),
        speedMps: _d(json['speed_mps'], 0),
        distanceDelta: _d(json['distance_delta'], 0),
        accuracy: _d(json['accuracy'], 0),
        cadence: _i(json['cadence']),
        heartRate: _i(json['heart_rate']),
        paused: (json['paused'] ?? false) as bool,
      );
}

/// Sebuah aktivitas (hasil rekaman atau impor).
class Activity {
  const Activity({
    required this.id,
    required this.userId,
    required this.type,
    required this.startedAt,
    this.title = '',
    this.description = '',
    this.distanceMeters = 0,
    this.movingSeconds = 0,
    this.elapsedSeconds = 0,
    this.elevationGain = 0,
    this.elevationLoss = 0,
    this.avgPaceSecPerKm = 0,
    this.maxSpeedKmh = 0,
    this.avgHeartRate = 0,
    this.avgCadenceSpm = 0,
    this.calories = 0,
    this.kudosCount = 0,
    this.commentCount = 0,
    this.visibility = 'followers',
    this.mapPolyline = '',
    this.points = const [],
    this.createdAt,
    this.synced = true,
    this.achievements = const [],
  });

  final String id;
  final String userId;
  final ActivityType type;
  final DateTime startedAt;
  final String title;
  final String description;
  final double distanceMeters;
  final int movingSeconds;
  final int elapsedSeconds;
  final double elevationGain;
  final double elevationLoss;
  final double avgPaceSecPerKm;
  final double maxSpeedKmh;
  final int avgHeartRate;
  final int avgCadenceSpm;
  final int calories;
  final int kudosCount;
  final int commentCount;

  /// 'everyone' | 'followers' | 'only_me'
  final String visibility;

  /// Encoded polyline (format Google, presisi 5) untuk render cepat.
  final String mapPolyline;

  /// Titik GPS detail.
  final List<RunPoint> points;

  final DateTime? createdAt;
  final bool synced;

  /// Lencana/PR yang didapat pada aktivitas ini.
  final List<String> achievements;

  Duration get movingDuration => Duration(seconds: movingSeconds);
  Duration get elapsedDuration => Duration(seconds: elapsedSeconds);

  double get distanceKm => distanceMeters / 1000.0;
  double get avgSpeedKmh =>
      movingSeconds > 0 ? (distanceMeters / 1000.0) / (movingSeconds / 3600.0) : 0;

  /// Pace rata-rata (detik/km) dihitung ulang bila belum tersedia.
  double get paceSecPerKm {
    if (avgPaceSecPerKm > 0) return avgPaceSecPerKm;
    if (distanceMeters <= 0) return 0;
    return movingSeconds / (distanceMeters / 1000.0);
  }

  String get displayTitle =>
      title.isNotEmpty ? title : '${type.label} ${startedAt.hour.toString().padLeft(2, '0')}:${startedAt.minute.toString().padLeft(2, '0')}';

  Activity copyWith({
    String? title,
    String? description,
    int? kudosCount,
    int? commentCount,
    String? visibility,
    List<String>? achievements,
    bool? synced,
  }) {
    return Activity(
      id: id,
      userId: userId,
      type: type,
      startedAt: startedAt,
      title: title ?? this.title,
      description: description ?? this.description,
      distanceMeters: distanceMeters,
      movingSeconds: movingSeconds,
      elapsedSeconds: elapsedSeconds,
      elevationGain: elevationGain,
      elevationLoss: elevationLoss,
      avgPaceSecPerKm: avgPaceSecPerKm,
      maxSpeedKmh: maxSpeedKmh,
      avgHeartRate: avgHeartRate,
      avgCadenceSpm: avgCadenceSpm,
      calories: calories,
      kudosCount: kudosCount ?? this.kudosCount,
      commentCount: commentCount ?? this.commentCount,
      visibility: visibility ?? this.visibility,
      mapPolyline: mapPolyline,
      points: points,
      createdAt: createdAt,
      synced: synced ?? this.synced,
      achievements: achievements ?? this.achievements,
    );
  }

  /// Ringkasan tanpa titik GPS (untuk feed & leaderboard).
  Map<String, dynamic> toJson({bool includePoints = false}) => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'title': title,
        'description': description,
        'started_at': startedAt.toIso8601String(),
        'distance_meters': distanceMeters,
        'moving_seconds': movingSeconds,
        'elapsed_seconds': elapsedSeconds,
        'elevation_gain': elevationGain,
        'elevation_loss': elevationLoss,
        'avg_pace_sec_per_km': avgPaceSecPerKm,
        'max_speed_kmh': maxSpeedKmh,
        'avg_heart_rate': avgHeartRate,
        'avg_cadence_spm': avgCadenceSpm,
        'calories': calories,
        'kudos_count': kudosCount,
        'comment_count': commentCount,
        'visibility': visibility,
        'map_polyline': mapPolyline,
        'created_at': createdAt?.toIso8601String(),
        'synced': synced,
        'achievements': achievements,
        if (includePoints) 'points': points.map((p) => p.toJson()).toList(),
      };

  factory Activity.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    return Activity(
      id: json['id'] as String,
      userId: (json['user_id'] ?? '') as String,
      type: ActivityType.fromName(json['type'] as String?),
      startedAt: _dt(json['started_at']) ?? DateTime.now(),
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      distanceMeters: _d(json['distance_meters'], 0),
      movingSeconds: _i(json['moving_seconds']),
      elapsedSeconds: _i(json['elapsed_seconds']),
      elevationGain: _d(json['elevation_gain'], 0),
      elevationLoss: _d(json['elevation_loss'], 0),
      avgPaceSecPerKm: _d(json['avg_pace_sec_per_km'], 0),
      maxSpeedKmh: _d(json['max_speed_kmh'], 0),
      avgHeartRate: _i(json['avg_heart_rate']),
      avgCadenceSpm: _i(json['avg_cadence_spm']),
      calories: _i(json['calories']),
      kudosCount: _i(json['kudos_count']),
      commentCount: _i(json['comment_count']),
      visibility: (json['visibility'] ?? 'followers') as String,
      mapPolyline: (json['map_polyline'] ?? '') as String,
      points: rawPoints is List
          ? rawPoints
              .map((e) => RunPoint.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList()
          : const [],
      createdAt: _dt(json['created_at']),
      synced: (json['synced'] ?? true) as bool,
      achievements: (json['achievements'] as List?)?.cast<String>() ?? const [],
    );
  }
}

/// Entri satu split (untuk halaman detail aktivitas).
class ActivitySplit {
  const ActivitySplit({
    required this.index,
    required this.distanceMeters,
    required this.seconds,
    this.elevationGain = 0,
    this.partial = false,
  });

  final int index;
  final double distanceMeters;
  final int seconds;
  final double elevationGain;
  final bool partial;

  double get paceSecPerKm =>
      distanceMeters <= 0 ? 0 : seconds / (distanceMeters / 1000.0);

  Map<String, dynamic> toJson() => {
        'index': index,
        'distance_meters': distanceMeters,
        'seconds': seconds,
        'elevation_gain': elevationGain,
        'partial': partial,
      };

  factory ActivitySplit.fromJson(Map<String, dynamic> json) => ActivitySplit(
        index: _i(json['index']),
        distanceMeters: _d(json['distance_meters'], 0),
        seconds: _i(json['seconds']),
        elevationGain: _d(json['elevation_gain'], 0),
        partial: (json['partial'] ?? false) as bool,
      );
}

/// Komentar pada aktivitas.
class ActivityComment {
  const ActivityComment({
    required this.id,
    required this.activityId,
    required this.userId,
    required this.body,
    required this.createdAt,
    this.author,
  });

  final String id;
  final String activityId;
  final String userId;
  final String body;
  final DateTime createdAt;
  final Profile? author;

  Map<String, dynamic> toJson() => {
        'id': id,
        'activity_id': activityId,
        'user_id': userId,
        'body': body,
        'created_at': createdAt.toIso8601String(),
      };

  factory ActivityComment.fromJson(Map<String, dynamic> json) {
    final authorJson = json['profiles'] ?? json['author'];
    return ActivityComment(
      id: json['id'] as String,
      activityId: (json['activity_id'] ?? '') as String,
      userId: (json['user_id'] ?? '') as String,
      body: (json['body'] ?? '') as String,
      createdAt: _dt(json['created_at']) ?? DateTime.now(),
      author: authorJson is Map
          ? Profile.fromJson(Map<String, dynamic>.from(authorJson))
          : null,
    );
  }
}

/// Item feed = aktivitas + penulis + status kudos.
class FeedItem {
  const FeedItem({
    required this.activity,
    required this.owner,
    this.hasKudosed = false,
    this.isFollowing = false,
  });

  final Activity activity;
  final Profile owner;
  final bool hasKudosed;
  final bool isFollowing;

  FeedItem copyWith({
    Activity? activity,
    Profile? owner,
    bool? hasKudosed,
    bool? isFollowing,
  }) {
    return FeedItem(
      activity: activity ?? this.activity,
      owner: owner ?? this.owner,
      hasKudosed: hasKudosed ?? this.hasKudosed,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }
}

/// Baris leaderboard.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.profile,
    required this.totalDistanceMeters,
    required this.activityCount,
    required this.totalElevationMeters,
    this.bestPaceSecPerKm = 0,
    this.rank = 0,
  });

  final Profile profile;
  final double totalDistanceMeters;
  final int activityCount;
  final double totalElevationMeters;
  final double bestPaceSecPerKm;
  final int rank;
}

/// Rekor pribadi (PR) pengguna.
class PersonalRecord {
  const PersonalRecord({
    required this.label,
    required this.value,
    required this.unit,
    this.activityId,
    this.achievedAt,
    this.isNew = false,
  });

  final String label;
  final String value;
  final String unit;
  final String? activityId;
  final DateTime? achievedAt;
  final bool isNew;
}

/// Ringkasan mingguan untuk dasbor.
class WeeklySummary {
  const WeeklySummary({
    required this.weekStart,
    required this.distanceMeters,
    required this.movingSeconds,
    required this.elevationGain,
    required this.activityCount,
    required this.calories,
    this.dailyDistances = const [],
  });

  final DateTime weekStart;
  final double distanceMeters;
  final int movingSeconds;
  final double elevationGain;
  final int activityCount;
  final int calories;

  /// Jarak (meter) per hari Senin..Minggu.
  final List<double> dailyDistances;

  double get avgPaceSecPerKm => distanceMeters <= 0
      ? 0
      : movingSeconds / (distanceMeters / 1000.0);

  List<double> get normalizedDaily {
    final maxV = dailyDistances.isEmpty
        ? 0.0
        : dailyDistances.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return List.filled(7, 0);
    return dailyDistances.map((d) => d / maxV).toList();
  }
}

// ---------------------------------------------------------------------------
// Helper konversi tipe dari JSON/Postgres.
// ---------------------------------------------------------------------------

double _d(Object? v, double fallback) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

int _i(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

DateTime? _dt(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v.toLocal();
  return DateTime.tryParse(v.toString())?.toLocal();
}

/// Encoder/decoder polyline kompatibel dengan PostGIS-friendly format
/// (Google encoded polyline, presisi 5).
class PolylineCodec {
  const PolylineCodec._();

  static String encode(List<RunPoint> points) {
    if (points.isEmpty) return '';
    final buf = StringBuffer();
    var prevLat = 0;
    var prevLon = 0;
    for (final p in points) {
      final lat = (p.lat * 1e5).round();
      final lon = (p.lon * 1e5).round();
      buf.write(_enc(lat - prevLat));
      buf.write(_enc(lon - prevLon));
      prevLat = lat;
      prevLon = lon;
    }
    return buf.toString();
  }

  static String _enc(int v) {
    var value = v < 0 ? ~(v << 1) : (v << 1);
    final out = StringBuffer();
    while (value >= 0x20) {
      out.writeCharCode((0x20 | (value & 0x1f)) + 63);
      value >>= 5;
    }
    out.writeCharCode(value + 63);
    return out.toString();
  }

  static List<(double, double)> decode(String encoded) {
    if (encoded.isEmpty) return const [];
    final coords = <(double, double)>[];
    var index = 0;
    var lat = 0;
    var lon = 0;
    while (index < encoded.length) {
      lat += _dec(encoded, index, (v) => index = v);
      lon += _dec(encoded, index, (v) => index = v);
      coords.add((lat / 1e5, lon / 1e5));
    }
    return coords;
  }

  static int _dec(String s, int start, void Function(int) set) {
    var result = 0;
    var shift = 0;
    int b;
    var i = start;
    do {
      b = s.codeUnitAt(i++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    set(i);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  static String encodeToJson(List<RunPoint> points) => jsonEncode(
        points.map((p) => [p.lat, p.lon]).toList(),
      );
}
