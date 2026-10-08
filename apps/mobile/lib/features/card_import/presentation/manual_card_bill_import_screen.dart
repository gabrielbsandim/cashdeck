import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_checkbox_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_stepper.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/card_import/card_import_providers.dart';
import 'package:cashdeck/features/card_import/domain/card_statement.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

final FutureProvider<CardStatement> cardStatementProvider =
    FutureProvider.autoDispose<CardStatement>(
      (ref) async =>
          (await ref.watch(cardImportRepositoryProvider).statement()).orThrow,
      retry: noRetry,
    );

/// Reviews a card statement read from its PDF and turns it into a bill.
class ManualCardBillImportScreen extends ConsumerWidget {
  const new({super.key});

  static const createKey = Key('card-create-bill');

  static Key lineKey(String id) => Key('card-line-$id');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final statement = ref.watch(cardStatementProvider);
    final value = statement.value;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: const Icon(Symbols.close_rounded),
          onPressed: () => context.pop(),
        ),
        title: value == null
            ? Text(l10n.cardImportMenu)
            : _Title(statement: value),
      ),
      body: switch (statement) {
        AsyncData(:final value) => _Review(statement: value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(cardStatementProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }
}

class _Title extends StatelessWidget {
  const new({required this.statement});

  final CardStatement statement;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.cardImportTitle(statement.card)),
        Text(
          l10n.cardImportIssuer(statement.issuer),
          style: AppTextStyles.bodyMd.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Review extends ConsumerStatefulWidget {
  const new({required this.statement});

  final CardStatement statement;

  @override
  ConsumerState<_Review> createState() => _ReviewState();
}

class _ReviewState extends ConsumerState<_Review> {
  late Set<String> _selected = {
    for (final line in widget.statement.lines) line.id,
  };
  var _creating = false;

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _creating = true);
    final result = await ref
        .read(cardImportRepositoryProvider)
        .createBill(widget.statement, _selected);
    if (!mounted) return;
    setState(() => _creating = false);
    final failure = switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
    showOutcomeToast(
      context,
      failure,
      success: l10n.cardBillCreatedToast,
    ).ignore();
    if (failure == null && context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final hide = ref.watch(hideAmountsProvider);
    final statement = widget.statement;
    final totals = StatementTotals.of(statement, _selected);
    final secondary = AppTextStyles.bodyMd.copyWith(
      color: palette.onSurfaceVariant,
    );
    final rate = (statement.rate / 10000).toStringAsFixed(4);
    final iof = (statement.iofBps / 100).toStringAsFixed(1);
    Widget fact(String label, String value) => Expanded(
      child: CdCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: secondary.copyWith(fontSize: 12)),
            Text(
              value,
              style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
            ),
          ],
        ),
      ),
    );
    Widget total(String label, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? AppTextStyles.titleSm.copyWith(color: palette.onSurface)
                  : secondary,
            ),
          ),
          Text(
            value,
            style: (strong ? AppTextStyles.amountSm : AppTextStyles.bodyMd)
                .copyWith(
                  color: palette.onSurface,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        CdStepper(
          steps: [l10n.cardStepSend, l10n.cardStepReview, l10n.cardStepCreate],
          current: 1,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            fact(l10n.cardClosing, statement.closing.dayMonth),
            const SizedBox(width: AppSpacing.sm),
            fact(l10n.cardRate, rate.replaceAll('.', ',')),
            const SizedBox(width: AppSpacing.sm),
            fact(l10n.cardIof, '${iof.replaceAll('.', ',')}%'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final line in statement.lines)
          CdCheckboxRow(
            key: ManualCardBillImportScreen.lineKey(line.id),
            title: line.merchant,
            value: _selected.contains(line.id),
            subtitle: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  line.date.dayMonth,
                  style: AppTextStyles.code.copyWith(
                    fontSize: 12,
                    color: palette.onSurfaceVariant,
                  ),
                ),
                if (line.needsReview) ...[
                  CdStatusBadge(
                    tone: MoneyTone.pending,
                    label: l10n.cardLineReview,
                    icon: Symbols.visibility_rounded,
                  ),
                ],
              ],
            ),
            trailing: CdAmount(
              line.amount,
              size: CdAmountSize.row,
              converted: statement.brlOf(line.amount),
            ),
            onChanged: (on) => setState(() {
              _selected = on
                  ? {..._selected, line.id}
                  : ({..._selected}..remove(line.id));
            }),
          ),
        const SizedBox(height: AppSpacing.md),
        CdCard(
          child: Column(
            children: [
              total(
                l10n.cardSubtotal(
                  MoneyFormat.format(totals.foreign, hide: hide),
                ),
                MoneyFormat.format(totals.subtotal, hide: hide),
              ),
              total(
                l10n.cardIofLine('${iof.replaceAll('.', ',')}%'),
                MoneyFormat.format(totals.iof, hide: hide),
              ),
              const Divider(height: AppSpacing.lg),
              total(
                l10n.cardTotal,
                MoneyFormat.format(totals.total, hide: hide),
                strong: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(l10n.cardBecomesBill(statement.due.dayMonth), style: secondary),
        const SizedBox(height: AppSpacing.md),
        CdButton.filled(
          key: ManualCardBillImportScreen.createKey,
          expand: true,
          loading: _creating,
          label: l10n.cardCreateBillButton,
          onPressed: _selected.isEmpty ? null : _create,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.cardReminder(statement.closing.day),
          textAlign: TextAlign.center,
          style: secondary,
        ),
      ],
    );
  }
}
