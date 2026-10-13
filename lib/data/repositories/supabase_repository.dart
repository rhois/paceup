import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/models.dart';
import 'paceup_repository.dart';

/// Implementasi repository di atas Supabase (Postgres + Auth + Storage).
///
/// Skema tabel yang dipakai ada di `sql/schema.sql`. Ringkasnya:
/// `profiles`, `activities`, `activity_points`, `kudos`, `comments`,
/// `follows`, dan view `activity_details`, `weekly_stats`.
///
/// Fitur yang memanfaatkan Postgres secara langsung:
/// * `follows` + view `activity_details` -> feed sosial.
/// * View `leaderboard_weekly` / `leaderboard_all_time` -> leaderboard.
/// * `activity_points` + PostGIS (opsional) -> peta rute.
class SupabaseRepository implements PaceUpRepository {
  SupabaseRepository(this._client);

  final sb.SupabaseClient _client;
  final _authController = StreamController<Profile?>.broadcast();

  Profile? _profile;
  StreamSubscription<sb.AuthState>? _authSub;

  static const _profileSelect =
      'id, username, display_name, avatar_url, bio, city, weight_kg, '
      'height_cm, is_private, created_at, follower_count, following_count, '
      'activity_count, total_distance_meters, total_elevation_meters';

  // ------------------------------------------------------------------ auth
  @override
  Future<void> bootstrap() async {
    final user = _client.auth.currentUser;
    if (user != null) {
      _profile = await _loadProfile(user.id);
    }
    _authSub ??= _client.auth.onAuthStateChange.listen((state) async {
      final u = state.session?.user;
      if (u == null) {
        _profile = null;
        _authController.add(null);
      } else {
        _profile = await _loadProfile(u.id);
        _authController.add(_profile);
      }
    });
  }

  @override
  Future<bool> get isSignedIn async => _client.auth.currentUser != null;

  @override
  Profile? get cachedProfile => _profile;

  @override
  Stream<Profile?> watchAuth() async* {
    yield _profile;
    yield* _authController.stream;
  }

  @override
  Future<Profile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw const AppFailure('Gagal masuk, coba lagi.');
      }
      final profile = await _loadProfile(user.id);
      _profile = profile;
      _authController.add(profile);
      return profile;
    } on sb.AuthException catch (e) {
      throw AppFailure(_friendlyAuthError(e), code: e.code);
    }
  }

  @override
  Future<Profile> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    // Cek username lebih dulu supaya tidak setengah jalan.
    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('username', username.trim())
        .maybeSingle();
    if (existing != null) {
      throw const AppFailure('Username sudah dipakai.', code: 'username-taken');
    }

    try {
      final res = await _client.auth.signUp(
        email: email.trim().toLowerCase(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw const AppFailure('Registrasi gagal. Coba lagi.');
      }
      final profile = Profile(
        id: user.id,
        username: username.trim(),
        displayName: (displayName ?? username).trim(),
        createdAt: DateTime.now(),
      );
      // Upsert: trigger di DB biasanya sudah membuat baris ini.
      await _client.from('profiles').upsert(profile.toJson());
      _profile = profile;
      _authController.add(profile);
      return profile;
    } on sb.AuthException catch (e) {
      throw AppFailure(_friendlyAuthError(e), code: e.code);
    }
  }

  @override
  Future<void> signOut() async {
    await _client.auth.signOut();
    _profile = null;
    _authController.add(null);
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    final updated = await _client
        .from('profiles')
        .update(profile.toJson())
        .eq('id', profile.id)
        .select(_profileSelect)
        .single();
    final result = Profile.fromJson(updated);
    _profile = result;
    _authController.add(result);
    return result;
  }

  @override
  Future<Profile?> profileByUsername(String username) async {
    final row = await _client
        .from('profiles')
        .select(_profileSelect)
        .eq('username', username)
        .maybeSingle();
    return row == null ? null : Profile.fromJson(row);
  }

  Future<Profile> _loadProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select(_profileSelect)
        .eq('id', userId)
        .maybeSingle();

    if (row == null) {
      // Trigger belum jalan (mis. akun lama) -> buat profil minimal.
      final fallback = Profile(
        id: userId,
        username: 'runner_${userId.substring(0, 6)}',
        displayName: _client.auth.currentUser?.email?.split('@').first ?? 'Pelari',
        createdAt: DateTime.now(),
      );
      await _client.from('profiles').upsert(fallback.toJson());
      return fallback;
    }
    return Profile.fromJson(row);
  }

  String _friendlyAuthError(sb.AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login')) return 'Email atau kata sandi salah.';
    if (msg.contains('already registered')) return 'Email sudah terdaftar.';
    if (msg.contains('password')) return 'Kata sandi minimal 6 karakter.';
    if (msg.contains('email')) return 'Format email tidak valid.';
    return 'Terjadi masalah pada autentikasi. Coba lagi.';
  }

  // ------------------------------------------------------------ activities
  @override
  Future<List<Activity>> activitiesOf(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client
        .from('activity_details')
        .select()
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<Activity?> activityById(String id) async {
    final row = await _client
        .from('activity_details')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final activity = Activity.fromJson(row);

    final pointRows = await _client
        .from('activity_points')
        .select('lat, lon, recorded_at, altitude, speed_mps, '
            'distance_delta, accuracy, cadence, heart_rate')
        .eq('activity_id', id)
        .order('seq', ascending: true);

    return Activity(
      id: activity.id,
      userId: activity.userId,
      type: activity.type,
      startedAt: activity.startedAt,
      title: activity.title,
      description: activity.description,
      distanceMeters: activity.distanceMeters,
      movingSeconds: activity.movingSeconds,
      elapsedSeconds: activity.elapsedSeconds,
      elevationGain: activity.elevationGain,
      elevationLoss: activity.elevationLoss,
      avgPaceSecPerKm: activity.avgPaceSecPerKm,
      maxSpeedKmh: activity.maxSpeedKmh,
      avgHeartRate: activity.avgHeartRate,
      avgCadenceSpm: activity.avgCadenceSpm,
      calories: activity.calories,
      kudosCount: activity.kudosCount,
      commentCount: activity.commentCount,
      visibility: activity.visibility,
      mapPolyline: activity.mapPolyline,
      points: (pointRows as List)
          .map((e) => RunPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      createdAt: activity.createdAt,
    );
  }

  @override
  Future<Activity> saveActivity(
    Activity activity, {
    List<RunPoint>? points,
  }) async {
    Future<void> insert() async {
      final payload = activity.toJson();
      payload['user_id'] = _client.auth.currentUser!.id;
      if (points != null && points.isNotEmpty) {
        payload['map_polyline'] = PolylineCodec.encode(points);
        // Bounding box rute dipakai oleh `nearby_activities()`.
        payload['start_lat'] = points.first.lat;
        payload['start_lon'] = points.first.lon;
        payload['end_lat'] = points.last.lat;
        payload['end_lon'] = points.last.lon;
      }
      await _client.from('activities').upsert(payload);

      if (points != null && points.isNotEmpty) {
        // Batch insert agar hemat round-trip.
        const chunk = 400;
        for (var start = 0; start < points.length; start += chunk) {
          final slice = points.skip(start).take(chunk).toList();
          await _client.from('activity_points').insert([
            for (var i = 0; i < slice.length; i++)
              {
                'activity_id': activity.id,
                'seq': start + i,
                ...slice[i].toJson(),
              },
          ]);
        }
      }
    }

    try {
      await insert();
    } on sb.PostgrestException catch (e) {
      // Offline / gangguan jaringan -> simpan sebagai aktivitas lokal.
      // Pemanggil dapat memakai `saveWithOfflineFallback` untuk antrean.
      throw AppFailure(
        'Gagal mengunggah aktivitas: ${e.message}',
        code: 'upload-failed',
      );
    }
    return activity;
  }

  @override
  Future<void> deleteActivity(String id) async {
    await _client.from('activities').delete().eq('id', id);
  }

  @override
  Future<void> updateActivityMeta(
    String id, {
    String? title,
    String? description,
    String? visibility,
  }) async {
    await _client.from('activities').update({
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (visibility != null) 'visibility': visibility,
    }).eq('id', id);
  }

  @override
  Future<int> flushPendingUploads() async {
    // Antrean offline dikelola di lapisan service (butuh LocalStore).
    return 0;
  }

  @override
  Future<int> pendingUploadCount() async => 0;

  // ---------------------------------------------------------------- social
  @override
  Future<List<FeedItem>> feed({int limit = 30, int offset = 0}) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return [];

    final rows = await _client
        .from('activity_details')
        .select('*, profiles!activities_user_id_fkey($_profileSelect), '
            'kudos(user_id)')
        .order('started_at', ascending: false)
        .range(offset, offset + limit - 1);

    return (rows as List).map((raw) {
      final row = Map<String, dynamic>.from(raw as Map);
      final activity = Activity.fromJson(row);
      final profileRaw = row['profiles'];
      final owner = profileRaw is Map
          ? Profile.fromJson(Map<String, dynamic>.from(profileRaw))
          : Profile(id: activity.userId, username: 'runner');
      final kudosList = (row['kudos'] as List?) ?? const [];
      final kudosers = kudosList
          .map((k) => (k as Map)['user_id'] as String)
          .toList();
      return FeedItem(
        activity: activity.copyWith(kudosCount: kudosers.length),
        owner: owner,
        hasKudosed: kudosers.contains(me),
      );
    }).toList();
  }

  @override
  Future<bool> hasKudosed(String activityId, String userId) async {
    final row = await _client
        .from('kudos')
        .select('activity_id')
        .eq('activity_id', activityId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<int> toggleKudos(String activityId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AppFailure('Belum masuk.');

    final existing = await hasKudosed(activityId, me);
    if (existing) {
      await _client
          .from('kudos')
          .delete()
          .eq('activity_id', activityId)
          .eq('user_id', me);
    } else {
      await _client.from('kudos').insert({
        'activity_id': activityId,
        'user_id': me,
      });
    }

    final count = await _client
        .from('kudos')
        .count(sb.CountOption.exact)
        .eq('activity_id', activityId);
    return count;
  }

  @override
  Future<List<ActivityComment>> comments(String activityId) async {
    final rows = await _client
        .from('comments')
        .select('*, profiles($_profileSelect)')
        .eq('activity_id', activityId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((e) => ActivityComment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<ActivityComment> addComment(String activityId, String body) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) throw const AppFailure('Belum masuk.');
    final row = await _client
        .from('comments')
        .insert({
          'activity_id': activityId,
          'user_id': me,
          'body': body.trim(),
        })
        .select('*, profiles($_profileSelect)')
        .single();
    return ActivityComment.fromJson(row);
  }

  @override
  Future<void> follow(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null || me == userId) return;
    await _client.from('follows').upsert({
      'follower_id': me,
      'following_id': userId,
    });
  }

  @override
  Future<void> unfollow(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return;
    await _client
        .from('follows')
        .delete()
        .eq('follower_id', me)
        .eq('following_id', userId);
  }

  @override
  Future<bool> isFollowing(String userId) async {
    final me = _client.auth.currentUser?.id;
    if (me == null) return false;
    final row = await _client
        .from('follows')
        .select('following_id')
        .eq('follower_id', me)
        .eq('following_id', userId)
        .maybeSingle();
    return row != null;
  }

  @override
  Future<List<Profile>> suggestedAthletes({int limit = 10}) async {
    final me = _client.auth.currentUser?.id;
    final rows = await _client
        .from('profiles')
        .select(_profileSelect)
        .neq('id', me ?? '')
        .order('total_distance_meters', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((e) => Profile.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<Profile>> followers(String userId) async {
    final rows = await _client
        .from('follows')
        .select('profiles!follows_follower_id_fkey($_profileSelect)')
        .eq('following_id', userId);
    return (rows as List)
        .map((e) => Profile.fromJson(
              Map<String, dynamic>.from(
                (e as Map)['profiles'] as Map,
              ),
            ))
        .toList();
  }

  @override
  Future<List<Profile>> following(String userId) async {
    final rows = await _client
        .from('follows')
        .select('profiles!follows_following_id_fkey($_profileSelect)')
        .eq('follower_id', userId);
    return (rows as List)
        .map((e) => Profile.fromJson(
              Map<String, dynamic>.from(
                (e as Map)['profiles'] as Map,
              ),
            ))
        .toList();
  }

  // ----------------------------------------------------------- statistics
  @override
  Future<WeeklySummary> weeklySummary(
    String userId, {
    DateTime? reference,
  }) async {
    final ref = reference ?? DateTime.now();
    final monday = DateTime(ref.year, ref.month, ref.day)
        .subtract(Duration(days: ref.weekday - 1));
    final weekEnd = monday.add(const Duration(days: 7));

    final rows = await _client
        .from('activity_details')
        .select('started_at, distance_meters, moving_seconds, '
            'elevation_gain, calories')
        .eq('user_id', userId)
        .gte('started_at', monday.toIso8601String())
        .lt('started_at', weekEnd.toIso8601String());

    final daily = List<double>.filled(7, 0);
    var dist = 0.0;
    var secs = 0;
    var elev = 0.0;
    var kcal = 0;
    var count = 0;

    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final started = DateTime.parse(row['started_at'] as String).toLocal();
      final idx = started.difference(monday).inDays.clamp(0, 6);
      final d = (row['distance_meters'] as num).toDouble();
      daily[idx] += d;
      dist += d;
      secs += (row['moving_seconds'] as num).toInt();
      elev += (row['elevation_gain'] as num).toDouble();
      kcal += (row['calories'] as num?)?.toInt() ?? 0;
      count++;
    }

    return WeeklySummary(
      weekStart: monday,
      distanceMeters: dist,
      movingSeconds: secs,
      elevationGain: elev,
      activityCount: count,
      calories: kcal,
      dailyDistances: daily,
    );
  }

  @override
  Future<List<PersonalRecord>> personalRecords(String userId) async {
    // PR spanduk: query agregat langsung di Postgres.
    final row = await _client.rpc('personal_records', params: {
      'p_user_id': userId,
    });
    if (row is List) {
      return row
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map((r) => PersonalRecord(
                label: r['label'] as String,
                value: r['value'].toString(),
                unit: (r['unit'] ?? '') as String,
                activityId: r['activity_id'] as String?,
              ))
          .toList();
    }
    return const [];
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.week,
    LeaderboardMetric metric = LeaderboardMetric.distance,
    int limit = 50,
  }) async {
    final view = switch (scope) {
      LeaderboardScope.week => 'leaderboard_weekly',
      LeaderboardScope.month => 'leaderboard_monthly',
      LeaderboardScope.year => 'leaderboard_yearly',
      LeaderboardScope.allTime => 'leaderboard_all_time',
    };
    final orderBy = switch (metric) {
      LeaderboardMetric.distance => 'total_distance_meters',
      LeaderboardMetric.elevation => 'total_elevation_meters',
      LeaderboardMetric.pace => 'best_pace_sec_per_km',
    };
    final ascending = metric == LeaderboardMetric.pace;

    final rows = await _client
        .from(view)
        .select()
        .order(orderBy, ascending: ascending)
        .limit(limit);

    return [
      for (var i = 0; i < (rows as List).length; i++)
        () {
          final row = Map<String, dynamic>.from(rows[i] as Map);
          return LeaderboardEntry(
            profile: Profile(
              id: row['user_id'] as String,
              username: (row['username'] ?? 'runner') as String,
              displayName: (row['display_name'] ?? '') as String,
              avatarUrl: row['avatar_url'] as String?,
              city: (row['city'] ?? '') as String,
            ),
            totalDistanceMeters:
                (row['total_distance_meters'] as num?)?.toDouble() ?? 0,
            activityCount: (row['activity_count'] as num?)?.toInt() ?? 0,
            totalElevationMeters:
                (row['total_elevation_meters'] as num?)?.toDouble() ?? 0,
            bestPaceSecPerKm:
                (row['best_pace_sec_per_km'] as num?)?.toDouble() ?? 0,
            rank: i + 1,
          );
        }(),
    ];
  }

  @override
  Future<List<(DateTime, double)>> dailyVolume(
    String userId, {
    int days = 30,
  }) async {
    final start = DateTime.now().subtract(Duration(days: days));
    final rows = await _client
        .from('activity_details')
        .select('started_at, distance_meters')
        .eq('user_id', userId)
        .gte('started_at', start.toIso8601String());

    final map = <String, double>{};
    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final day = DateTime.parse(row['started_at'] as String).toLocal();
      final key = '${day.year}-${day.month}-${day.day}';
      map[key] = (map[key] ?? 0) + (row['distance_meters'] as num).toDouble();
    }

    final today = DateTime.now();
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final day = DateTime(today.year, today.month, today.day)
              .subtract(Duration(days: i));
          final key = '${day.year}-${day.month}-${day.day}';
          return (day, map[key] ?? 0);
        }(),
    ];
  }

  void dispose() {
    _authSub?.cancel();
    _authController.close();
  }
}
