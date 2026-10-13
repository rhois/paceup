import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/models/models.dart';

/// Angka besar + label kecil, dipakai di layar rekam & ringkasan.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.value,
    required this.label,
    this.unit,
    this.accent,
    this.compact = false,
    super.key,
  });

  final String value;
  final String label;
  final String? unit;
  final Color? accent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final valueStyle = TextStyle(
      fontSize: compact ? 22 : 34,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1,
      color: accent ?? Colors.white,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Nilai + satuan. Diberi FittedBox agar tidak meluber saat kolom
        // sempit (mis. 4 metrik dalam satu baris di layar ponsel kecil)
        // maupun saat pengguna memperbesar skala teks.
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: valueStyle),
              if (unit != null) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: EdgeInsets.only(bottom: compact ? 1 : 4),
                  child: Text(
                    unit!,
                    style: TextStyle(
                      fontSize: compact ? 11 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 9 : 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }
}

/// Kartu ringkas statistik dengan ikon.
class StatPill extends StatelessWidget {
  const StatPill({
    required this.icon,
    required this.text,
    this.color,
    super.key,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
      ],
    );
  }
}

/// Avatar bulat dengan fallback inisial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    required this.profile,
    this.size = 44,
    super.key,
  });

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceAlt,
        border: Border.all(color: AppColors.outline),
        image: profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(profile.avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: profile.avatarUrl == null || profile.avatarUrl!.isEmpty
          ? Text(
              profile.initials.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
                color: AppColors.brand,
              ),
            )
          : null,
    );
  }
}

/// Baris pemisah bertitik (untuk leaderboard).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(action!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

/// Empty state yang informatif.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.muted,
                height: 1.5,
              ),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 46),
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Grafik batang sederhana untuk volume latihan harian.
class MiniBarChart extends StatelessWidget {
  const MiniBarChart({
    required this.values,
    this.labels = const [],
    this.height = 70,
    this.barColor = AppColors.brand,
    this.highlightLast = true,
    super.key,
  });

  /// Nilai 0..1.
  final List<double> values;
  final List<String> labels;
  final double height;
  final Color barColor;
  final bool highlightLast;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutCubic,
                          height: (values[i].clamp(0, 1) * (height - 8)) + 3,
                          decoration: BoxDecoration(
                            color: values[i] <= 0
                                ? AppColors.outline
                                : (highlightLast && i == values.length - 1
                                    ? barColor
                                    : barColor.withValues(alpha: 0.55)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              for (final l in labels)
                Expanded(
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Lencana kecil (mis. "PR 5K").
class BadgeChip extends StatelessWidget {
  const BadgeChip({
    required this.label,
    this.icon,
    this.color = AppColors.gold,
    super.key,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris loading singkat.
class LoadingRow extends StatelessWidget {
  const LoadingRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}
