import '../core/env.dart';
import '../data/local/local_store.dart';
import '../data/repositories/paceup_repository.dart';

/// Mengurus aktivitas yang direkam tanpa koneksi.
///
/// Saat mode Supabase aktif dan unggahan gagal, aktivitas disimpan di
/// [LocalStore.pendingActivities]. Saat aplikasi dibuka lagi (atau saat
/// pengguna menekan "sinkronkan"), antrean dikosongkan.
class SyncService {
  const SyncService(this._repo, this._store);

  final PaceUpRepository _repo;
  final LocalStore _store;

  bool get enabled => AppEnv.hasSupabase;

  /// Jumlah aktivitas menunggu unggah.
  Future<int> pendingCount() async =>
      enabled ? _store.pendingActivities.length : 0;

  /// Simpan ke antrean lokal.
  Future<void> enqueue(dynamic activity) async {
    await _store.enqueuePending(activity);
  }

  /// Coba unggah semua aktivitas dalam antrean.
  ///
  /// Mengembalikan jumlah yang berhasil. Yang gagal tetap di antrean.
  Future<int> flush() async {
    if (!enabled) return 0;
    final pending = _store.pendingActivities;
    var uploaded = 0;
    for (final activity in pending) {
      try {
        await _repo.saveActivity(activity, points: activity.points);
        await _store.removePending(activity.id);
        uploaded++;
      } on AppFailure {
        // Masih offline — hentikan, coba lagi nanti.
        break;
      }
    }
    return uploaded;
  }
}
