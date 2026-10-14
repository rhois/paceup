/// Konfigurasi environment.
///
/// Jalankan dengan:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// ```
///
/// Kunci juga bisa diberikan lewat `SUPABASE_ANON_KEY` (istilah lama
/// Supabase). Keduanya diterima agar proyek lama tetap jalan.
///
/// Jika dikosongkan, aplikasi otomatis berjalan di **mode lokal / offline
/// (demo)** memakai SharedPreferences, sehingga tetap bisa dicoba tanpa
/// backend. Semua fitur inti (login, rekam lari, pace, split, feed,
/// leaderboard) tetap berfungsi.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Istilah baru Supabase (disarankan).
  static const String supabasePublishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Istilah lama; masih didukung untuk kompatibilitas.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Kunci efektif: pakai publishable key bila ada, jika tidak anon key.
  static String get supabaseKey => supabasePublishableKey.isNotEmpty
      ? supabasePublishableKey
      : supabaseAnonKey;

  static const String appName = 'PaceUp';
  static const String userAgent = 'com.paceup.app';

  /// True bila Supabase dikonfigurasi -> pakai repository remote.
  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
