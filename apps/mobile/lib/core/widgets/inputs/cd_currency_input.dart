import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Typed cents fill from the right: 1, 12, 123 read 0,01, 0,12, 1,23.
final class CentsInputFormatter extends TextInputFormatter {
  const new();

  static int centsOf(String text) {
    final digits = text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 0;
    return int.parse(digits.length > 13 ? digits.substring(0, 13) : digits);
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = MoneyFormat.digits(Money(centsOf(newValue.text)));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class CdCurrencyInput extends StatefulWidget {
  const new({
    required this.label,
    required this.onChanged,
    this.initial = const Money(0),
    this.helperText,
    this.errorText,
    this.large = true,
    this.currencyChip,
    super.key,
  });

  final String label;
  final ValueChanged<Money> onChanged;
  final Money initial;
  final String? helperText;
  final String? errorText;

  /// amountLg for the main value of a screen, amountMd inside a form.
  final bool large;

  /// A currency picker shown before the value, for foreign amounts.
  final Widget? currencyChip;

  @override
  State<CdCurrencyInput> createState() => _CdCurrencyInputState();
}

class _CdCurrencyInputState extends State<CdCurrencyInput> {
  late final _controller = TextEditingController(
    text: MoneyFormat.digits(widget.initial),
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    final error = widget.errorText;
    final helper = widget.helperText;
    final lineColor = switch ((error, _focus.hasFocus)) {
      (String(), _) => money.failed,
      (null, true) => palette.primary,
      (null, false) => palette.outline,
    };
    final amountStyle = widget.large
        ? AppTextStyles.amountLg
        : AppTextStyles.amountMd;
    final chip = widget.currencyChip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTextStyles.labelMd.copyWith(
            color: _focus.hasFocus ? palette.primary : palette.onSurfaceVariant,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: lineColor,
                width: _focus.hasFocus || error != null ? 2 : 1,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (chip != null) ...[chip, const SizedBox(width: AppSpacing.sm)],
              Text(
                MoneyFormat.symbolOf(widget.initial.currency),
                style: AppTextStyles.titleMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CentsInputFormatter()],
                  style: amountStyle.copyWith(color: palette.onSurface),
                  cursorColor: palette.primary,
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    isDense: true,
                  ),
                  onChanged: (text) => widget.onChanged(
                    Money(
                      CentsInputFormatter.centsOf(text),
                      currency: widget.initial.currency,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                Icon(Symbols.error_rounded, size: 18, color: money.failed),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    error,
                    style: AppTextStyles.bodyMd.copyWith(color: money.failed),
                  ),
                ),
              ],
            ),
          )
        else if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              helper,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
