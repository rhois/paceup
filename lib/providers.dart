import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'data/local/local_store.dart';
import 'data/models/models.dart';
import 'data/repositories/paceup_repository.dart';
import 'services/recording_controller.dart';

/// Di-override saat startup (lihat `main.dart`).
final repositoryProvider = Provider<PaceUpRepository>(
  (ref) => throw UnimplementedError('repository belum di-override'),
);

/// Penyimpanan lokal; dipakai mode demo & antrean sinkronisasi offline.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStore belum di-override'),
);

/// True bila aplikasi berjalan di mode demo/offline.
final isDemoModeProvider = Provider<bool>((ref) => !AppEnv.hasSupabase);

/// Aliran status autentikasi.
final authStateProvider = StreamProvider<Profile?>((ref) {
  return ref.watch(repositoryProvider).watchAuth();
});

/// Profil pengguna yang sedang masuk.
final currentProfileProvider = Provider<Profile?>((ref) {
  final async = ref.watch(authStateProvider);
  return async.valueOrNull ?? ref.watch(repositoryProvider).cachedProfile;
});

/// Profil sendiri (non-null) — dipakai di halaman yang wajib login.
final meProvider = Provider<Profile?>((ref) => ref.watch(currentProfileProvider));

// ---------------------------------------------------------------- activities

final myActivitiesProvider = FutureProvider.autoDispose<List<Activity>>((ref) async {
  final me = ref.watch(currentProfileProvider);
  if (me == null) return [];
  final repo = ref.watch(repositoryProvider);
  final list = await repo.activitiesOf(me.id, limit: 100);
  return list;
});

final activityDetailProvider =
    FutureProvider.autoDispose.family<Activity?, String>((ref, id) async {
  final repo = ref.watch(repositoryProvider);
  return repo.activityById(id);
});

final activityCommentsProvider =
    FutureProvider.autoDispose.family<List<ActivityComment>, String>((ref, id) async {
  final repo = ref.watch(repositoryProvider);
  return repo.comments(id);
});

/// Feed aktivitas orang yang diikuti + diri sendiri.
final feedProvider = FutureProvider.autoDispose<List<FeedItem>>((ref) async {
  final me = ref.watch(currentProfileProvider);
  if (me == null) return [];
  final repo = ref.watch(repositoryProvider);
  return repo.feed(limit: 40);
});

final weeklySummaryProvider = FutureProvider.autoDispose<WeeklySummary>((ref) async {
  final me = ref.watch(currentProfileProvider);
  if (me == null) {
    return WeeklySummary(
      weekStart: DateTime.now(),
      distanceMeters: 0,
      movingSeconds: 0,
      elevationGain: 0,
      activityCount: 0,
      calories: 0,
      dailyDistances: List.filled(7, 0),
    );
  }
  final repo = ref.watch(repositoryProvider);
  return repo.weeklySummary(me.id);
});

final personalRecordsProvider =
    FutureProvider.autoDispose<List<PersonalRecord>>((ref) async {
  final me = ref.watch(currentProfileProvider);
  if (me == null) return [];
  final repo = ref.watch(repositoryProvider);
  return repo.personalRecords(me.id);
});

final dailyVolumeProvider =
    FutureProvider.autoDispose<List<(DateTime, double)>>((ref) async {
  final me = ref.watch(currentProfileProvider);
  if (me == null) return [];
  final repo = ref.watch(repositoryProvider);
  return repo.dailyVolume(me.id, days: 30);
});

// ------------------------------------------------------------------- social

/// Kunci leaderboard: scope + metrik.
class LeaderboardQuery {
  const LeaderboardQuery({
    this.scope = LeaderboardScope.week,
    this.metric = LeaderboardMetric.distance,
  });

  final LeaderboardScope scope;
  final LeaderboardMetric metric;

  @override
  bool operator ==(Object other) =>
      other is LeaderboardQuery && other.scope == scope && other.metric == metric;

  @override
  int get hashCode => Object.hash(scope, metric);
}

final leaderboardQueryProvider = StateProvider<LeaderboardQuery>(
  (ref) => const LeaderboardQuery(),
);

final leaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) async {
  final query = ref.watch(leaderboardQueryProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.leaderboard(scope: query.scope, metric: query.metric, limit: 50);
});

final suggestedAthletesProvider =
    FutureProvider.autoDispose<List<Profile>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.suggestedAthletes(limit: 8);
});

final athleteProfileProvider =
    FutureProvider.autoDispose.family<Profile?, String>((ref, username) async {
  final repo = ref.watch(repositoryProvider);
  return repo.profileByUsername(username);
});

final athleteActivitiesProvider =
    FutureProvider.autoDispose.family<List<Activity>, String>((ref, userId) async {
  final repo = ref.watch(repositoryProvider);
  return repo.activitiesOf(userId, limit: 50);
});

final isFollowingProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, userId) async {
  final repo = ref.watch(repositoryProvider);
  return repo.isFollowing(userId);
});

// ------------------------------------------------------------------ session

/// Pengendali perekaman; hidup selama aplikasi (bukan autoDispose) supaya
/// rekaman tidak hilang saat berpindah tab.
final recordingControllerProvider =
    ChangeNotifierProvider<RecordingController>((ref) {
  final controller = RecordingController();
  final profile = ref.read(currentProfileProvider);
  if (profile != null) controller.weightKg = profile.weightKg;
  ref.onDispose(controller.dispose);
  return controller;
});

/// Jumlah aktivitas menunggu unggah (mode Supabase).
final pendingUploadsProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.pendingUploadCount();
});
