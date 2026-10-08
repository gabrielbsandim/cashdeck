import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

/// The shared layout of a full screen state: a tinted icon, a title, a line
/// of explanation and one action.
class CdStateView extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.colors,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final ToneColors colors;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final message = this.message;
    final action = this.action;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.background,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: colors.foreground),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMd.copyWith(color: palette.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
