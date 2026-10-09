import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The new name for [account], trimmed, or null when the sheet is dismissed.
Future<String?> askAccountName(
  BuildContext context,
  TransactionAccount account,
) => showCdBottomSheet<String>(
  context,
  title: AppLocalizations.of(context).accountRenameTitle,
  builder: (_) => AccountRenameSheet(current: account.name),
);

class AccountRenameSheet extends StatefulWidget {
  const new({required this.current, super.key});

  static const fieldKey = Key('account-rename-field');
  static const saveKey = Key('account-rename-save');

  /// The server's limit on an account name.
  static const maxLength = 80;

  final String current;

  @override
  State<AccountRenameSheet> createState() => _AccountRenameSheetState();
}

class _AccountRenameSheetState extends State<AccountRenameSheet> {
  late String _name = widget.current;

  VoidCallback? get _save {
    final name = _name.trim();
    if (name.isEmpty || name == widget.current) return null;
    return () => Navigator.of(context).pop(name);
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
          initialValue: widget.current,
          helperText: l10n.accountRenameHelper,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            LengthLimitingTextInputFormatter(AccountRenameSheet.maxLength),
          ],
          onChanged: (value) => setState(() => _name = value),
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
