import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

final class PickerOption<T> {
  const new({
    required this.value,
    required this.label,
    required this.key,
    this.icon,
    this.selected = false,
  });

  final T value;
  final String label;
  final Key key;
  final IconData? icon;
  final bool selected;
}

/// A sheet of options; resolves with the chosen value wrapped in a record so
/// choosing a null value differs from closing the sheet.
Future<(T,)?> showOptionsSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
}) => showCdBottomSheet<(T,)>(
  context,
  title: title,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final option in options)
        CdListRow(
          key: option.key,
          title: option.label,
          icon: option.icon,
          padding: EdgeInsets.zero,
          trailing: option.selected
              ? Icon(Symbols.check_rounded, color: context.palette.primary)
              : null,
          onTap: () => Navigator.of(context).pop((option.value,)),
        ),
    ],
  ),
);
