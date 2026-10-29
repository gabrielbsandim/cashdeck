import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_search_field.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/capture/presentation/capture_flow.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/pix_contacts_providers.dart';
import 'package:cashdeck/features/pix_contacts/presentation/contact_avatar.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// A Pix from the Pay tab: pick a saved contact or type a new key, review the
/// holder the central bank names, then send after the device check.
class SendPixScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const searchKey = Key('send-pix-search');
  static const newKeyKey = Key('send-pix-new-key');
  static const nameKey = Key('send-pix-name');
  static const pixKeyKey = Key('send-pix-key');
  static const reviewKey = Key('send-pix-review');
  static const problemKey = Key('send-pix-problem');

  static Key contactKey(String id) => Key('send-pix-contact-$id');

  static Key kindKey(PixKeyKind kind) => Key('send-pix-kind-${kind.name}');

  static Key entityKey(EntityKind kind) => Key('send-pix-entity-${kind.name}');

  @override
  ConsumerState<SendPixScreen> createState() => _SendPixScreenState();
}

class _SendPixScreenState extends ConsumerState<SendPixScreen> {
  final _search = TextEditingController();
  final _name = TextEditingController();
  final _key = TextEditingController();
  var _query = '';
  String? _contactId;
  var _typing = false;
  PixKeyKind _kind = PixKeyKind.phone;
  Money _amount = const Money(0);
  late EntityKind _entity = defaultOwner(ref);
  var _busy = false;
  String? _problem;

  @override
  void dispose() {
    _search.dispose();
    _name.dispose();
    _key.dispose();
    super.dispose();
  }

  PixContactDraft get _draft => PixContactDraft(
    name: _name.text,
    handle: '',
    keyKind: _kind,
    pixKey: _key.text,
  );

  /// Null while the form still misses who gets the money.
  PixPayee? get _payee {
    final contactId = _contactId;
    if (!_typing) return contactId == null ? null : PixPayee.contact(contactId);
    final draft = _draft;
    if (draft.name.trim().isEmpty || draft.normalizedKey == null) return null;
    return PixPayee.newKey(draft);
  }

  void _choose(String contactId) => setState(() {
    _contactId = contactId;
    _typing = false;
    _problem = null;
  });

  Future<void> _review() async {
    final l10n = AppLocalizations.of(context);
    final payee = _payee;
    final problem = switch ((payee, _amount.cents)) {
      (null, _) => l10n.sendPixChooseSomeone,
      (_, <= 0) => l10n.sendPixAmountMissing,
      _ => null,
    };
    setState(() => _problem = problem);
    if (payee == null || problem != null) return;
    setState(() => _busy = true);
    final preview = await ref
        .read(previewPixTransferProvider)
        .call(payee, _entity);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (preview) {
      case Err(:final failure):
        setState(() => _problem = failure.userMessage(l10n));
      case Ok(:final value):
        await _confirm(l10n, payee, value);
    }
  }

  Future<void> _confirm(
    AppLocalizations l10n,
    PixPayee payee,
    PixPreview preview,
  ) async {
    final recipient = preview.recipient;
    final hide = ref.read(hideAmountsProvider);
    final confirmed = await showCdConfirmSheet(
      context,
      title: l10n.sendPixReviewTitle(preview.name),
      reason: recipient.verified ? l10n.chatRecipientVerified : null,
      reasonTone: MoneyTone.paid,
      reasonIcon: Symbols.verified_user_rounded,
      warning: recipient.verified ? null : l10n.chatRecipientUnverified,
      rows: [
        CdConfirmRow(l10n.chatDetailHolder, recipient.name),
        if (recipient.taxId case final taxId?)
          CdConfirmRow(l10n.chatDetailTaxId, taxId),
        if (recipient.bank case final bank?)
          CdConfirmRow(l10n.chatDetailBank, bank),
        CdConfirmRow(
          l10n.chatDetailPixKey,
          pixKeyLine(l10n, preview.pixKeyType, preview.pixKey),
        ),
        CdConfirmRow(
          l10n.confirmRowAmount,
          MoneyFormat.format(_amount, hide: hide),
        ),
        CdConfirmRow(l10n.sendPixFrom, _entityLabel(l10n, _entity)),
      ],
      confirmLabel: l10n.chatToolSendPix,
    );
    if (confirmed != true || !mounted) return;
    await _send(l10n, payee);
  }

  Future<void> _send(AppLocalizations l10n, PixPayee payee) async {
    setState(() => _busy = true);
    final sent = await ref
        .read(sendPixTransferProvider)
        .call(payee, _entity, _amount);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (sent) {
      case Err(:final failure):
        CdHaptics.error();
        setState(() => _problem = failure.userMessage(l10n));
      case Ok(value: final billId):
        CdHaptics.confirm();
        ref
          ..invalidate(pixContactsControllerProvider)
          ..invalidate(billsControllerProvider);
        HomeScreen.refreshed.forEach(ref.invalidate);
        showCdToast(
          context,
          icon: Symbols.check_circle_rounded,
          message: l10n.sendPixDone,
        ).ignore();
        context.pushReplacement(AppRoutes.bill(billId));
    }
  }

  static String _entityLabel(AppLocalizations l10n, EntityKind kind) =>
      switch (kind) {
        EntityKind.personal => l10n.entityPersonal,
        EntityKind.company => l10n.entityCompany,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contacts = ref.watch(pixContactsControllerProvider);
    final problem = _problem;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.chatToolSendPix)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          AppSpacing.xxl,
        ),
        children: [
          _Label(l10n.sendPixTo),
          CdSearchField(
            key: SendPixScreen.searchKey,
            controller: _search,
            hint: l10n.pixContactsSearch,
            onChanged: (query) => setState(() => _query = query),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...switch (contacts) {
            AsyncData(:final value) => _contacts(l10n, value),
            AsyncError(:final error) => [
              CdErrorState(
                failure: failureOf(error),
                onRetry: () => ref.invalidate(pixContactsControllerProvider),
              ),
            ],
            _ => [const CdSkeletonRows(count: 3)],
          },
          CdListRow(
            key: SendPixScreen.newKeyKey,
            icon: Symbols.add_rounded,
            title: l10n.sendPixNewKey,
            padding: EdgeInsets.zero,
            trailing: _typing ? const _Check() : null,
            onTap: () => setState(() {
              _typing = true;
              _contactId = null;
              _problem = null;
            }),
          ),
          if (_typing) ..._newKeyFields(l10n),
          const SizedBox(height: AppSpacing.lg),
          CdCurrencyInput(
            label: l10n.chatDetailAmount,
            onChanged: (amount) => setState(() => _amount = amount),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Label(l10n.sendPixFrom),
          CdSegmented<EntityKind>(
            segments: [
              for (final kind in EntityKind.values)
                CdSegment(
                  kind,
                  _entityLabel(l10n, kind),
                  key: SendPixScreen.entityKey(kind),
                ),
            ],
            selected: _entity,
            onChanged: (kind) => setState(() => _entity = kind),
          ),
          if (problem != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              problem,
              key: SendPixScreen.problemKey,
              style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          CdButton.filled(
            key: SendPixScreen.reviewKey,
            expand: true,
            label: l10n.sendPixReview,
            loading: _busy,
            onPressed: _review,
          ),
        ],
      ),
    );
  }

  List<Widget> _contacts(AppLocalizations l10n, List<PixContact> contacts) => [
    for (final contact in contacts.where((c) => c.matches(_query)))
      CdListRow(
        key: SendPixScreen.contactKey(contact.id),
        leading: ContactAvatar(contact: contact),
        title: contact.name,
        subtitle: pixKeyLine(l10n, contact.pixKeyType, contact.pixKey),
        padding: EdgeInsets.zero,
        trailing: !_typing && _contactId == contact.id ? const _Check() : null,
        onTap: () => _choose(contact.id),
      ),
  ];

  List<Widget> _newKeyFields(AppLocalizations l10n) => [
    const SizedBox(height: AppSpacing.sm),
    CdTextField(
      key: SendPixScreen.nameKey,
      controller: _name,
      label: l10n.pixContactName,
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {}),
    ),
    const SizedBox(height: AppSpacing.md),
    CdSegmented<PixKeyKind>(
      segments: [
        for (final kind in PixKeyKind.values)
          CdSegment(
            kind,
            pixKeyKindLabel(l10n, kind),
            key: SendPixScreen.kindKey(kind),
          ),
      ],
      selected: _kind,
      onChanged: (kind) => setState(() => _kind = kind),
    ),
    const SizedBox(height: AppSpacing.md),
    CdTextField(
      key: SendPixScreen.pixKeyKey,
      controller: _key,
      label: l10n.pixContactKey,
      suffix: Icon(pixKeyKindIcon(_kind)),
      onChanged: (_) => setState(() {}),
    ),
  ];
}

class _Label extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Text(
      text,
      style: AppTextStyles.labelLg.copyWith(
        color: context.palette.onSurfaceVariant,
      ),
    ),
  );
}

class _Check extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) =>
      Icon(Symbols.check_circle_rounded, color: context.palette.primary);
}
