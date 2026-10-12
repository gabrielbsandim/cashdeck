import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/goals/domain/goal.dart';
import 'package:cashdeck/features/goals/presentation/goal_editor.dart';
import 'package:cashdeck/features/goals/presentation/goal_labels.dart';
import 'package:cashdeck/features/goals/presentation/goal_ring.dart';
import 'package:cashdeck/features/goals/presentation/goals_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Every active goal with its ring, status and what it still needs.
class GoalsScreen extends ConsumerWidget {
  const new({super.key});

  static const addKey = Key('goals-add');

  static Key tileKey(String id) => Key('goal-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final goals = ref.watch(goalsControllerProvider);
    void create() => showGoalEditor(
      context,
      save: ref.read(goalsControllerProvider.notifier).create,
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.goalsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: addKey,
        onPressed: create,
        icon: const Icon(Symbols.add_rounded),
        label: Text(l10n.goalNew),
      ),
      body: switch (goals) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.flag_rounded,
          title: l10n.goalsEmptyTitle,
          message: l10n.goalsEmptyMessage,
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            96,
          ),
          children: [
            for (final goal in value) ...[
              _GoalTile(key: tileKey(goal.id), goal: goal),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(goalsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _GoalTile extends ConsumerWidget {
  const new({required this.goal, super.key});

  final Goal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final required = goalRequiredLine(l10n, goal, hide: hide);
    return CdCard(
      onTap: () => context.push(AppRoutes.goal(goal.id)),
      child: Row(
        children: [
          GoalRing(goal: goal, size: 64),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.name,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  goalProgressLine(l10n, goal, hide: hide),
                  style: secondary,
                ),
                if (required != null) Text(required, style: secondary),
                const SizedBox(height: AppSpacing.xs),
                CdStatusBadge(
                  tone: goalStatusTone(goal.status),
                  label: goalStatusLabel(l10n, goal.status),
                ),
              ],
            ),
          ),
          Icon(Symbols.chevron_right_rounded, color: palette.onSurfaceVariant),
        ],
      ),
    );
  }
}
