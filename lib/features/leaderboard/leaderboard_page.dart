import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/metrics.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/paceup_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';

/// Leaderboard: kompetisi jarak/elevasi/pace per periode.
class LeaderboardPage extends ConsumerWidget {
  const LeaderboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(leaderboardQueryProvider);
    final entries = ref.watch(leaderboardProvider);
    final me = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Peringkat'),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh, size: 21),
            onPressed: () => ref.invalidate(leaderboardProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          _scopes(ref, query),
          _metrics(ref, query),
          const SizedBox(height: 6),
          Expanded(
            child: entries.when(
              loading: () => const LoadingRow(),
              error: (e, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Gagal memuat peringkat',
                message: '$e',
                actionLabel: 'Coba lagi',
                onAction: () => ref.invalidate(leaderboardProvider),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'Belum ada data peringkat',
                    message: 'Belum ada aktivitas pada periode ini. '
                        'Rekam lari dan ajak teman bergabung!',
                  );
                }
                final podium = list.take(3).toList();
                final rest = list.skip(3).toList();

                return RefreshIndicator(
                  color: AppColors.brand,
                  onRefresh: () async {
                    ref.invalidate(leaderboardProvider);
                    await ref.read(leaderboardProvider.future);
                  },
                  child: ListView(
                    children: [
                      if (podium.isNotEmpty)
                        _Podium(entries: podium, metric: query.metric),
                      for (final e in rest)
                        _Row(entry: e, metric: query.metric, isMe: e.profile.id == me?.id),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopes(WidgetRef ref, LeaderboardQuery query) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final scope in LeaderboardScope.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                selected: query.scope == scope,
                onSelected: (_) => ref
                    .read(leaderboardQueryProvider.notifier)
                    .state = LeaderboardQuery(scope: scope, metric: query.metric),
                label: Text(scope.label),
                showCheckmark: false,
                selectedColor: AppColors.brand.withValues(alpha: 0.2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metrics(WidgetRef ref, LeaderboardQuery query) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: SegmentedButton<LeaderboardMetric>(
        segments: [
          for (final metric in LeaderboardMetric.values)
            ButtonSegment(
              value: metric,
              label: Text(metric.label, style: const TextStyle(fontSize: 12)),
            ),
        ],
        selected: {query.metric},
        onSelectionChanged: (set) => ref
            .read(leaderboardQueryProvider.notifier)
            .state = LeaderboardQuery(scope: query.scope, metric: set.first),
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.brand.withValues(alpha: 0.18)
                : AppColors.surfaceAlt;
          }),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          side: WidgetStateProperty.all(
            const BorderSide(color: AppColors.outline),
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.entries, required this.metric});

  final List<LeaderboardEntry> entries;
  final LeaderboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final order = [1, 0, 2];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      padding: const EdgeInsets.fromLTRB(10, 20, 10, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF232B34), Color(0xFF161B22)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final i in order)
            if (i < entries.length)
              Expanded(
                child: _podiumItem(context, entries[i], i),
              )
            else
              const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  Widget _podiumItem(BuildContext context, LeaderboardEntry e, int index) {
    final colors = [
      AppColors.gold,
      const Color(0xFFC0C6CC),
      const Color(0xFFCD7F32),
    ];
    final color = colors[index];
    final isFirst = index == 0;

    return GestureDetector(
      onTap: () => _push(context, e.profile.username),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFirst)
            Icon(Icons.workspace_premium, color: color, size: 22),
          UserAvatar(profile: e.profile, size: isFirst ? 58 : 46),
          const SizedBox(height: 8),
          Text(
            e.profile.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 13 : 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _value(e, metric),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isFirst ? 15 : 13,
              fontWeight: FontWeight.w900,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: isFirst ? 46 : 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            alignment: Alignment.center,
            child: Text(
              '${e.rank}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, String username) =>
      context.push('/athlete/$username');

  String _value(LeaderboardEntry e, LeaderboardMetric metric) => switch (metric) {
        LeaderboardMetric.distance =>
          '${(e.totalDistanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
        LeaderboardMetric.elevation => '${e.totalElevationMeters.round()} m',
        LeaderboardMetric.pace => e.bestPaceSecPerKm > 0
            ? '${formatPace(e.bestPaceSecPerKm)}/km'
            : '—',
      };
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.metric, this.isMe = false});

  final LeaderboardEntry entry;
  final LeaderboardMetric metric;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: isMe
          ? BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.08),
              border: const Border(
                left: BorderSide(color: AppColors.brand, width: 3),
              ),
            )
          : null,
      child: ListTile(
        onTap: () => context.push('/athlete/${entry.profile.username}'),
        leading: SizedBox(
          width: 46,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${entry.rank}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.muted,
                  ),
                ),
              ),
              UserAvatar(profile: entry.profile, size: 34),
            ],
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entry.profile.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 6),
              const BadgeChip(label: 'KAMU', color: AppColors.brand),
            ],
          ],
        ),
        subtitle: Text(
          '${entry.activityCount} aktivitas · '
          '${entry.profile.locationLabel}',
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
        trailing: Text(
          switch (metric) {
            LeaderboardMetric.distance =>
              '${(entry.totalDistanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km',
            LeaderboardMetric.elevation => '${entry.totalElevationMeters.round()} m',
            LeaderboardMetric.pace => entry.bestPaceSecPerKm > 0
                ? '${formatPace(entry.bestPaceSecPerKm)}/km'
                : '—',
          },
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
