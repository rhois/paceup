import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../core/metrics.dart';
import '../local/local_store.dart';
import '../models/models.dart';
import 'paceup_repository.dart';

/// Implementasi repository tanpa backend, memakai [LocalStore].
///
/// Dipakai saat Supabase belum dikonfigurasi (mode demo) dan sebagai basis
/// pengujian. Perilakunya dibuat semirip mungkin dengan versi server:
/// feed berisi aktivitas orang yang diikuti, kudos bisa di-toggle,
/// leaderboard dihitung dari periode.
class LocalRepository implements PaceUpRepository {
  LocalRepository(this._store);

  final LocalStore _store;
  final _uuid = const Uuid();
  final _authController = _ValueNotifier<Profile?>(null);

  Profile? _profile;

  // ------------------------------------------------------------------ auth
  @override
  Future<void> bootstrap() async {
    await _seedIfNeeded();
    final id = _store.sessionUserId;
    if (id != null) {
      _profile = _store.profileById(id);
      _authController.value = _profile;
    }
  }

  @override
  Future<bool> get isSignedIn async => _profile != null;

  @override
  Profile? get cachedProfile => _profile;

  @override
  Stream<Profile?> watchAuth() => _authController.stream;

  @override
  Future<Profile> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final normalized = email.trim().toLowerCase();
    final stored = _store.passwordFor(normalized);
    if (stored == null) {
      throw const AppFailure(
        'Email belum terdaftar. Coba daftar dulu, ya.',
        code: 'user-not-found',
      );
    }
    if (stored != password) {
      throw const AppFailure('Kata sandi salah.', code: 'wrong-password');
    }
    final profile = _store.profileByEmail(normalized)!;
    _profile = profile;
    _authController.value = profile;
    await _store.setSession(profile.id);
    return profile;
  }

  @override
  Future<Profile> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  }) async {
    final normalized = email.trim().toLowerCase();
    if (_store.passwordFor(normalized) != null) {
      throw const AppFailure('Email sudah dipakai.', code: 'email-taken');
    }
    if (_store.emailFor(username) != null) {
      throw const AppFailure('Username sudah dipakai.', code: 'username-taken');
    }
    final profile = Profile(
      id: 'u_${_uuid.v4().substring(0, 8)}',
      username: username.trim(),
      displayName: (displayName ?? username).trim(),
      createdAt: DateTime.now(),
    );
    await _store.upsertUser(
      email: normalized,
      password: password,
      profile: profile,
    );
    _profile = profile;
    _authController.value = profile;
    await _store.setSession(profile.id);
    return profile;
  }

  @override
  Future<void> signOut() async {
    _profile = null;
    _authController.value = null;
    await _store.setSession(null);
  }

  @override
  Future<Profile> updateProfile(Profile profile) async {
    await _store.saveProfile(profile);
    if (_profile?.id == profile.id) {
      _profile = profile;
      _authController.value = profile;
    }
    return profile;
  }

  @override
  Future<Profile?> profileByUsername(String username) async => _store
      .allProfiles()
      .where((p) => p.username.toLowerCase() == username.toLowerCase())
      .firstOrNull;

  // ------------------------------------------------------------ activities
  @override
  Future<List<Activity>> activitiesOf(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final list = _store.allActivities()
        .where((a) => a.userId == userId)
        .toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return list.skip(offset).take(limit).toList();
  }

  @override
  Future<Activity?> activityById(String id) async =>
      _store.allActivities().where((a) => a.id == id).firstOrNull;

  @override
  Future<Activity> saveActivity(
    Activity activity, {
    List<RunPoint>? points,
  }) async {
    final toSave = points == null
        ? activity
        : Activity(
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
            mapPolyline: PolylineCodec.encode(points),
            points: points,
            createdAt: activity.createdAt ?? DateTime.now(),
            achievements: activity.achievements,
          );
    await _store.upsertActivity(toSave);
    return toSave;
  }

  @override
  Future<void> deleteActivity(String id) => _store.removeActivity(id);

  @override
  Future<void> updateActivityMeta(
    String id, {
    String? title,
    String? description,
    String? visibility,
  }) async {
    final list = _store.allActivities();
    final idx = list.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    list[idx] = list[idx].copyWith(
      title: title,
      description: description,
      visibility: visibility,
    );
    await _store.saveActivities(list);
  }

  @override
  Future<int> flushPendingUploads() async {
    // Mode lokal: tidak ada server, jadi cukup pindahkan dari antrean ke
    // penyimpanan utama.
    final pending = _store.pendingActivities;
    for (final a in pending) {
      await _store.upsertActivity(a.copyWith(synced: true));
      await _store.removePending(a.id);
    }
    return pending.length;
  }

  @override
  Future<int> pendingUploadCount() async => _store.pendingActivities.length;

  // ---------------------------------------------------------------- social
  @override
  Future<List<FeedItem>> feed({int limit = 30, int offset = 0}) async {
    final me = _profile;
    if (me == null) return [];
    final following = _followingIds(me.id).toSet()..add(me.id);
    final profiles = {for (final p in _store.allProfiles()) p.id: p};
    final kudosMap = _store.kudos;

    final items = _store.allActivities()
        .where((a) => following.contains(a.userId))
        .map((a) {
          final owner = profiles[a.userId];
          if (owner == null) return null;
          final kudosers = kudosMap[a.id] ?? const <String>[];
          return FeedItem(
            activity: a.copyWith(kudosCount: kudosers.length),
            owner: owner,
            hasKudosed: kudosers.contains(me.id),
            isFollowing: _followingIds(me.id).contains(a.userId),
          );
        })
        .whereType<FeedItem>()
        .toList()
      ..sort((a, b) => b.activity.startedAt.compareTo(a.activity.startedAt));
    return items.skip(offset).take(limit).toList();
  }

  @override
  Future<bool> hasKudosed(String activityId, String userId) async =>
      (_store.kudos[activityId] ?? const []).contains(userId);

  @override
  Future<int> toggleKudos(String activityId) async {
    final me = _profile;
    if (me == null) throw const AppFailure('Belum masuk.');
    final map = _store.kudos;
    final list = [...(map[activityId] ?? const <String>[])];
    if (list.contains(me.id)) {
      list.remove(me.id);
    } else {
      list.add(me.id);
    }
    map[activityId] = list;
    await _store.setKudos(map);

    // Sinkronkan angka di aktivitas agar tampil konsisten.
    final activities = _store.allActivities();
    final idx = activities.indexWhere((a) => a.id == activityId);
    if (idx >= 0) {
      activities[idx] = activities[idx].copyWith(kudosCount: list.length);
      await _store.saveActivities(activities);
    }
    return list.length;
  }

  @override
  Future<List<ActivityComment>> comments(String activityId) async {
    final profiles = {for (final p in _store.allProfiles()) p.id: p};
    return _store.commentsFor(activityId).map((c) {
      return ActivityComment(
        id: c.id,
        activityId: c.activityId,
        userId: c.userId,
        body: c.body,
        createdAt: c.createdAt,
        author: c.author ?? profiles[c.userId],
      );
    }).toList();
  }

  @override
  Future<ActivityComment> addComment(String activityId, String body) async {
    final me = _profile;
    if (me == null) throw const AppFailure('Belum masuk.');
    final comment = ActivityComment(
      id: _uuid.v4(),
      activityId: activityId,
      userId: me.id,
      body: body.trim(),
      createdAt: DateTime.now(),
      author: me,
    );
    await _store.addComment(comment);

    final activities = _store.allActivities();
    final idx = activities.indexWhere((a) => a.id == activityId);
    if (idx >= 0) {
      activities[idx] =
          activities[idx].copyWith(commentCount: activities[idx].commentCount + 1);
      await _store.saveActivities(activities);
    }
    return comment;
  }

  @override
  Future<void> follow(String userId) async {
    final me = _profile;
    if (me == null || userId == me.id) return;
    final map = _store.follows;
    final list = [...(map[me.id] ?? const <String>[])];
    if (!list.contains(userId)) list.add(userId);
    map[me.id] = list;
    await _store.setFollows(map);
  }

  @override
  Future<void> unfollow(String userId) async {
    final me = _profile;
    if (me == null) return;
    final map = _store.follows;
    final list = [...(map[me.id] ?? const <String>[])]..remove(userId);
    map[me.id] = list;
    await _store.setFollows(map);
  }

  @override
  Future<bool> isFollowing(String userId) async {
    final me = _profile;
    if (me == null) return false;
    return _followingIds(me.id).contains(userId);
  }

  @override
  Future<List<Profile>> suggestedAthletes({int limit = 10}) async {
    final me = _profile;
    if (me == null) return [];
    final following = _followingIds(me.id).toSet();
    return _store
        .allProfiles()
        .where((p) => p.id != me.id && !following.contains(p.id))
        .take(limit)
        .toList();
  }

  @override
  Future<List<Profile>> followers(String userId) async {
    final map = _store.follows;
    final ids = map.entries
        .where((e) => e.value.contains(userId))
        .map((e) => e.key)
        .toSet();
    return _store.allProfiles().where((p) => ids.contains(p.id)).toList();
  }

  @override
  Future<List<Profile>> following(String userId) async =>
      _store.allProfiles().where((p) => _followingIds(userId).contains(p.id)).toList();

  List<String> _followingIds(String userId) =>
      _store.follows[userId] ?? const <String>[];

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

    final list = (await activitiesOf(userId, limit: 1000))
        .where((a) => !a.startedAt.isBefore(monday) && a.startedAt.isBefore(weekEnd))
        .toList();

    final daily = List<double>.filled(7, 0);
    var dist = 0.0;
    var secs = 0;
    var elev = 0.0;
    var kcal = 0;
    for (final a in list) {
      final dayIdx = a.startedAt.difference(monday).inDays.clamp(0, 6);
      daily[dayIdx] += a.distanceMeters;
      dist += a.distanceMeters;
      secs += a.movingSeconds;
      elev += a.elevationGain;
      kcal += a.calories;
    }

    return WeeklySummary(
      weekStart: monday,
      distanceMeters: dist,
      movingSeconds: secs,
      elevationGain: elev,
      activityCount: list.length,
      calories: kcal,
      dailyDistances: daily,
    );
  }

  @override
  Future<List<PersonalRecord>> personalRecords(String userId) async {
    final all = await activitiesOf(userId, limit: 1000);
    final records = <PersonalRecord>[];

    Activity? longest;
    for (final a in all) {
      if (longest == null || a.distanceMeters > longest.distanceMeters) {
        longest = a;
      }
    }
    if (longest != null) {
      records.add(PersonalRecord(
        label: 'Jarak terjauh',
        value: formatDistance(longest.distanceMeters, decimals: 2)
            .replaceAll(' km', ''),
        unit: 'km',
        activityId: longest.id,
        achievedAt: longest.startedAt,
      ));
    }

    // PR 1K / 5K / 10K dari split terbaik.
    for (final target in const [1000.0, 5000.0, 10000.0, 21097.5]) {
      final best = _bestEffort(all, target);
      if (best != null) {
        records.add(PersonalRecord(
          label: _prLabel(target),
          value: formatDuration(best.$1),
          unit: '',
          activityId: best.$2,
        ));
      }
    }

    Activity? fastest;
    for (final a in all) {
      if (a.distanceMeters < 1000 || a.paceSecPerKm <= 0) continue;
      if (fastest == null || a.paceSecPerKm < fastest.paceSecPerKm) fastest = a;
    }
    if (fastest != null) {
      records.add(PersonalRecord(
        label: 'Pace terbaik',
        value: formatPace(fastest.paceSecPerKm),
        unit: '/km',
        activityId: fastest.id,
        achievedAt: fastest.startedAt,
      ));
    }

    Activity? climber;
    for (final a in all) {
      if (climber == null || a.elevationGain > climber.elevationGain) {
        climber = a;
      }
    }
    if (climber != null && climber.elevationGain > 0) {
      records.add(PersonalRecord(
        label: 'Elevasi terbanyak',
        value: climber.elevationGain.round().toString(),
        unit: 'm',
        activityId: climber.id,
        achievedAt: climber.startedAt,
      ));
    }

    return records;
  }

  /// Cari waktu tercepat untuk menempuh [target] meter (rolling window).
  (Duration, String)? _bestEffort(List<Activity> activities, double target) {
    (Duration, String)? best;
    for (final a in activities) {
      if (a.points.length < 2 || a.distanceMeters < target) continue;
      for (var i = 0; i < a.points.length; i++) {
        var dist = 0.0;
        for (var j = i + 1; j < a.points.length; j++) {
          dist += a.points[j].distanceDelta;
          if (dist >= target) {
            final dur = a.points[j].recordedAt.difference(a.points[i].recordedAt);
            if (best == null || dur < best.$1) best = (dur, a.id);
            break;
          }
        }
      }
    }
    return best;
  }

  String _prLabel(double meters) {
    if (meters < 1000) return '${meters.round()} m tercepat';
    if (meters == 21097.5) return 'Half marathon';
    return '${(meters / 1000).round()}K tercepat';
  }

  @override
  Future<List<LeaderboardEntry>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.week,
    LeaderboardMetric metric = LeaderboardMetric.distance,
    int limit = 50,
  }) async {
    final now = DateTime.now();
    DateTime from;
    switch (scope) {
      case LeaderboardScope.week:
        from = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
      case LeaderboardScope.month:
        from = DateTime(now.year, now.month, 1);
      case LeaderboardScope.year:
        from = DateTime(now.year, 1, 1);
      case LeaderboardScope.allTime:
        from = DateTime(2000);
    }

    final profiles = _store.allProfiles();
    final entries = <LeaderboardEntry>[];
    for (final p in profiles) {
      final acts = _store
          .allActivities()
          .where((a) => a.userId == p.id && !a.startedAt.isBefore(from))
          .toList();
      if (acts.isEmpty) continue;
      final dist = acts.fold<double>(0, (s, a) => s + a.distanceMeters);
      final elev = acts.fold<double>(0, (s, a) => s + a.elevationGain);
      final running = acts.where((a) => a.distanceMeters >= 1000);
      final bestPace = running.isEmpty
          ? 0.0
          : running.map((a) => a.paceSecPerKm).reduce(math.min);
      entries.add(LeaderboardEntry(
        profile: p,
        totalDistanceMeters: dist,
        activityCount: acts.length,
        totalElevationMeters: elev,
        bestPaceSecPerKm: bestPace,
      ));
    }

    entries.sort((a, b) => switch (metric) {
          LeaderboardMetric.distance =>
            b.totalDistanceMeters.compareTo(a.totalDistanceMeters),
          LeaderboardMetric.elevation =>
            b.totalElevationMeters.compareTo(a.totalElevationMeters),
          LeaderboardMetric.pace => _paceCompare(a, b),
        });

    return [
      for (var i = 0; i < entries.length && i < limit; i++)
        LeaderboardEntry(
          profile: entries[i].profile,
          totalDistanceMeters: entries[i].totalDistanceMeters,
          activityCount: entries[i].activityCount,
          totalElevationMeters: entries[i].totalElevationMeters,
          bestPaceSecPerKm: entries[i].bestPaceSecPerKm,
          rank: i + 1,
        ),
    ];
  }

  int _paceCompare(LeaderboardEntry a, LeaderboardEntry b) {
    if (a.bestPaceSecPerKm <= 0) return 1;
    if (b.bestPaceSecPerKm <= 0) return -1;
    return a.bestPaceSecPerKm.compareTo(b.bestPaceSecPerKm);
  }

  @override
  Future<List<(DateTime, double)>> dailyVolume(
    String userId, {
    int days = 30,
  }) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    final acts = (await activitiesOf(userId, limit: 1000))
        .where((a) => !a.startedAt.isBefore(start))
        .toList();

    return [
      for (var i = 0; i < days; i++)
        () {
          final day = start.add(Duration(days: i));
          final next = day.add(const Duration(days: 1));
          final total = acts
              .where((a) => !a.startedAt.isBefore(day) && a.startedAt.isBefore(next))
              .fold<double>(0, (s, a) => s + a.distanceMeters);
          return (day, total);
        }(),
    ];
  }

  // ------------------------------------------------------------------ seed
  /// Isi data contoh supaya aplikasi tidak terasa kosong saat pertama dibuka.
  Future<void> _seedIfNeeded() async {
    if (_store.isSeeded) return;
    final rnd = math.Random(7);
    final now = DateTime.now();

    final me = Profile(
      id: 'u_me',
      username: 'kamu',
      displayName: 'Pelari Baru',
      city: 'Jakarta',
      bio: 'Mulai rutin lari tahun ini.',
      createdAt: now,
    );
    await _store.upsertUser(
      email: 'demo@paceup.app',
      password: 'paceup123',
      profile: me,
    );

    final friends = <Profile>[
      Profile(
        id: 'u_budi',
        username: 'budisantoso',
        displayName: 'Budi Santoso',
        city: 'Bandung',
        bio: 'Trail runner. Suka naik gunung pagi-pagi.',
        followerCount: 128,
        followingCount: 74,
        createdAt: now,
      ),
      Profile(
        id: 'u_sari',
        username: 'sari.run',
        displayName: 'Sari Wijaya',
        city: 'Yogyakarta',
        bio: 'Marathoner. PR 3:58.',
        followerCount: 342,
        followingCount: 120,
        createdAt: now,
      ),
      Profile(
        id: 'u_andre',
        username: 'andrew',
        displayName: 'Andre Kusuma',
        city: 'Surabaya',
        bio: 'Pace 4:30 target tahun ini.',
        followerCount: 87,
        followingCount: 65,
        createdAt: now,
      ),
      Profile(
        id: 'u_dita',
        username: 'ditaputri',
        displayName: 'Dita Putri',
        city: 'Denpasar',
        bio: 'Lari santai tiap pagi.',
        followerCount: 55,
        followingCount: 40,
        createdAt: now,
      ),
    ];
    for (final f in friends) {
      await _store.upsertUser(
        email: '${f.username}@paceup.app',
        password: 'paceup123',
        profile: f,
      );
    }

    await _store.setFollows({
      me.id: friends.map((f) => f.id).toList(),
      'u_budi': [me.id],
      'u_sari': [me.id],
      'u_andre': [me.id],
    });

    final activities = <Activity>[];
    for (final friend in friends) {
      final count = friend.id == 'u_sari' ? 5 : 3;
      for (var i = 0; i < count; i++) {
        final daysAgo = rnd.nextInt(9) + i;
        activities.add(_fakeActivity(
          userId: friend.id,
          startedAt: now.subtract(Duration(days: daysAgo, hours: rnd.nextInt(10))),
          baseKm: 5 + rnd.nextDouble() * 12,
          paceSecPerKm: 300 + rnd.nextDouble() * 120,
          rnd: rnd,
          type: friend.id == 'u_budi' && i.isEven
              ? ActivityType.trailRun
              : ActivityType.run,
        ));
      }
    }

    // Aktivitas milik pengguna sendiri.
    activities.add(_fakeActivity(
      userId: me.id,
      startedAt: now.subtract(const Duration(days: 1, hours: 6)),
      baseKm: 8.4,
      paceSecPerKm: 342,
      rnd: rnd,
    ));
    activities.add(_fakeActivity(
      userId: me.id,
      startedAt: now.subtract(const Duration(days: 3, hours: 5)),
      baseKm: 5.2,
      paceSecPerKm: 361,
      rnd: rnd,
    ));

    // Kudos & komentar contoh.
    final kudos = <String, List<String>>{};
    final comments = <Map<String, dynamic>>[];
    for (final a in activities) {
      final likers = <String>[me.id];
      for (final f in friends) {
        if (rnd.nextBool()) likers.add(f.id);
      }
      kudos[a.id] = likers;
      if (rnd.nextBool()) {
        comments.add(ActivityComment(
          id: _uuid.v4(),
          activityId: a.id,
          userId: friends[rnd.nextInt(friends.length)].id,
          body: const [
            'Kencang! 🔥',
            'Mantap, lanjutkan!',
            'Besok bareng, yuk.',
            'Pace-nya rapi banget.',
            'Semangat terus!',
          ][rnd.nextInt(5)],
          createdAt: a.startedAt.add(const Duration(hours: 2)),
        ).toJson());
      }
    }

    await _store.saveActivities(activities);
    await _store.setKudos(kudos);

    // Simpan komentar langsung lewat helper store.
    for (final c in comments) {
      await _store.addComment(ActivityComment.fromJson(c));
    }
    // Sinkronkan counter kudos/komentar ke aktivitas.
    final synced = activities.map((a) {
      final commentCount =
          comments.where((c) => c['activity_id'] == a.id).length;
      return a.copyWith(
        kudosCount: (kudos[a.id] ?? const []).length,
        commentCount: commentCount,
      );
    }).toList();
    await _store.saveActivities(synced);

    _store.markSeeded();
  }

  /// Membangun aktivitas sintetis yang realistis: rute melingkar, elevasi
  /// naik-turun, kecepatan bervariasi, dan split yang masuk akal.
  Activity _fakeActivity({
    required String userId,
    required DateTime startedAt,
    required double baseKm,
    required double paceSecPerKm,
    required math.Random rnd,
    ActivityType type = ActivityType.run,
  }) {
    final centerLat = -6.2 + rnd.nextDouble() * 3;
    final centerLon = 106.8 + rnd.nextDouble() * 4;
    final totalMeters = baseKm * 1000;
    const tickSeconds = 4;
    final speedMps = 1000 / paceSecPerKm;
    final steps = (totalMeters / (speedMps * tickSeconds)).round().clamp(60, 4000);
    final radiusDeg = totalMeters / (2 * math.pi) / 111320.0;

    final points = <RunPoint>[];
    for (var i = 0; i < steps; i++) {
      final angle = 2 * math.pi * i / steps;
      // Radius bervariasi supaya rutenya tidak bulat sempurna.
      final wobble = 1 + 0.18 * math.sin(angle * 3 + rnd.nextDouble());
      final lat = centerLat + radiusDeg * wobble * math.cos(angle);
      final lon = centerLon +
          radiusDeg * wobble * math.sin(angle) / math.cos(centerLat * math.pi / 180);
      final t = startedAt.add(Duration(seconds: i * tickSeconds));

      final jitter = 0.9 + rnd.nextDouble() * 0.2;
      final stepDist = speedMps * tickSeconds * jitter;

      points.add(RunPoint(
        lat: lat,
        lon: lon,
        recordedAt: t,
        altitude: 40 + 25 * math.sin(angle * 2) + rnd.nextDouble() * 2,
        speedMps: speedMps * jitter,
        distanceDelta: i == 0 ? 0 : stepDist,
        accuracy: 5 + rnd.nextDouble() * 6,
        cadence: 168 + rnd.nextInt(12),
        heartRate: 148 + rnd.nextInt(18),
      ));
    }

    final metrics = MetricsEngine.compute(
      points,
      splitUnitMeters: 1000,
      avgHeartRate: 152 + rnd.nextInt(12),
    );

    final templates = const [
      'Morning run',
      'Easy run',
      'Tempo run',
      'Long run',
      'Recovery run',
      'Sunset run',
    ];

    return Activity(
      id: 'a_${_uuid.v4().substring(0, 8)}',
      userId: userId,
      type: type,
      startedAt: startedAt,
      title: templates[rnd.nextInt(templates.length)],
      description: rnd.nextBool() ? 'Cuaca cerah, badan terasa enak.' : '',
      distanceMeters: metrics.distanceMeters,
      movingSeconds: metrics.movingDuration.inSeconds,
      elapsedSeconds: metrics.elapsedDuration.inSeconds,
      elevationGain: metrics.elevationGain,
      elevationLoss: metrics.elevationLoss,
      avgPaceSecPerKm: metrics.avgMovingPaceSecPerKm,
      maxSpeedKmh: metrics.maxSpeedKmh,
      avgHeartRate: metrics.avgHeartRate,
      avgCadenceSpm: metrics.avgCadenceSpm,
      calories: metrics.calories,
      mapPolyline: PolylineCodec.encode(points),
      points: points,
      createdAt: startedAt,
      visibility: 'followers',
    );
  }
}

/// Notifier sederhana agar repository tidak perlu bergantung pada Riverpod.
class _ValueNotifier<T> {
  T _value;
  _ValueNotifier(this._value);

  final _listeners = <void Function(T)>[];

  T get value => _value;

  set value(T next) {
    _value = next;
    for (final l in [..._listeners]) {
      l(next);
    }
  }

  Stream<T> get stream async* {
    yield _value;
    final controller = StreamController<T>();
    void listener(T v) => controller.add(v);
    _listeners.add(listener);
    try {
      yield* controller.stream;
    } finally {
      _listeners.remove(listener);
      await controller.close();
    }
  }
}
