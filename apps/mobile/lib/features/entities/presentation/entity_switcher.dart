import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_entity_badge.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Scopes the screen below it to Pessoal, Empresa or Consolidado.
class EntitySwitcher extends ConsumerWidget {
  const new({super.key});

  static Key segmentKey(EntityScope scope) => Key('entity-${scope.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scope = ref.watch(entityScopeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: CdSegmented<EntityScope>(
        segments: [
          for (final option in EntityScope.values)
            CdSegment(
              option,
              entityScopeLabel(l10n, option),
              key: segmentKey(option),
            ),
        ],
        selected: scope,
        onChanged: ref.read(entityScopeProvider.notifier).select,
      ),
    );
  }
}

/// The entity chip of an app bar: badge, name, and a sheet to change scope.
class EntityChip extends ConsumerWidget {
  const new({super.key});

  static const chipKey = Key('entity-chip');

  static Key optionKey(EntityScope scope) => Key('entity-option-${scope.name}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final scope = ref.watch(entityScopeProvider);
    return Semantics(
      button: true,
      label: l10n.entityChipSemantics(entityScopeLabel(l10n, scope)),
      excludeSemantics: true,
      child: InkWell(
        key: chipKey,
        borderRadius: BorderRadius.circular(20),
        onTap: () => showCdBottomSheet<void>(
          context,
          title: l10n.entitySheetTitle,
          builder: (_) => const _EntitySheet(),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSpacing.minTouchTarget,
          ),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
              decoration: BoxDecoration(
                color: palette.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: palette.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EntityScopeBadge(scope: scope),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    entityScopeLabel(l10n, scope),
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  Icon(
                    Symbols.expand_more_rounded,
                    size: 20,
                    color: palette.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EntitySheet extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final scope = ref.watch(entityScopeProvider);
    return RadioGroup<EntityScope>(
      groupValue: scope,
      onChanged: (value) {
        if (value == null) return;
        ref.read(entityScopeProvider.notifier).select(value);
        Navigator.of(context).pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in EntityScope.values)
            RadioListTile<EntityScope>(
              key: EntityChip.optionKey(option),
              value: option,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              secondary: EntityScopeBadge(scope: option),
              title: Text(
                entityScopeLabel(l10n, option),
                style: AppTextStyles.bodyLg.copyWith(
                  color: palette.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EntityScopeBadge extends StatelessWidget {
  const new({required this.scope, this.size = 32, super.key});

  final EntityScope scope;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (scope) {
      EntityScope.personal => CdEntityBadge(
        entity: EntityTone.personal,
        label: l10n.entityPersonalShort,
        size: size,
      ),
      EntityScope.company => CdEntityBadge(
        entity: EntityTone.company,
        label: l10n.entityCompanyShort,
        size: size,
      ),
      EntityScope.consolidated => CdEntityBadge(
        entity: EntityTone.consolidated,
        size: size,
      ),
    };
  }
}

/// The badge of a single owner, for rows that mix entities.
class EntityKindBadge extends StatelessWidget {
  const new({required this.kind, this.size = 32, super.key});

  final EntityKind kind;
  final double size;

  @override
  Widget build(BuildContext context) => EntityScopeBadge(
    scope: switch (kind) {
      EntityKind.personal => EntityScope.personal,
      EntityKind.company => EntityScope.company,
    },
    size: size,
  );
}

String entityScopeLabel(AppLocalizations l10n, EntityScope scope) =>
    switch (scope) {
      EntityScope.personal => l10n.entityPersonal,
      EntityScope.company => l10n.entityCompany,
      EntityScope.consolidated => l10n.entityConsolidated,
    };
