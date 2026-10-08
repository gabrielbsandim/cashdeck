import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:flutter/material.dart';

/// A status message inside a screen, in the container of its tone, with an
/// optional action on the right.
class CdInlineBanner extends StatelessWidget {
  const new({
    required this.icon,
    required this.message,
    this.tone = MoneyTone.assisted,
    this.title,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    super.key,
  });

  final IconData icon;
  final String message;
  final MoneyTone tone;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.tone(tone);
    final title = this.title;
    final actionLabel = this.actionLabel;
    final ink = tone == MoneyTone.assisted
        ? palette.onPrimaryContainer
        : palette.onSurface;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.foreground, fill: 1, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: AppTextStyles.titleSm.copyWith(color: ink),
                    ),
                  Text(
                    message,
                    style: AppTextStyles.bodyMd.copyWith(
                      color: title == null ? ink : palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(
                key: actionKey,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: palette.primary,
                  textStyle: AppTextStyles.labelLg,
                  minimumSize: const Size(
                    AppSpacing.minTouchTarget,
                    AppSpacing.minTouchTarget,
                  ),
                ),
                child: Text(actionLabel),
              )
            else
              const SizedBox(width: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
