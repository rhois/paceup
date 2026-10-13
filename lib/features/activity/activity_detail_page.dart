import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/date_format.dart';
import '../../core/metrics.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/paceup_repository.dart';
import '../../providers.dart';
import '../../widgets/common.dart';
import '../../widgets/route_map.dart';
import '../home/widgets/activity_card.dart' show relativeTime;

/// Detail aktivitas: statistik lengkap, split, rute, kudos, komentar.
class ActivityDetailPage extends ConsumerStatefulWidget {
  const ActivityDetailPage({required this.activityId, super.key});

  final String activityId;

  @override
  ConsumerState<ActivityDetailPage> createState() => _ActivityDetailPageState();
}

class _ActivityDetailPageState extends ConsumerState<ActivityDetailPage> {
  final _comment = TextEditingController();
  bool _sending = false;
  bool _kudosed = false;
  int _kudosCount = 0;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _toggleKudos() async {
    final previous = _kudosed;
    setState(() {
      _kudosed = !_kudosed;
      _kudosCount += _kudosed ? 1 : -1;
    });
    try {
      final count = await ref
          .read(repositoryProvider)
          .toggleKudos(widget.activityId);
      if (mounted) setState(() => _kudosCount = count);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kudosed = previous;
        _kudosCount += previous ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e')),
      );
    }
  }

  Future<void> _sendComment() async {
    final body = _comment.text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).addComment(widget.activityId, body);
      _comment.clear();
      ref.invalidate(activityCommentsProvider(widget.activityId));
      ref.invalidate(activityDetailProvider(widget.activityId));
    } on AppFailure catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hapus aktivitas?'),
        content: const Text('Aktivitas ini akan dihapus permanen.'),
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
    await ref.read(repositoryProvider).deleteActivity(widget.activityId);
    ref.invalidate(myActivitiesProvider);
    ref.invalidate(feedProvider);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(activityDetailProvider(widget.activityId));

    return async.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const LoadingRow(),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: 'Gagal memuat aktivitas',
          message: '$e',
          actionLabel: 'Coba lagi',
          onAction: () =>
              ref.invalidate(activityDetailProvider(widget.activityId)),
        ),
      ),
      data: (activity) {
        if (activity == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.search_off,
              title: 'Aktivitas tidak ditemukan',
              message: 'Mungkin sudah dihapus atau tautannya salah.',
            ),
          );
        }
        _kudosCount = activity.kudosCount;
        return _content(activity);
      },
    );
  }

  Widget _content(Activity a) {
    final me = ref.watch(currentProfileProvider);
    final isMine = me?.id == a.userId;
    final metrics = MetricsEngine.compute(a.points, weightKg: me?.weightKg ?? 65);
    final comments = ref.watch(activityCommentsProvider(widget.activityId));

    return Scaffold(
      appBar: AppBar(
        title: Text(a.displayTitle),
        actions: [
          if (isMine)
            IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline, size: 21),
              onPressed: _delete,
            ),
          IconButton(
            tooltip: 'Bagikan',
            icon: const Icon(Icons.share_outlined, size: 21),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tautan aktivitas disalin.')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _header(a),
          _stats(a, metrics),
          if (a.mapPolyline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: RouteMap(
                polyline: a.mapPolyline,
                points: a.points
                    .map((p) => LatLng(p.lat, p.lon))
                    .toList(),
                height: 220,
              ),
            ),
          if (metrics.splits.isNotEmpty) _splits(metrics),
          if (metrics.avgCadenceSpm > 0 || a.avgHeartRate > 0)
            _physiology(a, metrics),
          _social(a),
          _commentSection(comments),
        ],
      ),
    );
  }

  Widget _header(Activity a) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.type.emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                a.type.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                a.visibility == 'only_me'
                    ? 'Hanya saya'
                    : a.visibility == 'followers'
                        ? 'Pengikut'
                        : 'Publik',
                style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppDate.full(a.startedAt),
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
          if (a.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              a.description,
              style: const TextStyle(fontSize: 13.5, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stats(Activity a, RunMetrics m) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: (a.distanceMeters / 1000)
                      .toStringAsFixed(2)
                      .replaceAll('.', ','),
                  unit: 'km',
                  label: 'Jarak',
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatPace(a.paceSecPerKm),
                  unit: '/km',
                  label: 'Pace',
                  accent: AppColors.brand,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatDuration(a.movingDuration),
                  label: 'Waktu',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  value: a.elevationGain.round().toString(),
                  unit: 'm',
                  label: 'Elevasi naik',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: a.maxSpeedKmh.toStringAsFixed(1),
                  unit: 'km/j',
                  label: 'Kecepatan maks',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: a.calories.toString(),
                  unit: 'kkal',
                  label: 'Kalori',
                  compact: true,
                ),
              ),
              Expanded(
                child: MetricTile(
                  value: formatDuration(a.elapsedDuration),
                  label: 'Total waktu',
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _splits(RunMetrics m) {
    final maxPace = m.splits
        .where((s) => !s.partial)
        .map((s) => s.paceSecPerKm)
        .fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed_outlined, size: 16, color: AppColors.brand),
              const SizedBox(width: 6),
              const Text(
                'Split',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (m.bestSplit != null)
                BadgeChip(
                  label: 'TERBAIK ${formatPace(m.bestSplit!.paceSecPerKm)}',
                  icon: Icons.bolt,
                  color: AppColors.success,
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final s in m.splits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${s.index}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: s.index == m.bestSplit?.index
                            ? AppColors.success
                            : AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxPace <= 0
                            ? 0
                            : (s.paceSecPerKm / maxPace).clamp(0.25, 1.0),
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(
                          s.index == m.bestSplit?.index
                              ? AppColors.success
                              : AppColors.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatPace(s.paceSecPerKm),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (m.splits.any((s) => s.partial))
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Angka tanpa tanda = 1 km penuh.',
                style: TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _physiology(Activity a, RunMetrics m) {
    final vo2 = MetricsEngine.vo2max(
      distanceMeters: a.distanceMeters,
      movingSeconds: a.movingSeconds.toDouble(),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.monitor_heart_outlined, size: 16, color: AppColors.info),
              SizedBox(width: 6),
              Text(
                'Fisiologis',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (a.avgHeartRate > 0) _row('Detak jantung rata-rata', '${a.avgHeartRate} bpm'),
          if (m.avgCadenceSpm > 0) _row('Kadens rata-rata', '${m.avgCadenceSpm} spm'),
          if (m.stoppedDuration.inSeconds > 0)
            _row('Waktu berhenti', formatDuration(m.stoppedDuration)),
          if (vo2 > 0) _row('Estimasi VO₂max', '${vo2.toStringAsFixed(1)} ml/kg/menit'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _social(Activity a) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _toggleKudos,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _kudosed ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 18,
                    color: _kudosed ? AppColors.brand : AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _kudosCount > 0 ? 'Kudos · $_kudosCount' : 'Kudos',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _kudosed ? AppColors.brand : AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentSection(AsyncValue<List<ActivityComment>> comments) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Komentar'),
        comments.when(
          loading: () => const LoadingRow(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Gagal memuat komentar: $e'),
          ),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Belum ada komentar. Jadi yang pertama!',
                    style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                )
              : Column(
                  children: [
                    for (final c in list)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            UserAvatar(
                              profile: c.author ??
                                  Profile(id: c.userId, username: 'runner'),
                              size: 32,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c.author?.name ?? 'Pelari',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        relativeTime(c.createdAt),
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    c.body,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _comment,
                  minLines: 1,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Tulis komentar…',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _sendComment,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
