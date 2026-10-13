import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:cashdeck/features/household/presentation/household_controller.dart';
import 'package:cashdeck/features/household/presentation/household_member_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The family members whose Pix moves the household's own money.
class HouseholdScreen extends ConsumerWidget {
  const new({super.key});

  static const addKey = Key('household-add');

  static Key rowKey(String taxId) => Key('household-member-$taxId');

  static Key removeKey(String taxId) => Key('household-remove-$taxId');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final household = ref.watch(householdControllerProvider);
    final canAdd = switch (household) {
      AsyncData(:final value) => !value.isFull,
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.householdTitle)),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              key: addKey,
              onPressed: () => showHouseholdMemberSheet(context),
              icon: const Icon(Symbols.person_add_rounded),
              label: Text(l10n.householdAdd),
            )
          : null,
      body: switch (household) {
        AsyncData(:final value) when value.members.isEmpty => CdEmptyState(
          icon: Symbols.family_restroom_rounded,
          title: l10n.householdEmptyTitle,
          message: l10n.householdIntro,
        ),
        AsyncData(:final value) => _Members(household: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(householdControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Members extends ConsumerStatefulWidget {
  const new({required this.household});

  final Household household;

  @override
  ConsumerState<_Members> createState() => _MembersState();
}

class _MembersState extends ConsumerState<_Members> {
  var _busy = false;

  Future<void> _remove(HouseholdMember member) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    final failure = await ref
        .read(householdControllerProvider.notifier)
        .remove(member);
    if (!mounted) return;
    setState(() => _busy = false);
    await showOutcomeToast(
      context,
      failure,
      success: l10n.householdMemberRemoved(member.name),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final household = widget.household;
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.sm,
          ),
          child: Text(
            l10n.householdIntro,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        for (final member in household.members)
          CdListRow(
            key: HouseholdScreen.rowKey(member.taxId),
            icon: Symbols.person_rounded,
            title: member.name,
            subtitle: l10n.householdCpfLine(member.maskedTaxId),
            trailing: IconButton(
              key: HouseholdScreen.removeKey(member.taxId),
              tooltip: l10n.householdRemove(member.name),
              icon: const Icon(Symbols.person_remove_rounded),
              onPressed: _busy ? null : () => _remove(member),
            ),
          ),
        if (household.isFull)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Text(
              l10n.householdFull(Household.maxMembers),
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
