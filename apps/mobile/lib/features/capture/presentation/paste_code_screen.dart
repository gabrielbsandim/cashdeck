import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/features/capture/domain/bill_draft.dart';
import 'package:cashdeck/features/capture/domain/pasted_code.dart';
import 'package:cashdeck/features/capture/domain/pix_br_code.dart';
import 'package:cashdeck/features/capture/presentation/capture_details_sheet.dart';
import 'package:cashdeck/features/capture/presentation/capture_flow.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Types or pastes a bill's code: a Pix copy-and-paste, a boleto or guide
/// line, or a Pix key. Opens with the shared text, or with the clipboard when
/// it already holds a code.
class PasteCodeScreen extends ConsumerStatefulWidget {
  const new({this.sharedText, super.key});

  static const codeKey = Key('paste-code-field');
  static const clipboardKey = Key('paste-code-clipboard');
  static const bolepixKey = Key('paste-code-bolepix');
  static const amountKey = Key('paste-code-amount');
  static const payeeKey = Key('paste-code-payee');
  static const saveKey = Key('paste-code-save');

  /// Text another app shared in, often a code inside a sentence.
  final String? sharedText;

  @override
  ConsumerState<PasteCodeScreen> createState() => _PasteCodeScreenState();
}

class _PasteCodeScreenState extends ConsumerState<PasteCodeScreen> {
  final _code = TextEditingController();
  final _bolepix = TextEditingController();
  final _payee = TextEditingController();
  late EntityKind _owner = defaultOwner(ref);
  PastedCode? _parsed;
  var _amount = const Money(0);
  CalendarDate? _dueDate;
  var _fromClipboard = false;
  var _sending = false;

  @override
  void initState() {
    super.initState();
    final shared = widget.sharedText;
    if (shared != null) {
      _fill(shared);
      return;
    }
    _paste(onlyCodes: true).ignore();
  }

  @override
  void dispose() {
    _code.dispose();
    _bolepix.dispose();
    _payee.dispose();
    super.dispose();
  }

  /// [onlyCodes] is the silent read on open: the clipboard fills the field
  /// only when it already holds something payable.
  Future<void> _paste({required bool onlyCodes}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted || text == null) return;
    if (onlyCodes && readPastedCode(text) == null) return;
    setState(() {
      _fill(text);
      _fromClipboard = true;
    });
  }

  /// Shows the code itself rather than the sentence around it.
  void _fill(String text) {
    final parsed = readPastedCode(text);
    _code.text = switch (parsed) {
      PastedPixCode(:final code) => code.payload,
      PastedBarcode(:final digits) => digits,
      PastedPixKey(:final value) => value,
      null => text.trim(),
    };
    _parsedChanged(parsed);
  }

  void _typed(String text) => setState(() {
    _fromClipboard = false;
    _parsedChanged(readPastedCode(text));
  });

  void _parsedChanged(PastedCode? parsed) {
    _parsed = parsed;
    final name = switch (parsed) {
      PastedPixCode(:final code) => code.merchantName,
      _ => null,
    };
    if (name == null || _payee.text.isNotEmpty) return;
    _payee.text = name;
  }

  CalendarDate get _today =>
      CalendarDate.brazilToday(ref.read(clockProvider).now());

  /// A key or an open QR carries no amount; the bill needs one, and a due
  /// date that starts at today.
  bool get _needsAmount => switch (_parsed) {
    PastedPixKey() => true,
    PastedPixCode(:final code) => code.amount == null,
    PastedBarcode() || null => false,
  };

  CalendarDate? get _effectiveDueDate =>
      _dueDate ?? (_needsAmount ? _today : null);

  String? get _bolepixPayload {
    final text = _bolepix.text.trim();
    if (text.isEmpty) return null;
    return parsePixBrCode(text)?.payload;
  }

  bool get _bolepixInvalid =>
      _bolepix.text.trim().isNotEmpty && _bolepixPayload == null;

  bool get _ready =>
      _parsed != null &&
      !_bolepixInvalid &&
      (!_needsAmount || _amount.cents > 0);

  Future<void> _save() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final l10n = AppLocalizations.of(context);
    final channel = widget.sharedText == null
        ? CaptureChannel.manual
        : CaptureChannel.share;
    final draft = BillDraft.fromPasted(parsed, _owner, channel: channel)
        .copyWith(
          amount: _amount.cents > 0 ? _amount : null,
          dueDate: _effectiveDueDate,
          payee: _payee.text,
          pixCode: parsed is PastedBarcode ? _bolepixPayload : null,
        );
    final result = await captureAsking(
      context,
      ref,
      draft,
      onSending: (sending) => setState(() => _sending = sending),
    );
    if (!mounted) return;
    switch (result) {
      case null:
        return;
      case Ok(value: BillCaptured(:final duplicate)):
        context.go(AppRoutes.bills);
        await showOutcomeToast(
          context,
          null,
          success: duplicate
              ? l10n.captureDuplicateToast
              : l10n.captureSavedToast,
        );
      case Ok():
        return;
      case Err(:final failure):
        await showOutcomeToast(context, failure, success: '');
    }
  }

  String? _codeError(AppLocalizations l10n) {
    final text = _code.text.trim();
    if (text.isEmpty || _parsed != null) return null;
    if (text.startsWith('000201')) return l10n.pasteCodeBadPix;
    return l10n.pasteCodeUnknown;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final parsed = _parsed;
    final showsAmount = switch (parsed) {
      PastedPixCode(:final code) => code.amount == null,
      PastedBarcode() || PastedPixKey() => true,
      null => false,
    };
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pasteCodeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          CdTextField(
            key: PasteCodeScreen.codeKey,
            controller: _code,
            label: l10n.pasteCodeFieldLabel,
            hintText: l10n.pasteCodeFieldHint,
            monospace: true,
            maxLines: 4,
            valid: parsed != null,
            errorText: _codeError(l10n),
            helperText: _fromClipboard ? l10n.pasteCodeFromClipboard : null,
            onChanged: _typed,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (parsed != null)
                CdStatusBadge(
                  tone: MoneyTone.paid,
                  icon: Symbols.check_rounded,
                  label: pastedKindLabel(l10n, parsed),
                ),
              CdButton.text(
                key: PasteCodeScreen.clipboardKey,
                dense: true,
                icon: Symbols.content_paste_rounded,
                label: l10n.pasteFromClipboard,
                onPressed: () => _paste(onlyCodes: false),
              ),
            ],
          ),
          if (parsed case PastedPixCode(:final code)) ...[
            const SizedBox(height: AppSpacing.md),
            PixCodeDetails(code: code),
          ],
          if (parsed is PastedBarcode) ...[
            const SizedBox(height: AppSpacing.lg),
            CdTextField(
              key: PasteCodeScreen.bolepixKey,
              controller: _bolepix,
              label: l10n.bolepixFieldLabel,
              helperText: l10n.bolepixFieldHelper,
              monospace: true,
              maxLines: 3,
              valid: _bolepixPayload != null,
              errorText: _bolepixInvalid ? l10n.pasteCodeBadPix : null,
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (showsAmount) ...[
            const SizedBox(height: AppSpacing.lg),
            CdCurrencyInput(
              key: PasteCodeScreen.amountKey,
              label: l10n.captureAmountLabel,
              large: false,
              helperText: _needsAmount
                  ? l10n.captureAmountRequired
                  : l10n.captureAmountFromCode,
              onChanged: (amount) => setState(() => _amount = amount),
            ),
          ],
          if (parsed != null) ...[
            const SizedBox(height: AppSpacing.lg),
            DueDateField(
              date: _effectiveDueDate,
              today: _today,
              onChanged: (date) => setState(() => _dueDate = date),
            ),
            const SizedBox(height: AppSpacing.lg),
            CdTextField(
              key: PasteCodeScreen.payeeKey,
              controller: _payee,
              label: l10n.capturePayeeLabel,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.captureOwnerLabel,
            style: AppTextStyles.bodyMd.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CdSegmented<EntityKind>(
            segments: [
              CdSegment(EntityKind.personal, l10n.entityPersonal),
              CdSegment(EntityKind.company, l10n.entityCompany),
            ],
            selected: _owner,
            onChanged: (owner) => setState(() => _owner = owner),
          ),
          const SizedBox(height: AppSpacing.xl),
          CdButton.filled(
            key: PasteCodeScreen.saveKey,
            expand: true,
            loading: _sending,
            icon: Symbols.add_rounded,
            label: l10n.captureSaveButton,
            onPressed: _ready ? _save : null,
          ),
        ],
      ),
    );
  }
}

/// What the BR Code says, so the user checks the recipient before saving.
class PixCodeDetails extends StatelessWidget {
  const new({required this.code, super.key});

  final PixBrCode code;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final amount = code.amount;
    final rows = [
      (l10n.pixInfoRecipient, code.merchantName),
      (l10n.pixInfoCity, code.merchantCity),
      (
        l10n.pixInfoAmount,
        amount == null ? l10n.pixInfoAmountOpen : MoneyFormat.format(amount),
      ),
      (l10n.pixInfoKey, code.pixKey),
    ];
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.pixInfoTitle,
            style: AppTextStyles.titleSm.copyWith(color: palette.onSurface),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (label, value) in rows)
            if (value != null) CdKeyValueRow(label: label, value: Text(value)),
          if (code.url != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.pixInfoDynamic,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String pastedKindLabel(AppLocalizations l10n, PastedCode code) =>
    switch (code) {
      PastedPixCode() => l10n.pasteKindPix,
      PastedBarcode(isTaxGuide: true) => l10n.pasteKindTaxGuide,
      PastedBarcode() => l10n.pasteKindBoleto,
      PastedPixKey(:final type) => l10n.pasteKindPixKey(
        pixKeyTypeLabel(l10n, type),
      ),
    };

String pixKeyTypeLabel(AppLocalizations l10n, PixKeyType type) =>
    switch (type) {
      PixKeyType.cpf => l10n.pixKeyCpf,
      PixKeyType.cnpj => l10n.pixKeyCnpj,
      PixKeyType.email => l10n.pixKeyEmail,
      PixKeyType.phone => l10n.pixKeyPhone,
      PixKeyType.random => l10n.pixKeyRandom,
    };
