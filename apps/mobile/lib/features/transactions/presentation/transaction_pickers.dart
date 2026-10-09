import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// Asks whether a new category also goes to the similar transactions.
/// True for all of them, false for this one only, null when dismissed.
Future<bool?> askApplyToSimilar(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showCdBottomSheet<bool>(
    context,
    title: l10n.applyToSimilarTitle,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.applyToSimilarMessage,
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdButton.filled(
          key: applyToSimilarKey,
          expand: true,
          label: l10n.applyToSimilarYes,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          key: applyToThisOnlyKey,
          expand: true,
          label: l10n.applyToSimilarNo,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
}

const applyToSimilarKey = Key('apply-to-similar');
const applyToThisOnlyKey = Key('apply-to-this-only');
