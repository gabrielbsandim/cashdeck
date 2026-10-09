import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:cashdeck/features/alerts/presentation/alert_labels.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One switch per alert type: off mutes its push, the inbox still keeps it.
class AlertSettingsScreen extends ConsumerWidget {
  const new({super.key});

  static Key switchKey(AlertKind kind) => Key('alert-setting-${kind.wire}');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(alertSettingsControllerProvider);
    final controller = ref.read(alertSettingsControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.alertSettingsTitle)),
      body: switch (settings) {
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.screenGutter),
              child: Text(
                l10n.alertSettingsHint,
                style: AppTextStyles.bodyMd.copyWith(
                  color: context.palette.onSurfaceVariant,
                ),
              ),
            ),
            for (final MapEntry(key: kind, value: muted) in value.entries)
              CdListRow(
                icon: alertKindIcon(kind),
                title: alertKindLabel(l10n, kind),
                trailing: Switch(
                  key: switchKey(kind),
                  value: !muted,
                  onChanged: (enabled) async {
                    final failure = await controller.setMuted(
                      kind,
                      muted: !enabled,
                    );
                    if (failure == null || !context.mounted) return;
                    await showCdToast(
                      context,
                      message: failure.userMessage(l10n),
                    );
                  },
                ),
              ),
          ],
        ),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(alertSettingsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}
