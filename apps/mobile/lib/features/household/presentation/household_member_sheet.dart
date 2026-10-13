import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/tax_id_input_formatter.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:cashdeck/features/household/presentation/household_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Adds a member; the toast tells the outcome once the sheet closes.
Future<void> showHouseholdMemberSheet(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final added = await showCdBottomSheet<bool>(
    context,
    title: l10n.householdAdd,
    builder: (_) => const HouseholdMemberSheet(),
  );
  if (added != true || !context.mounted) return;
  await showOutcomeToast(context, null, success: l10n.householdMemberAdded);
}

String memberProblemLabel(AppLocalizations l10n, MemberProblem problem) =>
    switch (problem) {
      MemberProblem.nameMissing => l10n.householdNameMissing,
      MemberProblem.nameTooLong => l10n.householdNameTooLong(
        Household.maxNameLength,
      ),
      MemberProblem.cpfInvalid => l10n.householdCpfInvalid,
      MemberProblem.cpfTaken => l10n.householdCpfTaken,
      MemberProblem.full => l10n.householdFull(Household.maxMembers),
    };

class HouseholdMemberSheet extends ConsumerStatefulWidget {
  const new({super.key});

  static const nameKey = Key('household-member-name');
  static const cpfKey = Key('household-member-cpf');
  static const saveKey = Key('household-member-save');
  static const errorKey = Key('household-member-error');

  @override
  ConsumerState<HouseholdMemberSheet> createState() =>
      _HouseholdMemberSheetState();
}

class _HouseholdMemberSheetState extends ConsumerState<HouseholdMemberSheet> {
  final _name = TextEditingController();
  final _cpf = TextEditingController();
  MemberProblem? _problem;
  String? _serverError;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _cpf.dispose();
    super.dispose();
  }

  String? _errorFor(AppLocalizations l10n, Set<MemberProblem> shown) {
    final problem = _problem;
    if (problem == null || !shown.contains(problem)) return null;
    return memberProblemLabel(l10n, problem);
  }

  Future<void> _save() async {
    final household =
        ref.read(householdControllerProvider).value ?? const Household([]);
    final problem = household.problemOf(_name.text, _cpf.text);
    setState(() {
      _problem = problem;
      _serverError = null;
      _saving = problem == null;
    });
    if (problem != null) return;
    final navigator = Navigator.of(context);
    final l10n = AppLocalizations.of(context);
    final failure = await ref
        .read(householdControllerProvider.notifier)
        .add(_name.text, _cpf.text);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = failure.userMessage(l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final general = _serverError ?? _errorFor(l10n, {MemberProblem.full});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdTextField(
          key: HouseholdMemberSheet.nameKey,
          controller: _name,
          label: l10n.householdNameLabel,
          errorText: _errorFor(l10n, {
            MemberProblem.nameMissing,
            MemberProblem.nameTooLong,
          }),
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(Household.maxNameLength),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: HouseholdMemberSheet.cpfKey,
          controller: _cpf,
          label: l10n.householdCpfLabel,
          errorText: _errorFor(l10n, {
            MemberProblem.cpfInvalid,
            MemberProblem.cpfTaken,
          }),
          monospace: true,
          keyboardType: TextInputType.number,
          inputFormatters: [TaxIdInputFormatter(EntityKind.personal)],
        ),
        if (general != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            general,
            key: HouseholdMemberSheet.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: HouseholdMemberSheet.saveKey,
          expand: true,
          label: l10n.householdSave,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
