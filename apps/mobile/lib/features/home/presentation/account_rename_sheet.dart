import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/features/transactions/transactions_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the sheet saves: the trimmed name and the holder, null when blank.
typedef AccountEdit = ({String name, String? holder});

/// The edited name and holder of [account], or null when dismissed.
Future<AccountEdit?> askAccountEdit(
  BuildContext context,
  TransactionAccount account,
) => showCdBottomSheet<AccountEdit>(
  context,
  title: AppLocalizations.of(context).accountEditTitle,
  builder: (_) => AccountRenameSheet(current: account),
);

/// Asks for a new name and holder, saves what changed and says how it went.
Future<void> renameAccount(
  BuildContext context,
  WidgetRef ref,
  TransactionAccount account,
) async {
  final l10n = AppLocalizations.of(context);
  final rename = ref.read(renameAccountProvider);
  final setHolder = ref.read(setAccountHolderProvider);
  final edit = await askAccountEdit(context, account);
  if (edit == null || !context.mounted) return;
  final renamed = edit.name == account.name
      ? null
      : await rename(account.id, edit.name);
  final held = renamed is Err || edit.holder == account.holder
      ? null
      : await setHolder(account.id, edit.holder);
  if (!context.mounted) return;
  ref
    ..invalidate(transactionAccountsProvider)
    ..invalidate(homeControllerProvider);
  await showOutcomeToast(context, switch ((renamed, held)) {
    (Err(:final failure), _) || (_, Err(:final failure)) => failure,
    _ => null,
  }, success: l10n.accountUpdated);
}

class AccountRenameSheet extends StatefulWidget {
  const new({required this.current, super.key});

  static const fieldKey = Key('account-rename-field');
  static const saveKey = Key('account-rename-save');

  static const holderFieldKey = Key('account-holder-field');

  /// The server's limits on an account name and its holder.
  static const maxLength = 80;
  static const holderMaxLength = 40;

  final TransactionAccount current;

  @override
  State<AccountRenameSheet> createState() => _AccountRenameSheetState();
}

class _AccountRenameSheetState extends State<AccountRenameSheet> {
  late String _name = widget.current.name;
  late String _holder = widget.current.holder ?? '';

  VoidCallback? get _save {
    final name = _name.trim();
    final trimmed = _holder.trim();
    final holder = trimmed.isEmpty ? null : trimmed;
    final current = widget.current;
    if (name.isEmpty) return null;
    if (name == current.name && holder == current.holder) return null;
    return () =>
        Navigator.of(context).pop<AccountEdit>((name: name, holder: holder));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdTextField(
          key: AccountRenameSheet.fieldKey,
          label: l10n.accountRenameLabel,
          initialValue: widget.current.name,
          helperText: l10n.accountRenameHelper,
          textInputAction: TextInputAction.next,
          inputFormatters: [
            LengthLimitingTextInputFormatter(AccountRenameSheet.maxLength),
          ],
          onChanged: (value) => setState(() => _name = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: AccountRenameSheet.holderFieldKey,
          label: l10n.accountHolderLabel,
          initialValue: widget.current.holder,
          helperText: l10n.accountHolderHelper,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            LengthLimitingTextInputFormatter(
              AccountRenameSheet.holderMaxLength,
            ),
          ],
          onChanged: (value) => setState(() => _holder = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: AccountRenameSheet.saveKey,
          expand: true,
          label: l10n.saveButton,
          onPressed: _save,
        ),
      ],
    );
  }
}
