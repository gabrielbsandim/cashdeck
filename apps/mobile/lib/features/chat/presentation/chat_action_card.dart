import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/features/chat/domain/chat.dart';
import 'package:cashdeck/features/chat/presentation/chat_controller.dart';
import 'package:cashdeck/features/chat/presentation/chat_labels.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/home/presentation/home_screen.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// What the assistant proposes to do. Nothing runs until the user confirms
/// here; a consolidated thread also asks which entity it is for.
class ChatActionCard extends ConsumerStatefulWidget {
  const new({
    required this.conversation,
    required this.action,
    required this.busy,
    super.key,
  });

  static Key confirmKey(String id) => Key('chat-action-confirm-$id');

  static Key cancelKey(String id) => Key('chat-action-cancel-$id');

  static Key entityKey(EntityKind kind) =>
      Key('chat-action-entity-${kind.name}');

  static const newContactKey = Key('chat-action-new-contact');

  static Key receiptKey(String id) => Key('chat-action-receipt-$id');

  static const verifiedRecipientKey = Key('chat-action-recipient-verified');

  static const unverifiedRecipientKey = Key('chat-action-recipient-unverified');

  final ConversationKey conversation;
  final ChatAction action;
  final bool busy;

  @override
  ConsumerState<ChatActionCard> createState() => _ChatActionCardState();
}

class _ChatActionCardState extends ConsumerState<ChatActionCard> {
  EntityKind? _entity;

  ConversationController get _controller =>
      ref.read(conversationControllerProvider(widget.conversation).notifier);

  /// Money leaves only after the same device check as the confirm sheet.
  Future<bool> _deviceCheck(AppLocalizations l10n) async {
    final tool = widget.action.tool;
    if (!tool.movesMoney) return true;
    final passed = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(chatToolTitle(l10n, tool));
    if (passed || !mounted) return passed;
    CdHaptics.error();
    showCdToast(
      context,
      icon: Symbols.fingerprint_rounded,
      message: l10n.confirmDenied,
    ).ignore();
    return false;
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    if (!await _deviceCheck(l10n) || !mounted) return;
    CdHaptics.confirm();
    final failure = await _controller.confirm(widget.action, entity: _entity);
    if (!mounted) return;
    if (failure == null && widget.action.tool == ChatTool.sendPix) {
      ref.invalidate(pixContactsControllerProvider);
    }
    // Início stays mounted, so reloading it also redraws the home widget.
    if (failure == null && widget.action.tool.movesMoney) {
      HomeScreen.refreshed.forEach(ref.invalidate);
    }
    await showOutcomeToast(context, failure, success: l10n.chatActionDone);
  }

  Future<void> _cancel() async {
    final failure = await _controller.cancel(widget.action);
    if (failure == null || !mounted) return;
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final action = widget.action;
    final (status, tone) = chatActionStatusOf(l10n, action.status);
    final error = action.error;
    final needsChoice = action.isPending && action.needsEntity;
    final ready = !needsChoice || _entity != null;
    final receipt = _receiptBill(action);
    return CdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CdIconTile(chatToolIcon(action.tool)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  chatToolTitle(l10n, action.tool),
                  style: AppTextStyles.titleSm.copyWith(
                    color: palette.onSurface,
                  ),
                ),
              ),
              if (action.tool != ChatTool.showReceipt)
                CdStatusBadge(tone: tone, label: status),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ..._rows(l10n, action.details),
          if (action.details.recipient case final recipient?)
            ..._recipientRows(l10n, recipient),
          if (action.isPending && action.details.newContact == true)
            _Note(
              key: ChatActionCard.newContactKey,
              icon: Symbols.person_add_rounded,
              message: l10n.chatNewContactNote(
                action.details.contactHandle ?? '',
              ),
              colors: ToneColors(
                foreground: palette.onPrimaryContainer,
                background: palette.primaryContainer,
              ),
            ),
          if (error != null)
            Text(
              error,
              style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
            ),
          if (receipt != null) ...[
            const SizedBox(height: AppSpacing.md),
            CdButton.tonal(
              key: ChatActionCard.receiptKey(action.id),
              expand: true,
              icon: Symbols.receipt_long_rounded,
              label: l10n.billReceiptView,
              onPressed: () =>
                  context.push(AppRoutes.billReceipt(receipt)).ignore(),
            ),
          ],
          if (needsChoice) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.chatActionWhichEntity,
              style: AppTextStyles.bodyMd.copyWith(
                color: palette.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            CdSegmented<EntityKind?>(
              segments: [
                for (final kind in EntityKind.values)
                  CdSegment(kind, switch (kind) {
                    EntityKind.personal => l10n.entityPersonal,
                    EntityKind.company => l10n.entityCompany,
                  }, key: ChatActionCard.entityKey(kind)),
              ],
              selected: _entity,
              onChanged: (kind) => setState(() => _entity = kind),
            ),
          ],
          if (action.isPending) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: CdButton.text(
                    key: ChatActionCard.cancelKey(action.id),
                    label: l10n.cancelButton,
                    onPressed: widget.busy ? null : _cancel,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: CdButton.filled(
                    key: ChatActionCard.confirmKey(action.id),
                    label: l10n.chatActionConfirm,
                    loading: widget.busy,
                    onPressed: ready ? _confirm : null,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// A payment the user confirmed here is where they look for its proof.
  String? _receiptBill(ChatAction action) {
    final pays = action.tool.movesMoney || action.tool == ChatTool.showReceipt;
    if (!pays || action.status != ChatActionStatus.confirmed) return null;
    return action.result?.billId;
  }

  List<Widget> _rows(AppLocalizations l10n, ChatActionDetails details) {
    Widget text(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : CdKeyValueRow(label: label, value: Text(value));
    final amount = details.amount;
    final keyType = details.pixKeyType;
    final pixKey = details.pixKey;
    final handle = details.contactHandle;
    return [
      text(l10n.chatDetailPayee, details.payee),
      text(l10n.chatDetailContact, handle == null ? null : '@$handle'),
      if (pixKey != null)
        text(
          l10n.chatDetailPixKey,
          keyType == null
              ? pixKey
              : '${pixKeyTypeLabel(l10n, keyType)} $pixKey',
        ),
      if (amount != null)
        CdKeyValueRow(
          label: l10n.chatDetailAmount,
          value: CdAmount(amount, size: CdAmountSize.sm),
        ),
      text(l10n.chatDetailDueDate, details.dueDate?.display),
      text(l10n.chatDetailFile, details.fileName),
      text(l10n.chatDetailPattern, details.pattern),
      text(l10n.chatDetailCategory, details.category),
      text(l10n.chatDetailPayer, details.payer),
    ];
  }

  /// The holder the Pix directory names is what tells a right key from a
  /// mistyped one, so it is shown apart from the name the user gave.
  List<Widget> _recipientRows(AppLocalizations l10n, ChatRecipient recipient) {
    if (!recipient.verified) {
      return [
        _Note(
          key: ChatActionCard.unverifiedRecipientKey,
          icon: Symbols.warning_rounded,
          message: l10n.chatRecipientUnverified,
          colors: context.tone(MoneyTone.overdue),
        ),
      ];
    }
    final taxId = recipient.taxId;
    final bank = recipient.bank;
    return [
      const SizedBox(height: AppSpacing.sm),
      Align(
        alignment: Alignment.centerLeft,
        child: CdStatusBadge(
          key: ChatActionCard.verifiedRecipientKey,
          tone: MoneyTone.paid,
          icon: Symbols.verified_user_rounded,
          label: l10n.chatRecipientVerified,
        ),
      ),
      CdKeyValueRow(label: l10n.chatDetailHolder, value: Text(recipient.name)),
      if (taxId != null)
        CdKeyValueRow(label: l10n.chatDetailTaxId, value: Text(taxId)),
      if (bank != null)
        CdKeyValueRow(label: l10n.chatDetailBank, value: Text(bank)),
    ];
  }
}

class _Note extends StatelessWidget {
  const new({
    required this.icon,
    required this.message,
    required this.colors,
    super.key,
  });

  final IconData icon;
  final String message;
  final ToneColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMd.copyWith(color: colors.foreground),
            ),
          ),
        ],
      ),
    );
  }
}
