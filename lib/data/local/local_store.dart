import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Penyimpanan lokal berbasis SharedPreferences.
///
/// Dipakai untuk dua hal:
/// 1. **Mode offline/demo** — seluruh data (akun, aktivitas, kudos, komentar,
///    follow) hidup di sini tanpa backend.
/// 2. **Cache & antrean sinkronisasi** — saat memakai Supabase, aktivitas yang
///    direkam tanpa koneksi disimpan dulu lalu diunggah (`pendingActivities`).
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  // --- keys ---
  static const _kUsers = 'paceup.users';
  static const _kSession = 'paceup.session';
  static const _kActivities = 'paceup.activities';
  static const _kKudos = 'paceup.kudos';
  static const _kComments = 'paceup.comments';
  static const _kFollows = 'paceup.follows';
  static const _kPending = 'paceup.pending_activities';
  static const _kSeeded = 'paceup.seeded_v1';

  bool get isSeeded => _prefs.getBool(_kSeeded) ?? false;

  Future<void> markSeeded() => _prefs.setBool(_kSeeded, true);

  // --- session ---
  String? get sessionUserId => _prefs.getString(_kSession);

  Future<void> setSession(String? userId) async {
    if (userId == null) {
      await _prefs.remove(_kSession);
    } else {
      await _prefs.setString(_kSession, userId);
    }
  }

  // --- users (akun demo: email -> {password, profile}) ---
  Map<String, Map<String, dynamic>> get _users {
    final raw = _prefs.getString(_kUsers);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)),
    );
  }

  List<Profile> allProfiles() => _users.values
      .map((e) => Profile.fromJson(Map<String, dynamic>.from(e['profile'] as Map)))
      .toList();

  Profile? profileById(String id) {
    for (final entry in _users.values) {
      final p = Profile.fromJson(
        Map<String, dynamic>.from(entry['profile'] as Map),
      );
      if (p.id == id) return p;
    }
    return null;
  }

  Profile? profileByEmail(String email) {
    final entry = _users[email.toLowerCase()];
    if (entry == null) return null;
    return Profile.fromJson(
      Map<String, dynamic>.from(entry['profile'] as Map),
    );
  }

  String? passwordFor(String email) =>
      _users[email.toLowerCase()]?['password'] as String?;

  String? emailFor(String username) {
    for (final entry in _users.entries) {
      final profileMap = entry.value['profile'] as Map;
      if ((profileMap['username'] as String).toLowerCase() ==
          username.toLowerCase()) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> upsertUser({
    required String email,
    required String password,
    required Profile profile,
  }) async {
    final users = _users;
    users[email.toLowerCase()] = {
      'password': password,
      'profile': profile.toJson(),
    };
    await _prefs.setString(_kUsers, jsonEncode(users));
  }

  Future<void> saveProfile(Profile profile) async {
    final users = _users;
    for (final entry in users.entries) {
      final p = Map<String, dynamic>.from(entry.value['profile'] as Map);
      if (p['id'] == profile.id) {
        entry.value['profile'] = profile.toJson();
        await _prefs.setString(_kUsers, jsonEncode(users));
        return;
      }
    }
  }

  // --- activities ---
  List<Activity> allActivities() {
    final raw = _prefs.getString(_kActivities);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> saveActivities(List<Activity> activities) async {
    await _prefs.setString(
      _kActivities,
      jsonEncode(activities.map((a) => a.toJson(includePoints: true)).toList()),
    );
  }

  Future<void> upsertActivity(Activity activity) async {
    final list = allActivities();
    final idx = list.indexWhere((a) => a.id == activity.id);
    if (idx >= 0) {
      list[idx] = activity;
    } else {
      list.add(activity);
    }
    await saveActivities(list);
  }

  Future<void> removeActivity(String id) async {
    final list = allActivities()..removeWhere((a) => a.id == id);
    await saveActivities(list);
  }

  // --- kudos: activityId -> list userId ---
  Map<String, List<String>> get kudos {
    final raw = _prefs.getString(_kKudos);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as List).cast<String>()));
  }

  Future<void> setKudos(Map<String, List<String>> value) =>
      _prefs.setString(_kKudos, jsonEncode(value));

  // --- comments ---
  List<ActivityComment> commentsFor(String activityId) {
    final raw = _prefs.getString(_kComments);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ActivityComment.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((c) => c.activityId == activityId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<void> addComment(ActivityComment comment) async {
    final raw = _prefs.getString(_kComments);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    list.add(comment.toJson());
    await _prefs.setString(_kComments, jsonEncode(list));
  }

  // --- follows: followerId -> list of followed ids ---
  Map<String, List<String>> get follows {
    final raw = _prefs.getString(_kFollows);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as List).cast<String>()));
  }

  Future<void> setFollows(Map<String, List<String>> value) =>
      _prefs.setString(_kFollows, jsonEncode(value));

  // --- pending upload queue (mode Supabase) ---
  List<Activity> get pendingActivities {
    final raw = _prefs.getString(_kPending);
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Activity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> enqueuePending(Activity activity) async {
    final list = pendingActivities
        .where((a) => a.id != activity.id)
        .toList()
      ..add(activity);
    await _prefs.setString(
      _kPending,
      jsonEncode(list.map((a) => a.toJson(includePoints: true)).toList()),
    );
  }

  Future<void> removePending(String id) async {
    final list = pendingActivities.where((a) => a.id != id).toList();
    await _prefs.setString(
      _kPending,
      jsonEncode(list.map((a) => a.toJson(includePoints: true)).toList()),
    );
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}
