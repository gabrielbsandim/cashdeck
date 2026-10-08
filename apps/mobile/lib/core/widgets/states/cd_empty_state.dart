import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/states/cd_state_view.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class CdEmptyState extends StatelessWidget {
  const new({
    required this.title,
    this.icon = Symbols.inbox_rounded,
    this.message,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    super.key,
  });

  final String title;
  final IconData icon;
  final String? message;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final actionLabel = this.actionLabel;
    return CdStateView(
      icon: icon,
      title: title,
      message: message,
      colors: context.tone(MoneyTone.assisted),
      action: actionLabel == null
          ? null
          : CdButton.tonal(
              label: actionLabel,
              icon: actionIcon,
              onPressed: onAction,
            ),
    );
  }
}
