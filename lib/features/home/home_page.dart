import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../providers.dart';
import '../../router.dart';
import '../../widgets/common.dart';
import 'widgets/activity_card.dart';
import 'widgets/weekly_dashboard.dart';

/// Beranda = feed sosial + ringkasan mingguan.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final me = ref.watch(currentProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brand, AppColors.brandDark],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.directions_run, size: 17),
            ),
            const SizedBox(width: 9),
            const Text('PaceUp'),
            const SizedBox(width: 8),
            const DemoBadge(),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            icon: const Icon(Icons.refresh, size: 21),
            onPressed: () {
              ref.invalidate(feedProvider);
              ref.invalidate(weeklySummaryProvider);
              ref.invalidate(myActivitiesProvider);
            },
          ),
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined, size: 21),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.brand,
        onRefresh: () async {
          ref.invalidate(feedProvider);
          ref.invalidate(weeklySummaryProvider);
          await ref.read(feedProvider.future);
        },
        child: feed.when(
          loading: () => const LoadingRow(),
          error: (e, _) => ListView(
            children: [
              EmptyState(
                icon: Icons.cloud_off,
                title: 'Gagal memuat feed',
                message: '$e',
                actionLabel: 'Coba lagi',
                onAction: () => ref.invalidate(feedProvider),
              ),
            ],
          ),
          data: (items) => CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: WeeklyDashboard(profile: me),
              ),
              if (items.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.group_outlined,
                    title: 'Feed masih kosong',
                    message: 'Ikuti pelari lain supaya aktivitas mereka '
                        'muncul di sini. Atau mulai rekam lari pertamamu!',
                  ),
                )
              else ...[
                const SliverToBoxAdapter(
                  child: SectionHeader(title: 'Aktivitas terbaru'),
                ),
                SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) => ActivityCard(item: items[i]),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
