import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

enum CdButtonVariant { filled, tonal, outlined, text, danger }

/// The one button: 48 high, AppRadius.md, a 12% state layer and a 0.98 press
/// scale. [loading] keeps the label and blocks a second tap.
class CdButton extends StatefulWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.variant = CdButtonVariant.filled,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  });

  const new filled({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  }) : variant = CdButtonVariant.filled;

  const new tonal({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  }) : variant = CdButtonVariant.tonal;

  const new outlined({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  }) : variant = CdButtonVariant.outlined;

  const new text({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  }) : variant = CdButtonVariant.text;

  const new danger({
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
    this.dense = false,
    super.key,
  }) : variant = CdButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final CdButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expand;

  /// 40 high, for actions inside a card; the hit area stays 48.
  final bool dense;

  @override
  State<CdButton> createState() => _CdButtonState();
}

class _CdButtonState extends State<CdButton> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    final enabled = widget.onPressed != null && !widget.loading;
    final (background, foreground, border) = switch (widget.variant) {
      CdButtonVariant.filled => (palette.primary, palette.onPrimary, null),
      CdButtonVariant.tonal => (
        palette.primaryContainer,
        palette.onPrimaryContainer,
        null,
      ),
      CdButtonVariant.outlined => (
        Colors.transparent,
        palette.primary,
        palette.outline,
      ),
      CdButtonVariant.text => (Colors.transparent, palette.primary, null),
      CdButtonVariant.danger => (money.failedContainer, money.failed, null),
    };
    final disabled = widget.onPressed == null;
    final fill = disabled && background != Colors.transparent
        ? palette.surfaceContainerHigh
        : background;
    final ink = disabled
        ? palette.onSurfaceVariant.withValues(alpha: 0.7)
        : foreground;
    final icon = widget.icon;
    final height = widget.dense ? 40.0 : 48.0;
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: ink),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Icon(icon, size: 20, color: ink),
          ),
        Flexible(
          child: Text(
            widget.label,
            style: AppTextStyles.labelLg.copyWith(color: ink),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: border == null
          ? BorderSide.none
          : BorderSide(color: disabled ? palette.outlineVariant : border),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
        child: Center(
          widthFactor: widget.expand ? null : 1,
          heightFactor: 1,
          child: AnimatedScale(
            scale: _pressed ? 0.98 : 1,
            duration: AppMotion.of(context, AppMotion.fast),
            curve: AppMotion.standard,
            child: Material(
              color: fill,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: _setPressed,
                overlayColor: WidgetStatePropertyAll(
                  foreground.withValues(alpha: 0.12),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: height,
                    minWidth: widget.expand ? double.infinity : 64,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
