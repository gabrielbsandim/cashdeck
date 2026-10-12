import 'dart:async';

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A short, quiet celebration when a goal reaches its target: one haptic
/// tap and a badge that grows in.
Future<void> celebrateGoal(BuildContext context, String name) {
  CdHaptics.celebrate();
  return showDialog<void>(
    context: context,
    builder: (_) => GoalCelebration(name: name),
  );
}

class GoalCelebration extends StatelessWidget {
  const new({required this.name, super.key});

  static const closeKey = Key('goal-celebration-close');

  final String name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final paid = context.money.paid;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1),
              duration: AppMotion.of(context, AppMotion.containerTransform),
              curve: Curves.elasticOut,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                child: Opacity(opacity: scale.clamp(0, 1), child: child),
              ),
              child: CircleAvatar(
                radius: 40,
                backgroundColor: context.money.paidContainer,
                child: Icon(Symbols.celebration_rounded, size: 44, color: paid),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.goalReachedTitle,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.goalReachedMessage(name),
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            CdButton.filled(
              key: closeKey,
              expand: true,
              label: l10n.goalReachedClose,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
