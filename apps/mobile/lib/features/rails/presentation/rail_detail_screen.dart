import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/presentation/bill_labels.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/presentation/rail_labels.dart';
import 'package:cashdeck/features/rails/presentation/rails_controller.dart';
import 'package:cashdeck/features/rails/rails_providers.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// One API rail: its client certificate, API key and a live test.
class RailDetailScreen extends ConsumerStatefulWidget {
  const new({required this.railId, this.rail, super.key});

  static const testKey = Key('rail-test');
  static const removeKey = Key('rail-remove');
  static const replaceKey = Key('rail-replace');
  static const passwordKey = Key('rail-pfx-password');
  static const crtKey = Key('rail-upload-crt');
  static const keyFileKey = Key('rail-upload-key');

  final String railId;
  final PaymentRail? rail;

  @override
  ConsumerState<RailDetailScreen> createState() => _RailDetailScreenState();
}

class _RailDetailScreenState extends ConsumerState<RailDetailScreen> {
  List<RailCheck>? _checks;
  var _testing = false;
  var _pfxPassword = '';

  Future<void> _test() async {
    setState(() => _testing = true);
    final result = await ref.read(railsRepositoryProvider).test(widget.railId);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _checks = switch (result) {
        Ok(:final value) => value,
        Err() => const [],
      };
    });
    ref.invalidate(railCredentialsProvider(widget.railId));
  }

  Future<void> _remove() async {
    final l10n = AppLocalizations.of(context);
    final result = await ref
        .read(railsRepositoryProvider)
        .remove(widget.railId);
    if (!mounted) return;
    final failure = switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
    final rail = widget.rail;
    if (rail != null) ref.invalidate(railsControllerProvider(rail.owner));
    showOutcomeToast(context, failure, success: l10n.railRemovedToast).ignore();
    if (failure == null && context.canPop()) context.pop();
  }

  Future<void> _upload(List<String> extensions) async {
    final l10n = AppLocalizations.of(context);
    final file = await ref.read(fileChooserProvider).choose(extensions);
    if (file == null) return;
    final result = await ref
        .read(railsRepositoryProvider)
        .uploadCredential(widget.railId, file, password: _pfxPassword);
    if (!mounted) return;
    ref.invalidate(railCredentialsProvider(widget.railId));
    await showOutcomeToast(context, switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    }, success: l10n.certificateUploadedToast(file.name));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final rail = widget.rail;
    final credentials = ref.watch(railCredentialsProvider(widget.railId));
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rail == null ? l10n.railDetailTitle : railName(l10n, rail.kind),
            ),
            if (rail != null)
              Text(
                l10n.railOwnerLine(
                  entityKindLabel(l10n, rail.owner),
                  rail.institution,
                ),
                style: AppTextStyles.bodyMd.copyWith(
                  color: palette.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
      body: switch (credentials) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          children: [
            _StatusCard(credentials: value),
            const SizedBox(height: AppSpacing.xl),
            CdSectionHeader(title: l10n.railCertificateTitle, small: true),
            const SizedBox(height: AppSpacing.sm),
            CdCard(
              child: Row(
                children: [
                  Icon(
                    Symbols.workspace_premium_rounded,
                    color: palette.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value.certificateName,
                          style: AppTextStyles.code.copyWith(
                            color: palette.onSurface,
                          ),
                        ),
                        Text(
                          l10n.validUntil(value.certificateValidUntil.display),
                          style: AppTextStyles.bodyMd.copyWith(
                            color: palette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CdButton.text(
                    key: RailDetailScreen.replaceKey,
                    dense: true,
                    label: l10n.replaceButton,
                    onPressed: () => _upload(const ['pfx', 'p12']),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            CdTextField(
              key: RailDetailScreen.passwordKey,
              label: l10n.pfxPasswordLabel,
              secret: true,
              onChanged: (value) => _pfxPassword = value,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.sendSeparately,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
                CdFilterChip(
                  key: RailDetailScreen.crtKey,
                  label: '.crt',
                  icon: Symbols.upload_rounded,
                  onTap: () => _upload(const ['crt', 'pem', 'cer']),
                ),
                CdFilterChip(
                  key: RailDetailScreen.keyFileKey,
                  label: '.key',
                  icon: Symbols.upload_rounded,
                  onTap: () => _upload(const ['key', 'pem']),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            CdSectionHeader(title: l10n.apiKeyLabel, small: true),
            const SizedBox(height: AppSpacing.sm),
            CdTextField(
              label: l10n.apiKeyLabel,
              monospace: true,
              secret: true,
              initialValue: 'ak_live_••••••••${value.apiKeyHint}',
            ),
            const SizedBox(height: AppSpacing.xl),
            CdSectionHeader(
              title: l10n.railTestTitle,
              small: true,
              actionLabel: l10n.runTestButton,
              actionKey: RailDetailScreen.testKey,
              onAction: _testing ? null : _test,
            ),
            if (_testing) const LinearProgressIndicator(),
            for (final check in _checks ?? const <RailCheck>[])
              _CheckRow(check: check),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: CdButton.text(
                key: RailDetailScreen.removeKey,
                icon: Symbols.link_off_rounded,
                label: l10n.removeRailButton,
                onPressed: _remove,
              ),
            ),
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(railCredentialsProvider(widget.railId)),
        ),
        _ => const CdSkeleton(rows: 3),
      },
    );
  }
}

class _StatusCard extends ConsumerWidget {
  const new({required this.credentials});

  final RailCredentials credentials;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final colors = context.tone(MoneyTone.paid);
    final tested = credentials.lastTestAt;
    return CdCard(
      tone: colors,
      child: Row(
        children: [
          Icon(Symbols.check_circle_rounded, fill: 1, color: colors.foreground),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.railActive,
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                if (tested != null)
                  Text(
                    l10n.railLastTest(brazilTime(tested)),
                    style: AppTextStyles.bodyMd.copyWith(
                      color: palette.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const new({required this.check});

  final RailCheck check;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final money = context.money;
    final millis = check.millis;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            check.passed ? Symbols.check_circle_rounded : Symbols.error_rounded,
            size: 20,
            color: check.passed ? money.paid : money.failed,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              railCheckLabel(l10n, check.kind),
              style: AppTextStyles.bodyMd.copyWith(color: palette.onSurface),
            ),
          ),
          Text(
            millis == null ? '-' : l10n.millis(millis),
            style: AppTextStyles.code.copyWith(
              fontSize: 13,
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
