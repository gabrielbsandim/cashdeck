import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/features/plan/domain/life_plan.dart';
import 'package:cashdeck/features/plan/presentation/plan_controller.dart';
import 'package:cashdeck/features/plan/presentation/plan_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The next purchase of the plan and when the milestones come, on Início.
/// Stays out of the way while loading or when the plan cannot load.
class HomePlanCard extends ConsumerWidget {
  const new({super.key});

  static const cardKey = Key('home-plan');

  static List<String> linesOf(AppLocalizations l10n, LifePlan plan) {
    final purchases = [
      for (final goal in plan.goals)
        if (goal.kind == PlanGoalKind.purchase && goal.month != null) goal,
    ]..sort((a, b) => a.month!.compareTo(b.month!));
    final next = purchases.firstOrNull;
    return [
      if (next != null && next.status == PlanStatus.now)
        l10n.planHomeNextNow(next.name)
      else if (next != null)
        l10n.planHomeNext(next.name, planMonth(l10n, next.month!)),
      for (final goal in plan.goals)
        if (goal.kind == PlanGoalKind.milestone)
          l10n.planHomeMilestone(goal.name, planWhenLine(l10n, goal)),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final plan = ref.watch(planControllerProvider).value;
    if (plan == null) return const SizedBox.shrink();
    final lines = linesOf(l10n, plan);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(title: l10n.planTitle),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          key: cardKey,
          onTap: () => context.push(AppRoutes.plan),
          child: Row(
            children: [
              Icon(Symbols.route_rounded, color: palette.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line
                        in lines.isEmpty ? [l10n.planHomeEmpty] : lines)
                      Text(
                        line,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                Symbols.chevron_right_rounded,
                color: palette.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
