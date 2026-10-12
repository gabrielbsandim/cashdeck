import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_ring.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The goals in one swipeable row on Início, or an invitation to set one.
/// Stays out of the way while loading or when the goals cannot load.
class HomeGoalsStrip extends ConsumerWidget {
  const new({super.key});

  static const seeAllKey = Key('home-goals-see-all');
  static const startKey = Key('home-goals-start');

  static Key cardKey(String id) => Key('home-goal-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsControllerProvider).value;
    if (goals == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdSectionHeader(
          title: l10n.goalsTitle,
          actionLabel: goals.isEmpty ? null : l10n.seeAllButton,
          actionKey: seeAllKey,
          onAction: () => context.push(AppRoutes.goals),
        ),
        const SizedBox(height: AppSpacing.md),
        if (goals.isEmpty)
          const _StartGoal()
        else
          SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: goals.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (_, index) => _GoalCard(goal: goals[index]),
            ),
          ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const new({required this.goal});

  final Goal goal;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 140,
      child: CdCard(
        key: HomeGoalsStrip.cardKey(goal.id),
        onTap: () => context.push(AppRoutes.goal(goal.id)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GoalRing(goal: goal, size: 52),
            const Spacer(),
            Text(
              goal.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelLg.copyWith(
                color: context.palette.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StartGoal extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    return CdCard(
      key: HomeGoalsStrip.startKey,
      onTap: () => context.push(AppRoutes.goals),
      child: Row(
        children: [
          Icon(Symbols.flag_rounded, color: palette.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              l10n.goalsStart,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
          Icon(Symbols.chevron_right_rounded, color: palette.onSurfaceVariant),
        ],
      ),
    );
  }
}
