import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Min 56 high. [chevron] for navigation, [trailing] for a switch or a value,
/// [danger] for a destructive action.
class CdListRow extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.titleMaxLines,
    this.icon,
    this.leading,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.danger = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.screenGutter,
      vertical: AppSpacing.sm,
    ),
    super.key,
  });

  final String title;
  final String? subtitle;
  final int? titleMaxLines;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = danger ? context.money.failed : palette.onSurface;
    final icon = this.icon;
    final leading = this.leading;
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.listRowMinHeight,
        ),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              if (leading != null) ...[
                leading,
                const SizedBox(width: AppSpacing.md),
              ] else if (icon != null) ...[
                Icon(
                  icon,
                  color: danger ? ink : palette.onSurfaceVariant,
                  size: 24,
                ),
                const SizedBox(width: AppSpacing.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: titleMaxLines,
                      overflow: titleMaxLines == null
                          ? null
                          : TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLg.copyWith(
                        color: ink,
                        fontWeight: danger ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: AppSpacing.sm),
                trailing,
              ],
              if (chevron) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Symbols.chevron_right_rounded,
                  color: palette.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
