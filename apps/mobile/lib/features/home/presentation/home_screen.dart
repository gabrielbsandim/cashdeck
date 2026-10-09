import 'package:cashdeck/app/shell/tab_app_bar.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/insights/cd_entity_glow.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_refresh.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/automation/presentation/automation_controller.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/home/domain/home_summary.dart';
import 'package:cashdeck/features/home/presentation/company_home.dart';
import 'package:cashdeck/features/home/presentation/consolidated_home.dart';
import 'package:cashdeck/features/home/presentation/home_controller.dart';
import 'package:cashdeck/features/home/presentation/home_sections.dart';
import 'package:cashdeck/features/home/presentation/personal_home.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/transactions/presentation/transactions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class HomeScreen extends ConsumerWidget {
  const new({super.key});

  static const Key alertsKey = TabAppBar.alertsKey;

  /// Every source the three Início variants read, the summary tiles included.
  static final List<ProviderBase<AsyncValue<Object?>>> refreshed = [
    homeControllerProvider,
    billsControllerProvider,
    unreadAlertsProvider,
    insightsOverviewProvider,
    transactionAccountsProvider,
    installmentsProvider,
    subscriptionsControllerProvider,
    automationControllerProvider,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(homeControllerProvider);
    final palette = context.palette;
    final top = MediaQuery.paddingOf(context).top + TabAppBar.height;
    final tone = switch (ref.watch(entityScopeProvider)) {
      EntityScope.personal => EntityTone.personal,
      EntityScope.company => EntityTone.company,
      EntityScope.consolidated => EntityTone.consolidated,
    };
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: TabAppBar(
        background: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? palette.surface
              : palette.surface.withValues(alpha: 0),
        ),
      ),
      body: Stack(
        children: [
          CdEntityGlow(colors: context.glow.of(tone)),
          CdRefresh(
            edgeOffset: top,
            providers: refreshed,
            child: switch (summary) {
              AsyncData(:final value) => switch (value) {
                PersonalSummary() => PersonalHome(summary: value),
                CompanySummary() => CompanyHome(summary: value),
                ConsolidatedSummary() => ConsolidatedHome(summary: value),
              },
              AsyncError(:final error) => Padding(
                padding: EdgeInsets.only(top: top),
                child: CdErrorState(
                  failure: failureOf(error),
                  onRetry: () => ref.invalidate(homeControllerProvider),
                ),
              ),
              _ => Padding(
                padding: EdgeInsets.only(top: top),
                child: const CdSkeleton(),
              ),
            },
          ),
        ],
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
