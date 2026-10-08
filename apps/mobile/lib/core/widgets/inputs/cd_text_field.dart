import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// An outlined field with a floating label. [secret] adds the eye that shows
/// what was typed; [valid] marks a value the server or a rule accepted.
class CdTextField extends StatefulWidget {
  const new({
    required this.label,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.errorText,
    this.helperText,
    this.hintText,
    this.secret = false,
    this.valid = false,
    this.enabled = true,
    this.monospace = false,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.suffix,
    this.maxLines = 1,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final String? helperText;
  final String? hintText;
  final bool secret;
  final bool valid;
  final bool enabled;
  final bool monospace;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final Widget? suffix;
  final int maxLines;
  final Iterable<String>? autofillHints;

  @override
  State<CdTextField> createState() => _CdTextFieldState();
}

class _CdTextFieldState extends State<CdTextField> {
  var _revealed = false;

  Widget? _suffix(AppLocalizations l10n) {
    final money = context.money;
    if (widget.errorText != null) {
      return Icon(Symbols.error_rounded, color: money.failed);
    }
    if (widget.secret) {
      return IconButton(
        tooltip: _revealed ? l10n.hideTyped : l10n.showTyped,
        icon: Icon(
          _revealed
              ? Symbols.visibility_off_rounded
              : Symbols.visibility_rounded,
        ),
        onPressed: () => setState(() => _revealed = !_revealed),
      );
    }
    if (widget.valid) {
      return Icon(Symbols.check_circle_rounded, color: money.paid);
    }
    return widget.suffix;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final base = widget.monospace ? AppTextStyles.code : AppTextStyles.bodyLg;
    final validBorder = widget.valid && widget.errorText == null
        ? OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: money.paid, width: 2),
          )
        : null;
    return TextFormField(
      controller: widget.controller,
      initialValue: widget.controller == null ? widget.initialValue : null,
      onChanged: widget.onChanged,
      enabled: widget.enabled,
      obscureText: widget.secret && !_revealed,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      maxLines: widget.secret ? 1 : widget.maxLines,
      style: base.copyWith(
        color: widget.enabled ? palette.onSurface : palette.onSurfaceVariant,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        errorText: widget.errorText,
        helperText: widget.helperText,
        helperMaxLines: 3,
        errorMaxLines: 3,
        fillColor: widget.enabled ? null : palette.surfaceContainerLow,
        enabledBorder: validBorder,
        focusedBorder: validBorder,
        suffixIcon: _suffix(l10n),
      ),
    );
  }
}
