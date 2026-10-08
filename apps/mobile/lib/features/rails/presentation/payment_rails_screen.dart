import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/presentation/rail_labels.dart';
import 'package:cashdeck/features/rails/presentation/rails_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Which rail serves each step of the ladder, per entity.
class PaymentRailsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const authorizeKey = Key('rails-authorize');
  static const continueKey = Key('rails-continue');

  static Key ownerKey(EntityKind owner) => Key('rails-owner-${owner.name}');
  static Key railKey(String id) => Key('rail-$id');

  @override
  ConsumerState<PaymentRailsScreen> createState() => _PaymentRailsScreenState();
}

class _PaymentRailsScreenState extends ConsumerState<PaymentRailsScreen> {
  late EntityKind _owner = switch (ref.read(entityScopeProvider)) {
    EntityScope.company => EntityKind.company,
    EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final rails = ref.watch(railsControllerProvider(_owner));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.onboardingStep(5, 6))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          Text(
            l10n.railsTitle,
            style: AppTextStyles.headlineMd.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          CdSegmented<EntityKind>(
            segments: [
              CdSegment(
                EntityKind.personal,
                l10n.entityPersonal,
                key: PaymentRailsScreen.ownerKey(EntityKind.personal),
              ),
              CdSegment(
                EntityKind.company,
                l10n.entityCompany,
                key: PaymentRailsScreen.ownerKey(EntityKind.company),
              ),
            ],
            selected: _owner,
            onChanged: (owner) => setState(() => _owner = owner),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (rails) {
            AsyncData(:final value) => _RailList(owner: _owner, rails: value),
            AsyncError(:final error) => CdErrorState(
              failure: failureOf(error),
              onRetry: () => ref.invalidate(railsControllerProvider(_owner)),
            ),
            _ => const SizedBox(height: 240, child: CdSkeleton()),
          },
          const SizedBox(height: AppSpacing.xl),
          CdButton.filled(
            key: PaymentRailsScreen.continueKey,
            expand: true,
            label: l10n.continueButton,
            onPressed: () => context.pop(),
          ),
        ],
      ),
    );
  }
}

class _RailList extends ConsumerWidget {
  const new({required this.owner, required this.rails});

  final EntityKind owner;
  final List<PaymentRail> rails;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final pending = rails
        .where((rail) => rail.status == RailStatus.needsAuthorization)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final rail in rails) _RailRow(rail: rail),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.account_balance_rounded,
                size: 20,
                color: palette.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  owner == EntityKind.company
                      ? l10n.railsCompanyNote
                      : l10n.railsPersonalNote,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (pending != null) ...[
          const SizedBox(height: AppSpacing.md),
          CdInlineBanner(
            tone: MoneyTone.pending,
            icon: Symbols.key_rounded,
            message: l10n.railsAuthorizeBanner(pending.institution),
            actionLabel: l10n.railAuthorize,
            actionKey: PaymentRailsScreen.authorizeKey,
            onAction: () async {
              final failure = await ref
                  .read(railsControllerProvider(owner).notifier)
                  .authorize(pending.id);
              if (!context.mounted) return;
              await showOutcomeToast(
                context,
                failure,
                success: l10n.railAuthorizedToast(pending.institution),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _RailRow extends StatelessWidget {
  const new({required this.rail});

  final PaymentRail rail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final (tone, label, icon) = railStatusOf(l10n, rail.status);
    return InkWell(
      key: PaymentRailsScreen.railKey(rail.id),
      onTap: rail.configurable
          ? () => context.push(AppRoutes.rail(rail.id), extra: rail)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: palette.surfaceContainerHigh,
              child: Text(
                '${rail.step}',
                style: AppTextStyles.labelLg.copyWith(color: palette.onSurface),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    railName(l10n, rail.kind),
                    style: AppTextStyles.titleSm.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  Text(
                    railDetail(l10n, rail),
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: CdStatusBadge(tone: tone, label: label, icon: icon),
            ),
          ],
        ),
      ),
    );
  }
}
