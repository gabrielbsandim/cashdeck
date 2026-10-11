import 'package:cashdeck/core/security/safe_mode.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The state of the safe mode in one line, for Ajustes and this screen.
String safeModeStatusLabel(
  AppLocalizations l10n,
  SafeModeState mode,
  String locale,
) {
  final until = mode.releasedUntil;
  if (!mode.enabled) return l10n.safeZoneOff;
  if (until != null) {
    return l10n.safeZoneReleased(DateFormat.Hm(locale).format(until.toLocal()));
  }
  return switch (mode.status) {
    ZoneStatus.unknown => l10n.safeZoneChecking,
    ZoneStatus.inside => l10n.safeZoneInside,
    ZoneStatus.outside => l10n.safeZoneOutside,
  };
}

/// The places where the app opens in full; away from all of them it limits
/// itself. Zones change only from inside one.
class SafeZoneScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const addKey = Key('safe-zone-add');
  static const endReleaseKey = Key('safe-zone-end-release');
  static const limitedNoteKey = Key('safe-zone-limited-note');

  static Key removeKey(int index) => Key('safe-zone-remove-$index');

  static Key renameKey(int index) => Key('safe-zone-rename-$index');

  @override
  ConsumerState<SafeZoneScreen> createState() => _SafeZoneScreenState();
}

class _SafeZoneScreenState extends ConsumerState<SafeZoneScreen> {
  var _saving = false;

  Future<void> _report(SafeZoneChange change, {String? saved}) async {
    final l10n = AppLocalizations.of(context);
    final message = switch (change) {
      SafeZoneChange.saved => saved ?? l10n.safeZoneSaved,
      SafeZoneChange.limited => l10n.errorSafeMode,
      SafeZoneChange.noLocation => l10n.safeZoneNoLocation,
    };
    await showCdToast(context, message: message);
  }

  Future<void> _addHere() async {
    setState(() => _saving = true);
    final change = await ref
        .read(safeModeProvider.notifier)
        .addCurrentLocation();
    if (!mounted) return;
    setState(() => _saving = false);
    await _report(change);
  }

  Future<void> _rename(SafeZone zone, String current) async {
    final l10n = AppLocalizations.of(context);
    final name = await showCdBottomSheet<String>(
      context,
      title: l10n.safeZoneNameTitle,
      builder: (_) => SafeZoneNameSheet(current: current),
    );
    if (name == null || !mounted) return;
    final change = await ref
        .read(safeModeProvider.notifier)
        .renameZone(zone, name);
    if (!mounted) return;
    await _report(change, saved: l10n.safeZoneRenamed);
  }

  Future<void> _remove(SafeZone zone) async {
    final change = await ref.read(safeModeProvider.notifier).removeZone(zone);
    if (!mounted) return;
    await _report(change);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final mode = ref.watch(safeModeProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tone = switch ((mode.enabled, mode.limited)) {
      (false, _) => MoneyTone.neutral,
      (true, true) => MoneyTone.failed,
      (true, false) => MoneyTone.paid,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.safeZoneTitle)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: Text(
              l10n.safeZoneIntro,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: CdInlineBanner(
              icon: Symbols.shield_rounded,
              tone: tone,
              message: safeModeStatusLabel(l10n, mode, locale),
              actionKey: SafeZoneScreen.endReleaseKey,
              actionLabel: mode.releasedUntil == null
                  ? null
                  : l10n.safeZoneEndRelease,
              onAction: ref.read(safeModeProvider.notifier).endRelease,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (mode.zones.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                l10n.safeZoneEmpty,
                style: AppTextStyles.bodyMd.copyWith(color: palette.onSurface),
              ),
            ),
          for (final (index, zone) in mode.zones.indexed)
            _zoneRow(l10n, mode, index, zone),
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
            ),
            child: CdButton.tonal(
              key: SafeZoneScreen.addKey,
              expand: true,
              icon: Symbols.my_location_rounded,
              label: l10n.safeZoneAddHere,
              loading: _saving,
              onPressed: mode.limited ? null : _addHere,
            ),
          ),
          if (mode.limited)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                0,
              ),
              child: Text(
                l10n.safeZoneLimitedNote,
                key: SafeZoneScreen.limitedNoteKey,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.money.failed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _zoneRow(
    AppLocalizations l10n,
    SafeModeState mode,
    int index,
    SafeZone zone,
  ) {
    final title = zone.name ?? l10n.safeZoneItem(index + 1);
    final rename = mode.limited ? null : () => _rename(zone, title);
    return CdListRow(
      icon: Symbols.home_pin_rounded,
      title: title,
      titleMaxLines: 2,
      subtitle: l10n.safeZoneRadius(zone.radiusMeters),
      onTap: rename,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: SafeZoneScreen.renameKey(index),
            tooltip: l10n.safeZoneRename,
            icon: const Icon(Symbols.edit_rounded),
            onPressed: rename,
          ),
          IconButton(
            key: SafeZoneScreen.removeKey(index),
            tooltip: l10n.safeZoneRemove,
            icon: const Icon(Symbols.delete_rounded),
            onPressed: mode.limited ? null : () => _remove(zone),
          ),
        ],
      ),
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
