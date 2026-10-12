import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/recap/presentation/recap_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The way into the recap of the last month that closed; it loads nothing
/// until opened.
class RecapEntryCard extends ConsumerWidget {
  const new({super.key});

  static const tileKey = Key('recap-entry');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final month = lastClosedMonth(
      CalendarDate.brazilToday(ref.watch(clockProvider).now()),
    );
    return CdCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.cardPadding),
      child: CdListRow(
        key: tileKey,
        title: recapTitleOf(l10n, month),
        subtitle: l10n.recapEntrySubtitle,
        icon: Symbols.auto_stories_rounded,
        chevron: true,
        padding: EdgeInsets.zero,
        onTap: () => context.push(AppRoutes.recap(month.iso)).ignore(),
      ),
    );
  }
}
