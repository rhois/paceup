/// Konfigurasi environment.
///
/// Jalankan dengan:
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// Jika dikosongkan, aplikasi otomatis berjalan di **mode lokal / offline
/// (demo)** memakai SharedPreferences, sehingga tetap bisa dicoba tanpa
/// backend. Semua fitur inti (login, rekam lari, pace, split, feed,
/// leaderboard) tetap berfungsi.
class AppEnv {
  const AppEnv._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String appName = 'PaceUp';
  static const String userAgent = 'com.paceup.app';

  /// True bila Supabase dikonfigurasi -> pakai repository remote.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
