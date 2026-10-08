import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/states/cd_state_view.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CdErrorState extends StatelessWidget {
  const new({required this.failure, this.onRetry, super.key});

  static const retryKey = Key('error-state-retry');

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onRetry = this.onRetry;
    return CdStateView(
      icon: failure is NetworkFailure
          ? Symbols.cloud_off_rounded
          : Symbols.sync_problem_rounded,
      colors: context.tone(MoneyTone.failed),
      title: l10n.loadFailedTitle,
      message: failure.userMessage(l10n),
      action: onRetry == null
          ? null
          : CdButton.outlined(
              key: retryKey,
              label: l10n.retryButton,
              icon: Symbols.refresh_rounded,
              onPressed: onRetry,
            ),
    );
  }
}
