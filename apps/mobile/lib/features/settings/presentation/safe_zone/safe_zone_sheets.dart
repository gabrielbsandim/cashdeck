import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Where a new safe zone comes from.
sealed class ZoneSource {
  const new();
}

final class CurrentPlace extends ZoneSource {
  const new();
}

final class TypedAddress extends ZoneSource {
  const new(this.address);

  final String address;
}

/// Offers the current location or a typed address; pops the [ZoneSource],
/// or null when dismissed.
class SafeZoneAddSheet extends StatefulWidget {
  const new({super.key});

  static const hereKey = Key('safe-zone-add-here');
  static const addressKey = Key('safe-zone-address-field');
  static const saveKey = Key('safe-zone-address-save');

  @override
  State<SafeZoneAddSheet> createState() => _SafeZoneAddSheetState();
}

class _SafeZoneAddSheetState extends State<SafeZoneAddSheet> {
  var _address = '';

  VoidCallback? get _save {
    final address = _address.trim();
    if (address.isEmpty) return null;
    return () => Navigator.of(context).pop(TypedAddress(address));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdListRow(
          key: SafeZoneAddSheet.hereKey,
          icon: Symbols.my_location_rounded,
          title: l10n.safeZoneAddHere,
          subtitle: l10n.safeZoneAddHereHint,
          padding: EdgeInsets.zero,
          onTap: () => Navigator.of(context).pop(const CurrentPlace()),
        ),
        const SizedBox(height: AppSpacing.lg),
        CdTextField(
          key: SafeZoneAddSheet.addressKey,
          label: l10n.safeZoneAddressLabel,
          hintText: l10n.safeZoneAddressHint,
          helperText: l10n.safeZoneAddressHelper,
          keyboardType: TextInputType.streetAddress,
          textInputAction: TextInputAction.done,
          maxLines: 2,
          onChanged: (value) => setState(() => _address = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: SafeZoneAddSheet.saveKey,
          expand: true,
          icon: Symbols.search_rounded,
          label: l10n.safeZoneAddressSave,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Asks for a zone's name; pops the trimmed name, or null when dismissed.
class SafeZoneNameSheet extends StatefulWidget {
  const new({required this.current, super.key});

  static const fieldKey = Key('safe-zone-name-field');
  static const saveKey = Key('safe-zone-name-save');
  static const maxLength = 60;

  final String current;

  @override
  State<SafeZoneNameSheet> createState() => _SafeZoneNameSheetState();
}

class _SafeZoneNameSheetState extends State<SafeZoneNameSheet> {
  late String _name = widget.current;

  VoidCallback? get _save {
    final name = _name.trim();
    if (name.isEmpty || name == widget.current) return null;
    return () => Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CdTextField(
          key: SafeZoneNameSheet.fieldKey,
          label: l10n.safeZoneNameLabel,
          initialValue: widget.current,
          helperText: l10n.safeZoneNameHelper,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            LengthLimitingTextInputFormatter(SafeZoneNameSheet.maxLength),
          ],
          onChanged: (value) => setState(() => _name = value),
        ),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: SafeZoneNameSheet.saveKey,
          expand: true,
          label: l10n.saveButton,
          onPressed: _save,
        ),
      ],
    );
  }
}
