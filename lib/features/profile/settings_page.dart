import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/paceup_repository.dart';
import '../../providers.dart';
import '../../services/sync_service.dart';
import '../../widgets/common.dart';

/// Pengaturan & penyuntingan profil.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  final _weight = TextEditingController();
  final _height = TextEditingController();
  final _avatar = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  bool _private = false;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _city.dispose();
    _bio.dispose();
    _weight.dispose();
    _height.dispose();
    _avatar.dispose();
    super.dispose();
  }

  void _hydrate(Profile me) {
    if (_initialized) return;
    _initialized = true;
    _name.text = me.displayName;
    _username.text = me.username;
    _city.text = me.city;
    _bio.text = me.bio;
    _weight.text = me.weightKg.toStringAsFixed(0);
    _height.text = me.heightCm.toStringAsFixed(0);
    _avatar.text = me.avatarUrl ?? '';
    _private = me.isPrivate;
  }

  Future<void> _save(Profile me) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final updated = me.copyWith(
        displayName: _name.text.trim(),
        username: _username.text.trim(),
        city: _city.text.trim(),
        bio: _bio.text.trim(),
        weightKg: double.tryParse(_weight.text.replaceAll(',', '.')) ?? me.weightKg,
        heightCm: double.tryParse(_height.text) ?? me.heightCm,
        avatarUrl: _avatar.text.trim().isEmpty ? null : _avatar.text.trim(),
        isPrivate: _private,
      );
      await ref.read(repositoryProvider).updateProfile(updated);
      ref.invalidate(currentProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil diperbarui.')),
      );
      context.pop();
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Keluar?'),
        content: const Text('Kamu perlu masuk lagi untuk melanjutkan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(repositoryProvider).signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _resetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hapus semua data lokal?'),
        content: const Text(
          'Seluruh data demo di perangkat ini akan dihapus dan dibuat ulang '
          'saat aplikasi dibuka lagi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localStoreProvider).clearAll();
    if (mounted) context.go('/login');
  }

  Future<void> _sync() async {
    final sync = SyncService(
      ref.read(repositoryProvider),
      ref.read(localStoreProvider),
    );
    final uploaded = await sync.flush();
    ref.invalidate(pendingUploadsProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploaded == 0
                ? 'Tidak ada aktivitas untuk diunggah.'
                : '$uploaded aktivitas berhasil diunggah.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentProfileProvider);
    if (me == null) {
      return const Scaffold(body: LoadingRow());
    }
    _hydrate(me);

    final pending = ref.watch(pendingUploadsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Profil'),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama tampilan'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Nama wajib diisi.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixText: '@',
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (value.length < 3) return 'Minimal 3 karakter.';
                if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value)) {
                  return 'Hanya huruf, angka, titik, dan garis bawah.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Kota',
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bio,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Bio'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _avatar,
              decoration: const InputDecoration(
                labelText: 'URL foto profil (opsional)',
                prefixIcon: Icon(Icons.image_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 22),
            _section('Data tubuh'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _weight,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Berat',
                      suffixText: 'kg',
                    ),
                    validator: (v) {
                      final value = double.tryParse((v ?? '').replaceAll(',', '.'));
                      if (value == null || value <= 0) return 'Isi angka.';
                      if (value > 300) return 'Terlalu besar.';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _height,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tinggi',
                      suffixText: 'cm',
                    ),
                    validator: (v) {
                      final value = double.tryParse(v ?? '');
                      if (value == null || value <= 0) return 'Isi angka.';
                      if (value > 260) return 'Terlalu besar.';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Berat badan dipakai untuk estimasi kalori dan VO₂max.',
              style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 22),
            _section('Privasi'),
            SwitchListTile(
              value: _private,
              onChanged: (v) => setState(() => _private = v),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.brand,
              title: const Text('Profil privat', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Hanya pengikut yang disetujui bisa melihat aktivitasmu.',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ),
            const SizedBox(height: 22),
            _section('Akun & data'),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                children: [
                  _infoRow('Mode', AppEnv.hasSupabase ? 'Supabase (online)' : 'Demo lokal'),
                  _infoRow('Backend', AppEnv.hasSupabase ? AppEnv.supabaseUrl : '—'),
                  _infoRow('ID pengguna', me.id),
                  pending.maybeWhen(
                    data: (n) => _infoRow('Menunggu unggah', '$n aktivitas'),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (pending.valueOrNull != null && (pending.valueOrNull ?? 0) > 0)
              OutlinedButton.icon(
                onPressed: _sync,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('Sinkronkan sekarang'),
              ),
            if (!AppEnv.hasSupabase) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _resetData,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Reset data demo'),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(me),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_saving ? 'Menyimpan…' : 'Simpan perubahan'),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Keluar dari akun'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
            const SizedBox(height: 20),
            const Text(
              'PaceUp v0.1.0 · Level up every run.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 120,
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}
