import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/metrics.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../home/widgets/activity_card.dart';

/// Halaman profil pribadi: statistik, PR, riwayat aktivitas.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentProfileProvider);
    if (me == null) {
      return const Scaffold(body: LoadingRow());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined, size: 21),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(child: _header(me)),
          SliverToBoxAdapter(
            child: TabBar(
              controller: _tabs,
              indicatorColor: AppColors.brand,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.muted,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: 'Aktivitas'),
                Tab(text: 'Rekor'),
                Tab(text: 'Statistik'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _activitiesTab(),
            _recordsTab(),
            _statsTab(),
          ],
        ),
      ),
    );
  }

  Widget _header(Profile me) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
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
              UserAvatar(profile: me, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${me.username}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      me.locationLabel,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ubah profil',
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: AppColors.muted,
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _totals(me),
        ],
      ),
    );
  }

  Widget _totals(Profile me) {
    return FutureBuilder<List<Activity>>(
      future: ref.read(myActivitiesProvider.future),
      builder: (context, snapshot) {
        final list = snapshot.data ?? const <Activity>[];
        final dist = list.fold<double>(0, (s, a) => s + a.distanceMeters);
        final secs = list.fold<int>(0, (s, a) => s + a.movingSeconds);
        final elev = list.fold<double>(0, (s, a) => s + a.elevationGain);
        final longest = list.isEmpty
            ? 0.0
            : list.map((a) => a.distanceMeters).reduce((a, b) => a > b ? a : b);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    value: (dist / 1000).toStringAsFixed(1).replaceAll('.', ','),
                    unit: 'km',
                    label: 'Total jarak',
                    compact: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: list.length.toString(),
                    label: 'Aktivitas',
                    compact: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: formatDuration(Duration(seconds: secs)),
                    label: 'Total waktu',
                    compact: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: elev.round().toString(),
                    unit: 'm',
                    label: 'Elevasi',
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.outline)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.straighten, size: 15, color: AppColors.muted),
                  const SizedBox(width: 6),
                  const Text(
                    'Terjauh',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  const Spacer(),
                  Text(
                    formatDistance(longest),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _activitiesTab() {
    final async = ref.watch(myActivitiesProvider);
    return async.when(
      loading: () => const LoadingRow(),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Gagal memuat aktivitas',
        message: '$e',
        actionLabel: 'Coba lagi',
        onAction: () => ref.invalidate(myActivitiesProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.directions_run,
            title: 'Belum ada aktivitas',
            message: 'Ayo catat lari pertamamu. Tekan tombol Rekam di bawah.',
            actionLabel: 'Mulai rekam',
            onAction: () => context.go('/record'),
          );
        }
        final me = ref.read(currentProfileProvider);
        return RefreshIndicator(
          color: AppColors.brand,
          onRefresh: () async {
            ref.invalidate(myActivitiesProvider);
            await ref.read(myActivitiesProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 12),
            itemCount: list.length,
            itemBuilder: (context, i) => ActivityCard(
              item: FeedItem(
                activity: list[i],
                owner: me ?? const Profile(id: 'me', username: 'kamu'),
              ),
              showOwner: false,
            ),
          ),
        );
      },
    );
  }

  Widget _recordsTab() {
    final async = ref.watch(personalRecordsProvider);
    return async.when(
      loading: () => const LoadingRow(),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: 'Gagal memuat rekor',
        message: '$e',
      ),
      data: (records) {
        if (records.isEmpty) {
          return const EmptyState(
            icon: Icons.emoji_events_outlined,
            title: 'Belum ada rekor',
            message: 'Rekor pribadi akan muncul setelah kamu menyelesaikan '
                'beberapa aktivitas lari.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: records.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final r = records[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.emoji_events,
                        size: 18, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      r.label,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        r.value,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (r.unit.isNotEmpty)
                        Text(
                          r.unit,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.muted,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _statsTab() {
    final volume = ref.watch(dailyVolumeProvider);
    final summary = ref.watch(weeklySummaryProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Volume 30 hari terakhir',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Jarak lari harian (km)',
                style: TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              volume.when(
                loading: () => const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Gagal memuat: $e'),
                data: (data) {
                  if (data.isEmpty) {
                    return const Text(
                      'Belum ada data.',
                      style: TextStyle(color: AppColors.muted),
                    );
                  }
                  final maxV = data
                      .map((d) => d.$2)
                      .fold<double>(0, (a, b) => a > b ? a : b);
                  final values = data
                      .map((d) => maxV <= 0 ? 0.0 : d.$2 / maxV)
                      .toList();

                  final total = data.fold<double>(0, (s, d) => s + d.$2);
                  final active = data.where((d) => d.$2 > 0).length;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MiniBarChart(
                        values: values,
                        height: 80,
                        highlightLast: false,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: MetricTile(
                              value: (total / 1000)
                                  .toStringAsFixed(1)
                                  .replaceAll('.', ','),
                              unit: 'km',
                              label: 'Total',
                              compact: true,
                            ),
                          ),
                          Expanded(
                            child: MetricTile(
                              value: active.toString(),
                              label: 'Hari aktif',
                              compact: true,
                            ),
                          ),
                          Expanded(
                            child: MetricTile(
                              value: active == 0
                                  ? '—'
                                  : (total / 1000 / active)
                                      .toStringAsFixed(1)
                                      .replaceAll('.', ','),
                              unit: 'km',
                              label: 'Rata-rata',
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Minggu ini',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              summary.when(
                loading: () => const SizedBox(
                  height: 60,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Gagal memuat: $e'),
                data: (s) => Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            value: (s.distanceMeters / 1000)
                                .toStringAsFixed(1)
                                .replaceAll('.', ','),
                            unit: 'km',
                            label: 'Jarak',
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            value: formatDuration(
                              Duration(seconds: s.movingSeconds),
                            ),
                            label: 'Waktu',
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            value: s.activityCount.toString(),
                            label: 'Aktivitas',
                            compact: true,
                          ),
                        ),
                        Expanded(
                          child: MetricTile(
                            value: s.calories.toString(),
                            unit: 'kkal',
                            label: 'Kalori',
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    MiniBarChart(
                      values: s.normalizedDaily,
                      labels: const ['S', 'S', 'R', 'K', 'J', 'S', 'M'],
                      height: 50,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
