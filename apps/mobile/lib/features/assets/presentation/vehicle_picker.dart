import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/inputs/cd_search_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/assets/domain/asset.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

typedef VehicleOptionsLoader = Future<Result<List<VehicleOption>>> Function();

/// A searchable list of one step of the FIPE table.
Future<VehicleOption?> showVehicleOptions(
  BuildContext context, {
  required String title,
  required VehicleOptionsLoader load,
}) => showCdBottomSheet<VehicleOption>(
  context,
  title: title,
  builder: (_) => VehicleOptionsSheet(load: load),
);

class VehicleOptionsSheet extends StatefulWidget {
  const new({required this.load, super.key});

  final VehicleOptionsLoader load;

  static const searchKey = Key('vehicle-search');
  static const retryKey = Key('vehicle-retry');

  static Key optionKey(String code) => Key('vehicle-option-$code');

  @override
  State<VehicleOptionsSheet> createState() => _VehicleOptionsSheetState();
}

class _VehicleOptionsSheetState extends State<VehicleOptionsSheet> {
  final _search = TextEditingController();
  late Future<Result<List<VehicleOption>>> _options = widget.load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder(
      future: _options,
      builder: (context, snapshot) => switch (snapshot.data) {
        null => const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        Err(:final failure) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              failure.userMessage(l10n),
              style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
            ),
            const SizedBox(height: AppSpacing.md),
            CdButton.text(
              key: VehicleOptionsSheet.retryKey,
              label: l10n.retryButton,
              onPressed: () => setState(() {
                _options = widget.load();
              }),
            ),
          ],
        ),
        Ok(:final value) => _List(options: value, search: _search),
      },
    );
  }
}

class _List extends StatelessWidget {
  const new({required this.options, required this.search});

  final List<VehicleOption> options;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: search,
      builder: (context, query, _) {
        final wanted = foldText(query.text.trim());
        final shown = options
            .where((option) => foldText(option.name).contains(wanted))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CdSearchField(
              key: VehicleOptionsSheet.searchKey,
              controller: search,
              hint: l10n.vehicleSearch,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.vehicleNoMatch,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: context.palette.onSurfaceVariant,
                  ),
                ),
              ),
            for (final option in shown)
              CdListRow(
                key: VehicleOptionsSheet.optionKey(option.code),
                title: option.name,
                padding: EdgeInsets.zero,
                onTap: () => Navigator.of(context).pop(option),
              ),
          ],
        );
      },
    );
  }
}
