import 'dart:async';

import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A boleto line or a Pix payload, monospaced, with one copy action that
/// confirms in place for two seconds.
class CdCopyField extends StatefulWidget {
  const new({
    required this.code,
    this.label,
    this.copyLabel,
    this.valid = false,
    this.compact = false,
    this.buttonKey,
    super.key,
  });

  final String code;

  /// LINHA DIGITÁVEL or PIX COPIA E COLA; shown in caps above the code.
  final String? label;
  final String? copyLabel;
  final bool valid;

  /// One line with the code truncated and a small copy button, for inside a
  /// ladder step.
  final bool compact;
  final Key? buttonKey;

  @override
  State<CdCopyField> createState() => _CdCopyFieldState();
}

class _CdCopyFieldState extends State<CdCopyField> {
  var _copied = false;
  Timer? _reset;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final copyLabel = widget.copyLabel ?? l10n.copyCodeButton;
    if (widget.compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, 4, 4),
        decoration: BoxDecoration(
          color: palette.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.code.copyWith(
                  fontSize: 14,
                  color: palette.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            CdButton.filled(
              key: widget.buttonKey,
              dense: true,
              icon: _copied
                  ? Symbols.check_rounded
                  : Symbols.content_copy_rounded,
              label: _copied ? l10n.copied : l10n.copyShort,
              onPressed: _copy,
            ),
          ],
        ),
      );
    }
    final label = widget.label;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: palette.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (label != null)
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: AppTextStyles.labelMd.copyWith(
                      color: palette.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              if (widget.valid) ...[
                Icon(Symbols.verified_rounded, size: 16, color: money.paid),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  l10n.codeValid,
                  style: AppTextStyles.labelMd.copyWith(color: money.paid),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            widget.code,
            style: AppTextStyles.code.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.medium),
            child: _copied
                ? Container(
                    key: const ValueKey('copied'),
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: money.paidContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.check_rounded,
                          color: money.paid,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          l10n.copied,
                          style: AppTextStyles.labelLg.copyWith(
                            color: money.paid,
                          ),
                        ),
                      ],
                    ),
                  )
                : CdButton.filled(
                    key: widget.buttonKey,
                    expand: true,
                    icon: Symbols.content_copy_rounded,
                    label: copyLabel,
                    onPressed: _copy,
                  ),
          ),
        ],
      ),
    );
  }
}
