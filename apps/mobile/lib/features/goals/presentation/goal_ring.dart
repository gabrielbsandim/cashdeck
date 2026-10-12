import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/insights/cd_progress_ring.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_appearance.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The goal's progress as a ring in its colour, the percentage or a check in
/// the middle; a large ring also shows the goal's icon.
class GoalRing extends StatelessWidget {
  const new({required this.goal, this.size = 48, super.key});

  final Goal goal;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = goalRingColor(context, goal);
    final large = size >= 96;
    final percent = Text(
      '${goal.percent}%',
      style: (large ? AppTextStyles.titleLg : AppTextStyles.labelMd).copyWith(
        color: context.palette.onSurface,
      ),
    );
    return CdProgressRing(
      size: size,
      stroke: large ? 12 : 5,
      parts: [(goal.fraction, color)],
      semanticsLabel: l10n.goalRingSemantics(goal.name, goal.percent),
      center: switch ((goal.isDone, large)) {
        (true, _) => Icon(
          Symbols.check_rounded,
          color: color,
          size: size * 0.4,
        ),
        (false, true) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(goalIconOf(goal.icon), color: color, size: size * 0.18),
            percent,
          ],
        ),
        (false, false) => percent,
      },
    );
  }
}
