import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/alerts/presentation/alert_labels.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

class AlertsScreen extends ConsumerWidget {
  const new({super.key});

  static const readAllKey = Key('alerts-read-all');
  static const settingsKey = Key('alerts-settings');
  static const loadMoreKey = Key('alerts-load-more');

  static Key rowKey(String id) => Key('alert-$id');

  static Key unreadKey(String id) => Key('alert-unread-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(alertsControllerProvider);
    final controller = ref.read(alertsControllerProvider.notifier);
    Future<void> report(Future<AppFailure?> action) async {
      final failure = await action;
      if (failure == null || !context.mounted) return;
      await showCdToast(context, message: failure.userMessage(l10n));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.alertsTitle),
        actions: [
          IconButton(
            key: readAllKey,
            tooltip: l10n.alertsReadAll,
            onPressed: () =>
                report(controller.markAllRead(ref.read(clockProvider).now())),
            icon: const Icon(Symbols.done_all_rounded),
          ),
          IconButton(
            key: settingsKey,
            tooltip: l10n.alertSettingsTitle,
            onPressed: () => context.push(AppRoutes.alertSettings),
            icon: const Icon(Symbols.tune_rounded),
          ),
        ],
      ),
      body: switch (inbox) {
        AsyncData(:final value) when value.items.isEmpty => CdEmptyState(
          icon: Symbols.notifications_rounded,
          title: l10n.alertsInboxEmpty,
        ),
        AsyncData(:final value) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(alertsControllerProvider);
            await ref.read(alertsControllerProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            children: [
              for (final alert in value.items)
                AlertRow(
                  key: rowKey(alert.id),
                  alert: alert,
                  onTap: () async {
                    await report(controller.markRead(alert.id));
                    final billId = alert.billId;
                    if (billId == null || !context.mounted) return;
                    context.go(AppRoutes.bill(billId));
                  },
                ),
              if (value.nextCursor != null)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  child: CdButton.text(
                    key: loadMoreKey,
                    label: l10n.alertsLoadMore,
                    onPressed: () => report(controller.loadMore()),
                  ),
                ),
            ],
          ),
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(alertsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class AlertRow extends StatelessWidget {
  const new({required this.alert, required this.onTap, super.key});

  final AppAlert alert;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final when = DateFormat(
      'd MMM, HH:mm',
      Localizations.localeOf(context).toLanguageTag(),
    ).format(alert.createdAt.toLocal());
    final text = alertText(AppLocalizations.of(context), alert);
    return CdListRow(
      icon: alertKindIcon(alert.kind),
      title: text.title,
      subtitle: '${text.body}\n$when',
      onTap: onTap,
      trailing: alert.unread
          ? Container(
              key: AlertsScreen.unreadKey(alert.id),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: palette.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}
