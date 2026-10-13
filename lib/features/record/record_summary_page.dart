import 'package:flutter/material.dart' hide Split;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/date_format.dart';
import '../../core/metrics.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../data/repositories/paceup_repository.dart';
import '../../providers.dart';
import '../../services/sync_service.dart';
import '../../widgets/common.dart';
import '../../widgets/route_map.dart';

/// Ringkasan setelah aktivitas selesai: metrik lengkap, split, simpan.
class RecordSummaryPage extends ConsumerStatefulWidget {
  const RecordSummaryPage({this.activity, super.key});

  /// Aktivitas hasil rekaman. Bila null (mis. deep link), tampilkan pesan.
  final Activity? activity;

  @override
  ConsumerState<RecordSummaryPage> createState() => _RecordSummaryPageState();
}

class _RecordSummaryPageState extends ConsumerState<RecordSummaryPage> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _visibility = 'followers';
  bool _saving = false;

  late final RunMetrics _metrics;

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    _title.text = a?.displayTitle ?? '';
    _description.text = a?.description ?? '';
    _metrics = a == null
        ? MetricsEngine.compute(const [])
        : MetricsEngine.compute(
            a.points,
            weightKg: ref.read(currentProfileProvider)?.weightKg ?? 65,
          );
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final activity = widget.activity;
    if (activity == null) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    final me = ref.read(currentProfileProvider);

    final toSave = Activity(
      id: activity.id,
      userId: me?.id ?? 'me',
      type: activity.type,
      startedAt: activity.startedAt,
      title: _title.text.trim(),
      description: _description.text.trim(),
      distanceMeters: activity.distanceMeters,
      movingSeconds: activity.movingSeconds,
      elapsedSeconds: activity.elapsedSeconds,
      elevationGain: activity.elevationGain,
      elevationLoss: activity.elevationLoss,
      avgPaceSecPerKm: activity.avgPaceSecPerKm,
      maxSpeedKmh: activity.maxSpeedKmh,
      avgHeartRate: activity.avgHeartRate,
      avgCadenceSpm: activity.avgCadenceSpm,
      calories: activity.calories,
      visibility: _visibility,
      mapPolyline: activity.mapPolyline,
      points: activity.points,
      createdAt: DateTime.now(),
    );

    try {
      await repo.saveActivity(toSave, points: toSave.points);
      _invalidate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktivitas tersimpan! 💪')),
      );
      context.go('/');
    } on AppFailure catch (e) {
      // Simpan ke antrean offline bila gagal unggah.
      final sync = SyncService(repo, ref.read(localStoreProvider));
      await sync.enqueue(toSave);
      _invalidate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${e.message} Disimpan untuk diunggah nanti.')),
      );
      context.go('/');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e')),
        );
      }
    }
  }

  void _invalidate() {
    ref.invalidate(myActivitiesProvider);
    ref.invalidate(feedProvider);
    ref.invalidate(weeklySummaryProvider);
    ref.invalidate(personalRecordsProvider);
    ref.invalidate(dailyVolumeProvider);
    ref.invalidate(leaderboardProvider);
  }

  void _discard() {
    ref.read(recordingControllerProvider).discard();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.activity;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ringkasan')),
        body: const EmptyState(
          icon: Icons.help_outline,
          title: 'Tidak ada data aktivitas',
          message: 'Buka halaman Rekam untuk memulai aktivitas baru.',
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Ringkasan aktivitas'),
          actions: [
            TextButton(
              onPressed: _saving ? null : _discard,
              style: TextButton.styleFrom(foregroundColor: AppColors.muted),
              child: const Text('Buang'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _heroCard(a),
              const SizedBox(height: 14),
              if (_metrics.avgCadenceSpm > 0) ...[
                _insightCard(a),
                const SizedBox(height: 14),
              ],
              _splitCard(),
              const SizedBox(height: 14),
              if (a.mapPolyline.isNotEmpty) ...[
                const _Label('Rute'),
                RouteMap(polyline: a.mapPolyline, height: 200),
                const SizedBox(height: 18),
              ],
              const _Label('Judul aktivitas'),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Mis. Morning run 10K',
                ),
              ),
              const SizedBox(height: 14),
              const _Label('Catatan (opsional)'),
              TextField(
                controller: _description,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Bagaimana rasanya lari hari ini?',
                ),
              ),
              const SizedBox(height: 14),
              const _Label('Siapa yang bisa melihat'),
              _visibilitySelector(),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
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
                label: Text(_saving ? 'Menyimpan…' : 'Simpan aktivitas'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _saving ? null : _discard,
                child: const Text('Buang aktivitas ini'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard(Activity a) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.type.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                a.type.label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              const BadgeChip(
                label: 'BARU',
                icon: Icons.auto_awesome,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppDate.full(a.startedAt),
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Text(
                  (a.distanceMeters / 1000)
                      .toStringAsFixed(2)
                      .replaceAll('.', ','),
                  style: const TextStyle(
                    fontSize: 58,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    letterSpacing: -2.5,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'KILOMETER',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: AppColors.outline.withValues(alpha: 0.7),
                ),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MetricTile(
                        value: formatPace(a.paceSecPerKm),
                        unit: '/km',
                        label: 'Pace rata-rata',
                        compact: true,
                      ),
                    ),
                    Expanded(
                      child: MetricTile(
                        value: formatDuration(a.movingDuration),
                        label: 'Waktu bergerak',
                        compact: true,
                      ),
                    ),
                    Expanded(
                      child: MetricTile(
                        value: a.elevationGain.round().toString(),
                        unit: 'm',
                        label: 'Elevasi naik',
                        compact: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _insightCard(Activity a) {
    final m = _metrics;
    final vo2 = MetricsEngine.vo2max(
      distanceMeters: a.distanceMeters,
      movingSeconds: a.movingSeconds.toDouble(),
    );
    return Container(
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
              Icon(Icons.insights_outlined, size: 16, color: AppColors.info),
              SizedBox(width: 6),
              Text(
                'Analisis',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row('Kecepatan rata-rata', '${a.avgSpeedKmh.toStringAsFixed(1)} km/jam'),
          _row('Kecepatan maksimal', '${a.maxSpeedKmh.toStringAsFixed(1)} km/jam'),
          _row('Kadens', '${a.avgCadenceSpm} spm'),
          _row('Kalori (estimasi)', '${a.calories} kkal'),
          _row('Waktu total', formatDuration(a.elapsedDuration)),
          if (m.stoppedDuration.inSeconds > 0)
            _row('Waktu berhenti', formatDuration(m.stoppedDuration)),
          if (vo2 > 0)
            _row('Estimasi VO₂max', '${vo2.toStringAsFixed(1)} ml/kg/menit'),
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
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitCard() {
    final splits = _metrics.splits;
    if (splits.isEmpty) return const SizedBox.shrink();

    final best = _metrics.bestSplit;
    return Container(
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
                'Split per kilometer',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              if (best != null)
                BadgeChip(
                  label: 'TERBAIK ${formatPace(best.paceSecPerKm)}',
                  icon: Icons.bolt,
                  color: AppColors.success,
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final s in splits) _splitRow(s, best),
        ],
      ),
    );
  }

  Widget _splitRow(Split s, Split? best) {
    final isBest = best != null && s.index == best.index;
    final maxPace = _metrics.splits
        .where((x) => !x.partial)
        .map((x) => x.paceSecPerKm)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final ratio = maxPace <= 0 ? 0.0 : (s.paceSecPerKm / maxPace).clamp(0.25, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              s.partial ? '${s.index}*' : '${s.index}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isBest ? AppColors.success : AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(
                  isBest ? AppColors.success : AppColors.brand,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
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
          SizedBox(
            width: 42,
            child: Text(
              '+${s.elevationGain.round()}m',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _visibilitySelector() {
    const options = [
      ('everyone', 'Semua orang', Icons.public),
      ('followers', 'Pengikut', Icons.group_outlined),
      ('only_me', 'Hanya saya', Icons.lock_outline),
    ];
    return RadioGroup<String>(
      groupValue: _visibility,
      onChanged: (v) => setState(() => _visibility = v ?? 'followers'),
      child: Column(
        children: [
          for (final (value, label, icon) in options)
            RadioListTile<String>(
              value: value,
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.brand,
              secondary: Icon(icon, size: 18, color: AppColors.muted),
              title: Text(label, style: const TextStyle(fontSize: 13.5)),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          color: AppColors.muted,
        ),
      ),
    );
  }
}
