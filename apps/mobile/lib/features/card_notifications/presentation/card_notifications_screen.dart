import 'dart:async';

import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_checkbox_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/card_notifications/presentation/card_notifications_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Picks the card and the apps whose notifications become previews. Coming
/// back from the system settings reloads, since that is where access changes.
class CardNotificationsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const switchKey = Key('card-notifications-switch');
  static const accessKey = Key('card-notifications-access');

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
        section(l10n.cardNotificationsCardSection),
        if (view.cards.isEmpty) note(l10n.cardNotificationsNoCards),
        for (final card in view.cards)
          CdCheckboxRow(
            key: CardNotificationsScreen.cardKey(card.id),
            title: card.name,
            subtitle: Text(card.institution, style: hint),
            value: card.id == status.accountId,
            onChanged: (_) =>
                unawaited(_report(controller.selectCard(card.id))),
          ),
        section(l10n.cardNotificationsAppsSection),
        if (status.apps.isEmpty) note(l10n.cardNotificationsNoApps),
        for (final app in status.apps)
          CdCheckboxRow(
            key: CardNotificationsScreen.appKey(app.package),
            title: app.label,
            subtitle: Text(app.package, style: hint),
            value: status.packages.contains(app.package),
            onChanged: (watched) => unawaited(
              _report(controller.toggleApp(app.package, watched: watched)),
            ),
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
