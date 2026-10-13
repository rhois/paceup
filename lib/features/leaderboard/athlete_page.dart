import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/paceup_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../home/widgets/activity_card.dart';

/// Profil atlet lain: statistik, tombol follow, daftar aktivitas.
class AthletePage extends ConsumerStatefulWidget {
  const AthletePage({required this.username, super.key});

  final String username;

  @override
  ConsumerState<AthletePage> createState() => _AthletePageState();
}

class _AthletePageState extends ConsumerState<AthletePage> {
  bool _following = false;
  bool _busy = false;
  bool _loadedFollowState = false;

  Future<void> _toggleFollow(String userId) async {
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    try {
      if (_following) {
        await repo.unfollow(userId);
      } else {
        await repo.follow(userId);
      }
      setState(() => _following = !_following);
      ref.invalidate(feedProvider);
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(athleteProfileProvider(widget.username));

    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingRow()),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat profil',
          message: '$e',
          actionLabel: 'Coba lagi',
          onAction: () =>
              ref.invalidate(athleteProfileProvider(widget.username)),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'Atlet tidak ditemukan',
              message: 'Username mungkin salah atau akun sudah dihapus.',
            ),
          );
        }
        return _content(profile);
      },
    );
  }

  Widget _content(Profile profile) {
    final me = ref.watch(currentProfileProvider);
    final isMe = me?.id == profile.id;
    final activities = ref.watch(athleteActivitiesProvider(profile.id));

    if (!_loadedFollowState && !isMe) {
      _loadedFollowState = true;
      ref.read(isFollowingProvider(profile.id).future).then((value) {
        if (mounted) setState(() => _following = value);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('@${profile.username}'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _header(profile, isMe)),
          if (!isMe)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SizedBox(
                  width: double.infinity,
                  child: _following
                      ? OutlinedButton.icon(
                          onPressed: _busy ? null : () => _toggleFollow(profile.id),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Mengikuti'),
                        )
                      : FilledButton.icon(
                          onPressed: _busy ? null : () => _toggleFollow(profile.id),
                          icon: const Icon(Icons.person_add_alt, size: 18),
                          label: const Text('Ikuti'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                ),
              ),
            ),
          const SliverToBoxAdapter(
            child: SectionHeader(title: 'Aktivitas'),
          ),
          activities.when(
            loading: () => const SliverToBoxAdapter(child: LoadingRow()),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Gagal memuat aktivitas: $e'),
              ),
            ),
            data: (list) {
              if (list.isEmpty) {
                return const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.directions_run,
                    title: 'Belum ada aktivitas',
                    message: 'Atlet ini belum mencatat aktivitas apa pun.',
                  ),
                );
              }
              return SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, i) => ActivityCard(
                  item: FeedItem(
                    activity: list[i],
                    owner: profile,
                  ),
                  showOwner: false,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _header(Profile profile, bool isMe) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF232B34), Color(0xFF161B22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              UserAvatar(profile: profile, size: 66),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${profile.username}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined,
                            size: 12, color: AppColors.muted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            profile.locationLabel,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isMe)
                const BadgeChip(label: 'KAMU', color: AppColors.brand),
            ],
          ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                profile.bio,
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: (profile.totalDistanceMeters / 1000)
                      .toStringAsFixed(0),
                  unit: 'km',
                  label: 'Total jarak',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: profile.activityCount.toString(),
                  label: 'Aktivitas',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: profile.followerCount.toString(),
                  label: 'Pengikut',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: profile.followingCount.toString(),
                  label: 'Mengikuti',
                  compact: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _bodyStats(profile),
        ],
      ),
    );
  }

  Widget _bodyStats(Profile profile) {
    final bmi = profile.heightCm > 0
        ? profile.weightKg / ((profile.heightCm / 100) * (profile.heightCm / 100))
        : 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _miniStat('Berat', '${profile.weightKg.toStringAsFixed(0)} kg'),
          ),
          Expanded(
            child: _miniStat('Tinggi', '${profile.heightCm.toStringAsFixed(0)} cm'),
          ),
          Expanded(
            child: _miniStat(
              'BMI',
              bmi > 0 ? bmi.toStringAsFixed(1) : '—',
            ),
          ),
          Expanded(
            child: _miniStat(
              'Elevasi',
              '${profile.totalElevationMeters.round()} m',
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    );
  }
}
