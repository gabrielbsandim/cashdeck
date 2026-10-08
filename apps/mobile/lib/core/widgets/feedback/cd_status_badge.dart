import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/tone_icon.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// A status pill: the tone's container, its icon and a label, always together.
class CdStatusBadge extends StatelessWidget {
  const new({required this.tone, this.label, this.icon, super.key})
    : colors = null;

  /// A badge in colors that are not a money state, such as an entity tint.
  const new custom({
    required ToneColors this.colors,
    required String this.label,
    required IconData this.icon,
    super.key,
  }) : tone = MoneyTone.neutral;

  final MoneyTone tone;
  final String? label;
  final IconData? icon;
  final ToneColors? colors;

  @override
  Widget build(BuildContext context) {
    final colors = this.colors ?? context.tone(tone);
    final text = label ?? tone.label(AppLocalizations.of(context));
    return Container(
      constraints: const BoxConstraints(minHeight: 24),
      padding: const EdgeInsets.fromLTRB(6, 2, AppSpacing.sm, 2),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? tone.icon, size: 14, color: colors.foreground),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: AppTextStyles.labelMd.copyWith(color: colors.foreground),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
