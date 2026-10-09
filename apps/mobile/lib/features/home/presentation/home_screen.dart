import 'package:cashdeck/app/shell/tab_app_bar.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/company_home.dart';
import 'package:cashdeck/features/home/presentation/consolidated_home.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/features/home/presentation/personal_home.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class HomeScreen extends ConsumerWidget {
  const new({super.key});

  static const Key alertsKey = TabAppBar.alertsKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeControllerProvider);
    return Scaffold(
      appBar: const TabAppBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref
            ..invalidate(homeControllerProvider)
            ..invalidate(billsControllerProvider)
            ..invalidate(unreadAlertsProvider);
          await ref.read(homeControllerProvider.future);
        },
        child: switch (summary) {
          AsyncData(:final value) => switch (value) {
            PersonalSummary() => PersonalHome(summary: value),
            CompanySummary() => CompanyHome(summary: value),
            ConsolidatedSummary() => ConsolidatedHome(summary: value),
          },
          AsyncError(:final error) => CdErrorState(
            failure: failureOf(error),
            onRetry: () => ref.invalidate(homeControllerProvider),
          ),
          _ => const CdSkeleton(),
        },
      ),
    );
  }
}

Future<void> showAlertsSheet(BuildContext context, List<HomeAlert> alerts) {
  final l10n = AppLocalizations.of(context);
  return showCdBottomSheet<void>(
    context,
    title: l10n.alertsTitle,
    builder: (_) => alerts.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(l10n.alertsEmpty),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, alert) in alerts.indexed)
                HomeAlertRow(key: Key('sheet-alert-$index'), alert: alert),
            ],
          ),
  );
}
