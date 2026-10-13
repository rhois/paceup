import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/date_format.dart';
import '../../../core/metrics.dart';
import '../../../core/theme.dart';
import '../../../data/models/models.dart';
import '../../../providers.dart';
import '../../../widgets/common.dart';
import '../../../widgets/route_map.dart';

/// Kartu satu aktivitas di feed: peta rute, metrik, kudos, komentar.
class ActivityCard extends ConsumerStatefulWidget {
  const ActivityCard({required this.item, this.showOwner = true, super.key});

  final FeedItem item;
  final bool showOwner;

  @override
  ConsumerState<ActivityCard> createState() => _ActivityCardState();
}

class _ActivityCardState extends ConsumerState<ActivityCard> {
  late bool _kudosed;
  late int _kudosCount;
  bool _busyKudos = false;

  @override
  void initState() {
    super.initState();
    _kudosed = widget.item.hasKudosed;
    _kudosCount = widget.item.activity.kudosCount;
  }

  @override
  void didUpdateWidget(covariant ActivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.activity.id != widget.item.activity.id) {
      _kudosed = widget.item.hasKudosed;
      _kudosCount = widget.item.activity.kudosCount;
    }
  }

  Future<void> _toggleKudos() async {
    if (_busyKudos) return;
    setState(() {
      _busyKudos = true;
      // Optimistic update supaya terasa instan.
      _kudosed = !_kudosed;
      _kudosCount += _kudosed ? 1 : -1;
    });
    try {
      final count = await ref
          .read(repositoryProvider)
          .toggleKudos(widget.item.activity.id);
      if (mounted) setState(() => _kudosCount = count);
    } catch (e) {
      if (mounted) {
        setState(() {
          _kudosed = !_kudosed;
          _kudosCount += _kudosed ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memberi kudos: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busyKudos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activity = widget.item.activity;
    final owner = widget.item.owner;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/activity/${activity.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showOwner) _header(owner, activity),
            _metrics(activity),
            if (activity.mapPolyline.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: RouteMap(
                  polyline: activity.mapPolyline,
                  height: 150,
                ),
              ),
            _footer(activity),
          ],
        ),
      ),
    );
  }

  Widget _header(Profile owner, Activity activity) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.push('/athlete/${owner.username}'),
            child: UserAvatar(profile: owner, size: 40),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        owner.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '@${owner.username}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _relativeTime(activity.startedAt),
                  style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          Text(activity.type.emoji, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }

  Widget _metrics(Activity a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a.displayTitle,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          if (a.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              a.description,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.muted,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: a.distanceKm.toStringAsFixed(2).replaceAll('.', ','),
                  unit: 'km',
                  label: 'Jarak',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatPace(a.paceSecPerKm),
                  unit: '/km',
                  label: 'Pace',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatDuration(a.movingDuration),
                  label: 'Waktu',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: a.elevationGain.round().toString(),
                  unit: 'm',
                  label: 'Elevasi',
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer(Activity a) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        children: [
          _action(
            icon: _kudosed ? Icons.thumb_up : Icons.thumb_up_outlined,
            label: _kudosCount > 0 ? 'Kudos · $_kudosCount' : 'Kudos',
            color: _kudosed ? AppColors.brand : AppColors.muted,
            onTap: _toggleKudos,
          ),
          _action(
            icon: Icons.mode_comment_outlined,
            label: a.commentCount > 0 ? 'Komentar · ${a.commentCount}' : 'Komentar',
            onTap: () => context.push('/activity/${a.id}'),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined, size: 18),
            color: AppColors.muted,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Bagikan " ${a.displayTitle} " — '
                    '${a.distanceKm.toStringAsFixed(2)} km, '
                    'pace ${formatPace(a.paceSecPerKm)}/km',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = AppColors.muted,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String relativeTime(DateTime time) => _relativeTime(time);

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'baru saja';
  if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
  if (diff.inHours < 24) return '${diff.inHours} jam lalu';
  if (diff.inDays < 7) return '${diff.inDays} hari lalu';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} minggu lalu';
  return AppDate.short(time);
}
