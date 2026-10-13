import '../models/models.dart';

/// Filter periode untuk leaderboard.
enum LeaderboardScope { week, month, year, allTime }

extension LeaderboardScopeLabel on LeaderboardScope {
  String get label => switch (this) {
        LeaderboardScope.week => 'Minggu ini',
        LeaderboardScope.month => 'Bulan ini',
        LeaderboardScope.year => 'Tahun ini',
        LeaderboardScope.allTime => 'Sepanjang waktu',
      };
}

enum LeaderboardMetric { distance, elevation, pace }

extension LeaderboardMetricLabel on LeaderboardMetric {
  String get label => switch (this) {
        LeaderboardMetric.distance => 'Jarak',
        LeaderboardMetric.elevation => 'Elevasi',
        LeaderboardMetric.pace => 'Pace terbaik',
      };
}

/// Kesalahan yang bisa ditampilkan ke pengguna.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// Kontrak tunggal untuk semua sumber data.
///
/// Ada dua implementasi:
/// * [LocalRepository] — SharedPreferences, bisa jalan tanpa backend.
/// * [SupabaseRepository] — Postgres + Auth + Storage + Realtime.
///
/// UI hanya bergantung pada antarmuka ini, sehingga mode demo dan mode
/// produksi memakai kode halaman yang sama.
abstract class PaceUpRepository {
  // ------------------------------------------------------------------ auth
  Future<bool> get isSignedIn;
  Profile? get cachedProfile;
  Stream<Profile?> watchAuth();
  Future<void> bootstrap();

  Future<Profile> signInWithPassword({
    required String email,
    required String password,
  });

  Future<Profile> signUp({
    required String email,
    required String password,
    required String username,
    String? displayName,
  });

  Future<void> signOut();

  Future<Profile> updateProfile(Profile profile);

  Future<Profile?> profileByUsername(String username);

  // ------------------------------------------------------------ activities
  Future<List<Activity>> activitiesOf(
    String userId, {
    int limit = 50,
    int offset = 0,
  });

  Future<Activity?> activityById(String id);

  Future<Activity> saveActivity(Activity activity, {List<RunPoint>? points});

  Future<void> deleteActivity(String id);

  Future<void> updateActivityMeta(
    String id, {
    String? title,
    String? description,
    String? visibility,
  });

  /// Unggah aktivitas yang tertunda saat offline.
  Future<int> flushPendingUploads();

  Future<int> pendingUploadCount();

  // ---------------------------------------------------------------- social
  Future<List<FeedItem>> feed({int limit = 30, int offset = 0});

  Future<bool> hasKudosed(String activityId, String userId);

  Future<int> toggleKudos(String activityId);

  Future<List<ActivityComment>> comments(String activityId);

  Future<ActivityComment> addComment(String activityId, String body);

  Future<void> follow(String userId);

  Future<void> unfollow(String userId);

  Future<bool> isFollowing(String userId);

  Future<List<Profile>> suggestedAthletes({int limit = 10});

  Future<List<Profile>> followers(String userId);

  Future<List<Profile>> following(String userId);

  // ----------------------------------------------------------- statistics
  Future<WeeklySummary> weeklySummary(String userId, {DateTime? reference});

  Future<List<PersonalRecord>> personalRecords(String userId);

  Future<List<LeaderboardEntry>> leaderboard({
    LeaderboardScope scope = LeaderboardScope.week,
    LeaderboardMetric metric = LeaderboardMetric.distance,
    int limit = 50,
  });

  /// Data mentah untuk grafik volume latihan harian (N hari terakhir).
  Future<List<(DateTime, double)>> dailyVolume(String userId, {int days = 30});
}
