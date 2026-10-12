import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/auth/domain/device_session.dart';
import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:cashdeck/features/auth/presentation/device_sessions_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

IconData sessionPlatformIcon(SessionPlatform platform) => switch (platform) {
  SessionPlatform.android => Symbols.phone_android_rounded,
  SessionPlatform.ios => Symbols.phone_iphone_rounded,
  SessionPlatform.web => Symbols.computer_rounded,
};

/// Every phone signed in to the server, this one first. Disconnecting one
/// asks for the device check; disconnecting this one signs out.
class DeviceSessionsScreen extends ConsumerWidget {
  const new({super.key});

  static Key rowKey(String id) => Key('device-session-$id');

  static const currentKey = Key('device-session-current');

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    DeviceSession session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCdConfirmSheet(
      context,
      title: l10n.deviceSessionsRevokeTitle(session.deviceName),
      reason: session.current ? l10n.deviceSessionsRevokeCurrent : null,
      rows: [
        CdConfirmRow(
          l10n.deviceSessionsLastUsed,
          CalendarDate.brazilToday(session.lastUsedAt).display,
        ),
      ],
      confirmLabel: l10n.deviceSessionsRevoke,
    );
    if (confirmed != true || !context.mounted) return;
    final failure = await ref
        .read(deviceSessionsControllerProvider.notifier)
        .revoke(session);
    if (!context.mounted) return;
    await showCdToast(
      context,
      icon: failure == null
          ? Symbols.check_circle_rounded
          : Symbols.error_rounded,
      message: failure?.userMessage(l10n) ?? l10n.deviceSessionsRevoked,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sessions = ref.watch(deviceSessionsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.deviceSessionsTitle)),
      body: switch (sessions) {
        AsyncData(:final value) => ListView(
          children: [
            for (final session in value)
              CdListRow(
                key: rowKey(session.id),
                icon: sessionPlatformIcon(session.platform),
                title: session.deviceName,
                subtitle: l10n.deviceSessionsSubtitle(
                  CalendarDate.brazilToday(session.lastUsedAt).display,
                  CalendarDate.brazilToday(session.createdAt).display,
                ),
                trailing: session.current
                    ? CdStatusBadge(
                        key: currentKey,
                        tone: MoneyTone.neutral,
                        label: l10n.deviceSessionsCurrent,
                      )
                    : null,
                onTap: () => _revoke(context, ref, session),
              ),
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(deviceSessionsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}
