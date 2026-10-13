import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/metrics.dart';
import '../../core/theme.dart';
import '../../data/models/models.dart';
import '../../providers.dart';
import '../../services/location_service.dart';
import '../../services/recording_controller.dart';
import '../../widgets/common.dart';
import '../../widgets/route_map.dart';

/// Layar perekaman aktivitas.
///
/// Alur: siapkan GPS -> Start -> (jeda/auto-pause) -> Selesai -> ringkasan.
class RecordPage extends ConsumerStatefulWidget {
  const RecordPage({super.key});

  @override
  ConsumerState<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends ConsumerState<RecordPage> {
  bool _preparing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Cari sinyal saat halaman dibuka supaya tombol Start langsung siap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
  }

  Future<void> _prepare() async {
    final controller = ref.read(recordingControllerProvider);
    if (controller.status.isActive) return;
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      await controller.prepare();
    } on LocationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal menyiapkan GPS: $e');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _start() async {
    final controller = ref.read(recordingControllerProvider);
    setState(() => _error = null);
    try {
      await controller.start();
    } on LocationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal memulai: $e');
    }
  }

  Future<void> _finish() async {
    final controller = ref.read(recordingControllerProvider);
    final confirmed = await _confirmFinish(controller);
    if (confirmed != true) return;
    final activity = await controller.stop();
    if (!mounted) return;
    context.push('/record/summary', extra: activity);
  }

  Future<bool?> _confirmFinish(RecordingController controller) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Selesaikan aktivitas?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: MetricTile(
                    value: (controller.distanceMeters / 1000)
                        .toStringAsFixed(2)
                        .replaceAll('.', ','),
                    unit: 'km',
                    label: 'Jarak',
                    compact: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: formatDuration(controller.movingDuration),
                    label: 'Waktu',
                    compact: true,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    value: formatPace(controller.avgPaceSecPerKm),
                    unit: '/km',
                    label: 'Pace',
                    compact: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Simpan aktivitas'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Lanjut lari'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Buang aktivitas?'),
        content: const Text(
          'Semua data yang sudah direkam akan hilang dan tidak bisa '
          'dikembalikan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Buang'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(recordingControllerProvider).discard();
      if (mounted) await _prepare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(recordingControllerProvider);
    final status = controller.status;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rekam aktivitas'),
        actions: [
          if (status.isActive)
            IconButton(
              tooltip: 'Buang',
              icon: const Icon(Icons.delete_outline, size: 21),
              onPressed: _discard,
            ),
        ],
      ),
      body: SafeArea(
        child: status == RecordingStatus.idle && !_preparing && _error != null
            ? _errorView()
            : Column(
                children: [
                  if (_error != null) _inlineError(),
                  if (status == RecordingStatus.idle)
                    _readyView(controller)
                  else
                    _activeView(controller),
                ],
              ),
      ),
    );
  }

  // ------------------------------------------------------------ view: error
  Widget _errorView() {
    return EmptyState(
      icon: Icons.location_off_outlined,
      title: 'GPS belum siap',
      message: _error,
      actionLabel: 'Coba lagi',
      onAction: _prepare,
    );
  }

  Widget _inlineError() {
    return Container(
      width: double.infinity,
      color: AppColors.danger.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ view: ready
  Widget _readyView(RecordingController controller) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline),
              ),
              child: _preparing
                  ? const SizedBox(
                      width: 54,
                      height: 54,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : Icon(
                      Icons.gps_fixed,
                      size: 54,
                      color: controller.accuracy > 0
                          ? AppColors.success
                          : AppColors.muted,
                    ),
            ),
            const SizedBox(height: 22),
            Text(
              _preparing ? 'Mencari sinyal GPS…' : 'GPS siap',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              controller.accuracy > 0
                  ? 'Akurasi ±${controller.accuracy.toStringAsFixed(0)} m — '
                      'semakin kecil semakin baik.'
                  : 'Berdiri di area terbuka untuk sinyal terbaik.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            _typeSelector(controller),
            const Spacer(),
            FilledButton.icon(
              onPressed: _preparing ? null : _start,
              icon: const Icon(Icons.play_arrow_rounded, size: 26),
              label: const Text('MULAI LARI'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(62),
                textStyle: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 14),
            const _TipsCard(),
          ],
        ),
      ),
    );
  }

  Widget _typeSelector(RecordingController controller) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final type in const [
          ActivityType.run,
          ActivityType.trailRun,
          ActivityType.walk,
          ActivityType.ride,
        ])
          ChoiceChip(
            selected: controller.type == type,
            onSelected: (_) => controller.setType(type),
            avatar: Text(type.emoji, style: const TextStyle(fontSize: 14)),
            label: Text(type.label),
            showCheckmark: false,
            selectedColor: AppColors.brand.withValues(alpha: 0.2),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- view: active
  Widget _activeView(RecordingController controller) {
    final paused = controller.status == RecordingStatus.paused;
    final autoPaused = controller.isAutoPaused;

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                children: [
                  _statusBanner(controller, paused, autoPaused),
                  const SizedBox(height: 16),
                  _bigDistance(controller),
                  const SizedBox(height: 22),
                  _paceGrid(controller),
                  const SizedBox(height: 18),
                  _liveMap(controller),
                  const SizedBox(height: 14),
                  _splitsPreview(controller),
                  const SizedBox(height: 14),
                  _gpsQuality(controller),
                ],
              ),
            ),
          ),
          _controls(controller, paused),
        ],
      ),
    );
  }

  Widget _statusBanner(
    RecordingController controller,
    bool paused,
    bool autoPaused,
  ) {
    final color = paused
        ? AppColors.gold
        : autoPaused
            ? AppColors.info
            : AppColors.danger;
    final label = paused
        ? 'DIJEDA'
        : autoPaused
            ? 'AUTO-PAUSE'
            : 'MEREKAM';

    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: color,
          ),
        ),
        const Spacer(),
        Text(
          '${controller.type.emoji} ${controller.type.label}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _bigDistance(RecordingController controller) {
    return Column(
      children: [
        Text(
          (controller.distanceMeters / 1000).toStringAsFixed(2).replaceAll('.', ','),
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.w900,
            height: 1,
            letterSpacing: -3,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'KILOMETER',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 3,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _paceGrid(RecordingController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: MetricTile(
              value: formatDuration(controller.movingDuration),
              label: 'Waktu',
              compact: true,
            ),
          ),
          Expanded(
            child: MetricTile(
              value: formatPace(controller.currentPaceSecPerKm),
              unit: '/km',
              label: 'Pace saat ini',
              compact: true,
              accent: AppColors.brand,
            ),
          ),
          Expanded(
            child: MetricTile(
              value: formatPace(controller.avgPaceSecPerKm),
              unit: '/km',
              label: 'Pace rata-rata',
              compact: true,
            ),
          ),
          Expanded(
            child: MetricTile(
              value: controller.elevationGain.round().toString(),
              unit: 'm',
              label: 'Elevasi',
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveMap(RecordingController controller) {
    final points = controller.points
        .map((p) => LatLng(p.lat, p.lon))
        .toList();
    return RouteMap(
      polyline: '',
      points: points,
      height: 170,
      showMarkers: points.length > 1,
    );
  }

  Widget _splitsPreview(RecordingController controller) {
    final splits = controller.splits;
    if (splits.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline),
        ),
        child: const Row(
          children: [
            Icon(Icons.flag_outlined, size: 16, color: AppColors.muted),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Split per kilometer akan muncul setelah kamu menempuh 1 km.',
                style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4),
              ),
            ),
          ],
        ),
      );
    }

    final best = splits.map((s) => s.paceSecPerKm).reduce((a, b) => a < b ? a : b);
    final maxPace = splits.map((s) => s.paceSecPerKm).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'SPLIT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppColors.muted,
                ),
              ),
              const Spacer(),
              Text(
                'Terbaik ${formatPace(best)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final s in splits.reversed.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text(
                      '${s.index}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: maxPace <= 0
                            ? 0
                            : (maxPace - s.paceSecPerKm) / (maxPace - best + 0.001) * 0.85 + 0.15,
                        minHeight: 6,
                        backgroundColor: AppColors.surfaceAlt,
                        valueColor: AlwaysStoppedAnimation(
                          s.paceSecPerKm == best ? AppColors.success : AppColors.brand,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
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
        ],
      ),
    );
  }

  Widget _gpsQuality(RecordingController controller) {
    final quality = controller.accuracyQuality;
    final color = quality > 0.7
        ? AppColors.success
        : quality > 0.4
            ? AppColors.gold
            : AppColors.danger;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.satellite_alt_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sinyal GPS · akurasi ±${controller.accuracy.toStringAsFixed(0)} m',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: quality,
                    minHeight: 4,
                    backgroundColor: AppColors.surfaceAlt,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${controller.acceptedPoints} titik',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Widget _controls(RecordingController controller, bool paused) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              onPressed: () => controller.togglePause(),
              icon: Icon(
                paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 24,
              ),
              label: Text(paused ? 'LANJUT' : 'JEDA'),
              style: FilledButton.styleFrom(
                backgroundColor: paused ? AppColors.success : AppColors.surfaceAlt,
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.stop_rounded, size: 24),
              label: const Text('SELESAI'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipsCard extends StatelessWidget {
  const _TipsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.outline),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_outlined,
                  size: 15, color: AppColors.gold),
              SizedBox(width: 6),
              Text(
                'Tips akurasi',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '• Bawa ponsel di lengan atau saku yang tidak goyang.\n'
            '• Beri jeda 10–15 detik setelah menekan Mulai.\n'
            '• Auto-pause aktif: hitungan berhenti otomatis saat kamu berhenti.\n'
            '• Titik dengan akurasi buruk otomatis dibuang.',
            style: TextStyle(fontSize: 11.5, color: AppColors.muted, height: 1.6),
          ),
        ],
      ),
    );
  }
}
