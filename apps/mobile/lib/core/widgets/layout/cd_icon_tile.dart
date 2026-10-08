import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The leading icon of a row: a circle on a transaction, a rounded square on
/// a bill. [tone] tints it, otherwise it sits on surfaceContainerHigh.
class CdIconTile extends StatelessWidget {
  const new(
    this.icon, {
    this.tone,
    this.circle = true,
    this.size = 40,
    this.filled = false,
    super.key,
  });

  final IconData icon;
  final ToneColors? tone;
  final bool circle;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tone = this.tone;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone?.background ?? palette.surfaceContainerHigh,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        icon,
        size: size * 0.55,
        fill: filled ? 1 : 0,
        color: tone?.foreground ?? palette.onSurfaceVariant,
      ),
    );
  }
}

/// A category as a tile with its name below, for pickers.
class CdCategoryIcon extends StatelessWidget {
  const new({required this.icon, required this.label, this.onTap, super.key});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CdIconTile(icon, circle: false, size: 48),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: AppTextStyles.labelMd.copyWith(
                color: palette.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A category as a chip; [suggested] marks a guess the user has not accepted.
class CdCategoryChip extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    this.suggested = false,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool suggested;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = suggested ? palette.primary : palette.onSurface;
    final chip = Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: suggested
            ? palette.primaryContainer.withValues(alpha: 0.4)
            : palette.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            suggested ? Symbols.auto_awesome_rounded : icon,
            size: 18,
            color: ink,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppTextStyles.labelLg.copyWith(color: ink)),
        ],
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: suggested
          ? CustomPaint(
              foregroundPainter: _DashedBorder(palette.primary),
              child: chip,
            )
          : chip,
    );
  }
}

class _DashedBorder extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(AppRadius.sm),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 7) {
        canvas.drawPath(metric.extractPath(start, start + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder oldDelegate) => oldDelegate.color != color;
}
