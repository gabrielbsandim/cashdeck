import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_stepper.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

final class CdConfirmRow {
  const new(this.label, this.value);

  final String label;
  final String value;
}

/// Review, then confirm with the device check. Resolves true only after the
/// check passed; false when the user chose [secondaryLabel].
Future<bool?> showCdConfirmSheet(
  BuildContext context, {
  required String title,
  required List<CdConfirmRow> rows,
  required String confirmLabel,
  String? reason,
  String? secondaryLabel,
}) {
  return showCdBottomSheet<bool>(
    context,
    builder: (_) => CdConfirmSheet(
      title: title,
      rows: rows,
      confirmLabel: confirmLabel,
      reason: reason,
      secondaryLabel: secondaryLabel,
    ),
  );
}

class CdConfirmSheet extends ConsumerStatefulWidget {
  const new({
    required this.title,
    required this.rows,
    required this.confirmLabel,
    this.reason,
    this.secondaryLabel,
    super.key,
  });

  static const confirmKey = Key('cd-confirm');
  static const secondaryKey = Key('cd-confirm-secondary');

  final String title;
  final List<CdConfirmRow> rows;
  final String confirmLabel;

  /// Why the app asks, such as a cap or a new payee.
  final String? reason;

  /// Cancelar by default; "Pagar eu mesmo" when declining moves the bill on.
  final String? secondaryLabel;

  @override
  ConsumerState<CdConfirmSheet> createState() => _CdConfirmSheetState();
}

class _CdConfirmSheetState extends ConsumerState<CdConfirmSheet> {
  var _checking = false;
  var _denied = false;

  Future<void> _confirm() async {
    setState(() {
      _checking = true;
      _denied = false;
    });
    final navigator = Navigator.of(context);
    final passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(widget.title);
    if (!mounted) return;
    if (passed) {
      navigator.pop(true);
      return;
    }
    setState(() {
      _checking = false;
      _denied = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final reason = widget.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdStepper(
          steps: [l10n.confirmStepReview, l10n.confirmStepConfirm],
          current: 1,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          widget.title,
          style: AppTextStyles.titleLg.copyWith(color: palette.onSurface),
        ),
        if (reason != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: CdStatusBadge(
              tone: MoneyTone.pending,
              label: reason,
              icon: Symbols.shield_rounded,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final row in widget.rows)
          CdKeyValueRow(label: row.label, value: Text(row.value)),
        if (_denied) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.confirmDenied,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        CdButton.filled(
          key: CdConfirmSheet.confirmKey,
          expand: true,
          icon: Symbols.fingerprint_rounded,
          label: widget.confirmLabel,
          loading: _checking,
          onPressed: _confirm,
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: CdConfirmSheet.secondaryKey,
          expand: true,
          label: widget.secondaryLabel ?? l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
