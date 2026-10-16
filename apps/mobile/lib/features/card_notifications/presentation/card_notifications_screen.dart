import 'dart:async';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_options_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/card_notifications/presentation/card_notifications_controller.dart';
import 'package:cashdeck/features/transactions/presentation/transaction_labels.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Routes each app's notifications to the card they become previews on. Coming
/// back from the system settings reloads, since that is where access changes.
class CardNotificationsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const switchKey = Key('card-notifications-switch');
  static const accessKey = Key('card-notifications-access');
  static const offKey = Key('card-notifications-off');

  static Key cardKey(String id) => Key('card-notifications-card-$id');

  static Key appKey(String package) => Key('card-notifications-app-$package');

  @override
  ConsumerState<CardNotificationsScreen> createState() =>
      _CardNotificationsScreenState();
}

class _CardNotificationsScreenState
    extends ConsumerState<CardNotificationsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(cardNotificationsControllerProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _report(Future<AppFailure?> action) async {
    final failure = await action;
    if (failure == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    await showCdToast(context, message: failure.userMessage(l10n));
  }

  Future<void> _route(
    AppLocalizations l10n,
    CardNotificationsView view,
    NotifyingApp app,
  ) async {
    final current = view.status.routes[app.package];
    final picked = await showOptionsSheet<String?>(
      context,
      title: l10n.cardNotificationsPickCard(app.label),
      options: [
        PickerOption(
          value: null,
          label: l10n.cardNotificationsAppOff,
          key: CardNotificationsScreen.offKey,
          icon: Symbols.notifications_off_rounded,
          selected: current == null,
        ),
        for (final card in view.cards)
          PickerOption(
            value: card.id,
            label: accountName(card),
            subtitle: card.institution,
            key: CardNotificationsScreen.cardKey(card.id),
            icon: Symbols.credit_card_rounded,
            selected: card.id == current,
          ),
      ],
    );
    if (picked == null || picked.$1 == current) return;
    final controller = ref.read(cardNotificationsControllerProvider.notifier);
    await _report(controller.routeApp(app.package, picked.$1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = ref.watch(cardNotificationsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.cardNotificationsTitle)),
      body: switch (view) {
        AsyncData(:final value) => _body(context, l10n, value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(cardNotificationsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    CardNotificationsView view,
  ) {
    final controller = ref.read(cardNotificationsControllerProvider.notifier);
    final status = view.status;
    final hint = AppTextStyles.bodyMd.copyWith(
      color: context.palette.onSurfaceVariant,
    );
    Widget note(String text) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Text(text, style: hint),
    );
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.xl,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: CdSectionHeader(title: title, small: true),
    );
    if (!view.supported) {
      return ListView(
        children: [
          note(l10n.cardNotificationsIntro),
          note(l10n.cardNotificationsUnsupported),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        note(l10n.cardNotificationsIntro),
        if (status.access)
          CdListRow(
            icon: Symbols.notifications_active_rounded,
            title: l10n.cardNotificationsAccessTitle,
            subtitle: l10n.cardNotificationsAccessGranted,
          )
        else
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: CdInlineBanner(
              icon: Symbols.notifications_off_rounded,
              title: l10n.cardNotificationsAccessTitle,
              message: l10n.cardNotificationsAccessMissing,
              actionLabel: l10n.cardNotificationsAccessAction,
              actionKey: CardNotificationsScreen.accessKey,
              onAction: () =>
                  unawaited(_report(controller.openAccessSettings())),
            ),
          ),
        section(l10n.cardNotificationsAppsSection),
        if (view.cards.isEmpty) note(l10n.cardNotificationsNoCards),
        if (status.apps.isEmpty) note(l10n.cardNotificationsNoApps),
        for (final app in status.apps)
          CdListRow(
            key: CardNotificationsScreen.appKey(app.package),
            title: app.label,
            subtitle: switch (view.cardOf(app.package)) {
              final card? => l10n.cardNotificationsAppCard(accountName(card)),
              null => app.package,
            },
            icon: view.cardOf(app.package) == null
                ? Symbols.notifications_rounded
                : Symbols.credit_card_rounded,
            chevron: true,
            onTap: view.cards.isEmpty
                ? null
                : () => unawaited(_route(l10n, view, app)),
          ),
        const SizedBox(height: AppSpacing.lg),
        CdListRow(
          icon: Symbols.receipt_long_rounded,
          title: l10n.cardNotificationsSwitch,
          subtitle: view.canEnable ? null : l10n.cardNotificationsSwitchHint,
          trailing: Switch(
            key: CardNotificationsScreen.switchKey,
            value: status.enabled,
            onChanged: view.canEnable || status.enabled
                ? (enabled) => unawaited(
                    _report(controller.setEnabled(enabled: enabled)),
                  )
                : null,
          ),
        ),
        if (status.pending > 0)
          note(l10n.cardNotificationsPending(status.pending)),
      ],
    );
  }
}
