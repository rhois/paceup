import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/metrics.dart';
import '../../../core/theme.dart';
import '../../../data/models/models.dart';
import '../../../providers.dart';
import '../../../widgets/common.dart';

/// Dasbor ringkasan minggu ini: jarak, waktu, elevasi, grafik harian.
class WeeklyDashboard extends ConsumerWidget {
  const WeeklyDashboard({this.profile, super.key});

  final Profile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(weeklySummaryProvider);

    return summary.maybeWhen(
      data: (s) => _content(context, s),
      orElse: () => _content(
        context,
        WeeklySummary(
          weekStart: DateTime.now(),
          distanceMeters: 0,
          movingSeconds: 0,
          elevationGain: 0,
          activityCount: 0,
          calories: 0,
          dailyDistances: List.filled(7, 0),
        ),
        loading: true,
      ),
    );
  }

  Widget _content(BuildContext context, WeeklySummary s, {bool loading = false}) {
    final range = _weekRange(s.weekStart);
    const dayLabels = ['S', 'S', 'R', 'K', 'J', 'S', 'M'];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1D242C), Color(0xFF161B22)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile == null
                          ? 'Ringkasan minggu ini'
                          : 'Halo, ${profile!.name.split(' ').first} 👋',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      range,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${s.activityCount} aktivitas',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: (s.distanceMeters / 1000).toStringAsFixed(1).replaceAll('.', ','),
                  unit: 'km',
                  label: 'Jarak',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatDuration(Duration(seconds: s.movingSeconds)),
                  label: 'Waktu',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: s.elevationGain.round().toString(),
                  unit: 'm',
                  label: 'Elevasi',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: s.calories.toString(),
                  unit: 'kkal',
                  label: 'Kalori',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          MiniBarChart(
            values: s.normalizedDaily,
            labels: dayLabels,
            height: 56,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.play_arrow_rounded,
                  label: 'Mulai lari',
                  primary: true,
                  onTap: () => context.go('/record'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickAction(
                  context,
                  icon: Icons.emoji_events_outlined,
                  label: 'Peringkat',
                  onTap: () => context.go('/leaderboard'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary ? AppColors.brand : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _weekRange(DateTime monday) {
    final end = monday.add(const Duration(days: 6));
    return '${AppDate.dayMonth(monday)} – ${AppDate.dayMonth(end)}';
  }
}
