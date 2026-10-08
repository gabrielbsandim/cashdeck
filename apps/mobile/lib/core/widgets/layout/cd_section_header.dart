import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A section title with an optional line below and a text action on the right.
class CdSectionHeader extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.small = false,
    super.key,
  });

  final String title;
  final Widget? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// A labelLg caption over a group of rows instead of a titleMd heading.
  final bool small;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final actionLabel = this.actionLabel;
    final subtitle = this.subtitle;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: small
                      ? AppTextStyles.labelLg.copyWith(
                          color: palette.onSurfaceVariant,
                        )
                      : AppTextStyles.titleMd.copyWith(
                          color: palette.onSurface,
                        ),
                ),
              ),
              if (subtitle != null)
                DefaultTextStyle.merge(
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                  child: subtitle,
                ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            key: actionKey,
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(
                AppSpacing.minTouchTarget,
                AppSpacing.minTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              foregroundColor: palette.primary,
              textStyle: AppTextStyles.labelLg,
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }
}
