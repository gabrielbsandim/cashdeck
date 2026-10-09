import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The radius 24 card every insight sits in: a title, an optional action
/// on the right, and the content below.
class CdInsightCard extends StatelessWidget {
  const new({
    required this.child,
    this.title,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.trailing,
    super.key,
  });

  final String? title;
  final Widget child;

  /// A text action on the title row, such as "Ver todas".
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Opens the screen behind the card; shows a chevron on the title row.
  final VoidCallback? onTap;

  /// Anything else on the title row, such as a toggle.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final charts = context.charts;
    final title = this.title;
    final actionLabel = this.actionLabel;
    final trailing = this.trailing;
    return Material(
      color: charts.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        side: BorderSide(color: charts.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: AppTextStyles.titleSm.copyWith(
                              color: palette.onSurface,
                            ),
                          ),
                        ),
                      ),
                      ?trailing,
                      if (actionLabel != null)
                        TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(48, 36),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            foregroundColor: palette.primary,
                          ),
                          child: Text(actionLabel),
                        ),
                      if (onTap != null && actionLabel == null)
                        Icon(
                          Symbols.chevron_right_rounded,
                          color: palette.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
