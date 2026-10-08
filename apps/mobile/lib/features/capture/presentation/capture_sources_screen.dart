import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/capture/capture_providers.dart';
import 'package:cashdeck/features/capture/domain/capture_sources.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

class CaptureController extends AsyncNotifier<CaptureSources> {
  @override
  Future<CaptureSources> build() async =>
      (await ref.watch(captureRepositoryProvider).sources()).orThrow;

  Future<AppFailure?> _apply(Future<Result<CaptureSources>> call) async {
    switch (await call) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> readNow(String id) =>
      _apply(ref.read(captureRepositoryProvider).readNow(id));

  Future<AppFailure?> disconnect(String id) =>
      _apply(ref.read(captureRepositoryProvider).disconnect(id));

  Future<AppFailure?> setDda(DdaEnrollment dda, {required bool on}) =>
      _apply(ref.read(captureRepositoryProvider).setDda(dda.owner, on: on));
}

final AsyncNotifierProvider<CaptureController, CaptureSources>
captureControllerProvider =
    AsyncNotifierProvider.autoDispose<CaptureController, CaptureSources>(
      CaptureController.new,
      retry: noRetry,
    );

/// Where bills come from: mailboxes, the bank's DDA and the sources that are
/// always on.
class CaptureSourcesScreen extends ConsumerWidget {
  const new({super.key});

  static Key readKey(String id) => Key('capture-read-$id');
  static Key disconnectKey(String id) => Key('capture-disconnect-$id');
  static const connectKey = Key('capture-connect');
  static const scanKey = Key('capture-scan');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sources = ref.watch(captureControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureTitle)),
      body: switch (sources) {
        AsyncData(:final value) => _Sources(sources: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(captureControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Sources extends ConsumerWidget {
  const new({required this.sources});

  final CaptureSources sources;

  /// Opens the provider's consent page; the mailbox appears after the
  /// server receives the grant and the list is refreshed.
  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final owner = switch (ref.read(entityScopeProvider)) {
      EntityScope.company => EntityKind.company,
      EntityScope.personal || EntityScope.consolidated => EntityKind.personal,
    };
    final url = await ref
        .read(captureRepositoryProvider)
        .mailboxAuthorizationUrl(owner);
    final opened = switch (url) {
      Ok(:final value) => await ref.read(linkOpenerProvider).open(value),
      Err() => false,
    };
    if (opened || !context.mounted) return;
    await showCdToast(
      context,
      icon: Symbols.mail_rounded,
      message: l10n.captureConnectFailed,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final controller = ref.read(captureControllerProvider.notifier);
    final always = [
      (
        Symbols.ios_share_rounded,
        l10n.captureShareTitle,
        l10n.captureShareBody,
        null,
      ),
      (
        Symbols.photo_camera_rounded,
        l10n.captureCameraTitle,
        l10n.captureCameraBody,
        () => context.push(AppRoutes.scanBill).ignore(),
      ),
      (
        Symbols.forum_rounded,
        l10n.captureChatTitle,
        l10n.captureChatBody,
        null,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        _Header(l10n.captureEmail),
        for (final mailbox in sources.mailboxes)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
              vertical: AppSpacing.xs,
            ),
            child: _MailboxCard(
              mailbox: mailbox,
              onRead: () async {
                final failure = await controller.readNow(mailbox.id);
                if (!context.mounted) return;
                await showOutcomeToast(
                  context,
                  failure,
                  success: l10n.captureReadToast,
                );
              },
              onDisconnect: () async {
                final failure = await controller.disconnect(mailbox.id);
                if (!context.mounted) return;
                await showOutcomeToast(
                  context,
                  failure,
                  success: l10n.captureDisconnectedToast,
                );
              },
            ),
          ),
        CdListRow(
          key: CaptureSourcesScreen.connectKey,
          leading: Icon(Symbols.add_rounded, color: palette.primary),
          title: l10n.captureConnectMailbox,
          subtitle: l10n.captureConnectMailboxHint,
          onTap: () => _connect(context, ref),
        ),
        _Header(l10n.captureDda),
        for (final dda in sources.dda)
          CdListRow(
            key: Key('capture-dda-${dda.owner.name}'),
            leading: EntityKindBadge(kind: dda.owner),
            title: l10n.captureDdaTitle(entityKindLabel(l10n, dda.owner)),
            subtitle: l10n.captureDdaBody(
              dda.bank,
              CalendarDate.brazilToday(dda.lastBatchAt).dayMonth,
              brazilTime(dda.lastBatchAt),
              dda.boletos,
            ),
            trailing: Switch(
              value: dda.enabled,
              onChanged: (on) => controller.setDda(dda, on: on),
            ),
          ),
        _Header(l10n.captureAlwaysOn),
        for (final (icon, title, body, onTap) in always)
          CdListRow(
            key: onTap == null ? null : CaptureSourcesScreen.scanKey,
            icon: icon,
            title: title,
            subtitle: body,
            onTap: onTap,
            trailing: Icon(
              Symbols.check_circle_rounded,
              color: context.money.paid,
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const new(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.xs,
      ),
      child: CdSectionHeader(title: title, small: true),
    );
  }
}

class _MailboxCard extends ConsumerWidget {
  const new({
    required this.mailbox,
    required this.onRead,
    required this.onDisconnect,
  });

  final Mailbox mailbox;
  final VoidCallback onRead;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
    final readDay = CalendarDate.brazilToday(mailbox.lastReadAt);
    final readLabel = readDay == today
        ? l10n.todayAt(brazilTime(mailbox.lastReadAt))
        : readDay.dayMonth;
    Widget stat(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: palette.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.bodyMd.copyWith(
                fontSize: 12,
                color: palette.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
            ),
          ],
        ),
      ),
    );
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CdIconTile(
                Symbols.mail_rounded,
                tone: context.entities.of(EntityTone.personal),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mailbox.address,
                      style: AppTextStyles.titleSm.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                    Text(
                      l10n.captureMailboxGrant(
                        entityKindLabel(l10n, mailbox.owner),
                      ),
                      style: AppTextStyles.bodyMd.copyWith(
                        color: palette.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              stat(l10n.captureLastRead, readLabel),
              const SizedBox(width: AppSpacing.sm),
              stat(
                l10n.captureBillsFound,
                l10n.captureBillsOf(mailbox.billsFound, mailbox.emailsScanned),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              CdButton.tonal(
                key: CaptureSourcesScreen.readKey(mailbox.id),
                dense: true,
                icon: Symbols.sync_rounded,
                label: l10n.captureReadNow,
                onPressed: onRead,
              ),
              CdButton.danger(
                key: CaptureSourcesScreen.disconnectKey(mailbox.id),
                dense: true,
                label: l10n.disconnectButton,
                onPressed: onDisconnect,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
