import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A tile of the Início summary grid: a tinted icon and a title, the value,
/// an optional ring or bar, and a caption. Tapping opens its screen.
class CdWidgetTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.colors,
    required this.title,
    required this.value,
    required this.caption,
    this.visual,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final SeriesColors colors;
  final String title;
  final Widget value;
  final String caption;

  /// A ring beside the value or a bar under it.
  final Widget? visual;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final charts = context.charts;
    final visual = this.visual;
    return Material(
      color: charts.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: charts.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: colors.container,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 18, color: colors.foreground),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMd.copyWith(
                        fontSize: 13,
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (visual == null)
                value
              else
                Row(
                  children: [
                    visual,
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: value),
                  ],
                ),
              const SizedBox(height: AppSpacing.md),
              Text(
                caption,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 13,
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
