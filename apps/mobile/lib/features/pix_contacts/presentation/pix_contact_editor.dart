import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

enum _EditorOutcome { saved, delete }

/// Adds a contact, or edits [contact]; deleting asks once more in its own
/// sheet.
Future<void> showPixContactEditor(
  BuildContext context, {
  PixContact? contact,
}) async {
  final l10n = AppLocalizations.of(context);
  final outcome = await showCdBottomSheet<_EditorOutcome>(
    context,
    title: contact == null ? l10n.pixContactsAdd : l10n.pixContactsEdit,
    builder: (_) => PixContactEditor(contact: contact),
  );
  if (!context.mounted || outcome == null) return;
  switch (outcome) {
    case _EditorOutcome.saved:
      await showCdToast(
        context,
        icon: Symbols.task_alt_rounded,
        message: l10n.pixContactSaved,
      );
    case _EditorOutcome.delete:
      await _confirmDelete(context, contact!);
  }
}

Future<void> _confirmDelete(BuildContext context, PixContact contact) async {
  final l10n = AppLocalizations.of(context);
  final deleted = await showCdBottomSheet<bool>(
    context,
    title: l10n.pixContactDeleteTitle(contact.name),
    builder: (_) => _DeleteSheet(contact: contact),
  );
  if (deleted != true || !context.mounted) return;
  await showCdToast(
    context,
    icon: Symbols.task_alt_rounded,
    message: l10n.pixContactDeleted,
  );
}

class PixContactEditor extends ConsumerStatefulWidget {
  const new({this.contact, super.key});

  static const nameKey = Key('pix-contact-name');
  static const handleKey = Key('pix-contact-handle');
  static const pixKeyKey = Key('pix-contact-key');
  static const saveKey = Key('pix-contact-save');
  static const deleteKey = Key('pix-contact-delete');
  static const errorKey = Key('pix-contact-error');

  static Key kindKey(PixKeyKind kind) => Key('pix-contact-kind-${kind.name}');

  final PixContact? contact;

  @override
  ConsumerState<PixContactEditor> createState() => _PixContactEditorState();
}

final _handleChars = FilteringTextInputFormatter.allow(RegExp('[a-z0-9._]'));
final _lowercase = TextInputFormatter.withFunction(
  (_, value) => value.copyWith(text: value.text.toLowerCase()),
);

class _PixContactEditorState extends ConsumerState<PixContactEditor> {
  late final PixContact? _original = widget.contact;
  late final _name = TextEditingController(text: _original?.name);
  late final _handle = TextEditingController(text: _original?.handle);
  late final _key = TextEditingController(text: _original?.pixKey);
  late PixKeyKind _kind = switch (_original) {
    final PixContact contact => kindOf(contact.pixKeyType),
    null => PixKeyKind.phone,
  };
  late var _handleTouched = _original != null;
  var _submitted = false;
  var _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _key.dispose();
    super.dispose();
  }

  PixContactDraft get _draft => PixContactDraft(
    name: _name.text,
    handle: _handle.text,
    keyKind: _kind,
    pixKey: _key.text,
  );

  Iterable<PixContact> get _others =>
      (ref.read(pixContactsControllerProvider).value ?? const <PixContact>[])
          .where((contact) => contact.id != _original?.id);

  void _onName(String name) {
    if (_handleTouched) return;
    _handle.text = handleFromName(name);
    setState(() {});
  }

  String? _nameError(AppLocalizations l10n) {
    if (!_submitted || _name.text.trim().isNotEmpty) return null;
    return l10n.pixContactNameMissing;
  }

  String? _keyError(AppLocalizations l10n) {
    if (!_submitted) return null;
    final key = _draft.normalizedKey;
    if (key == null) return l10n.pixContactKeyInvalid;
    final taken = _others.any((contact) => contact.pixKey == key.$1);
    return taken ? l10n.pixContactKeyTaken : null;
  }

  String? _handleError(AppLocalizations l10n) {
    if (!_submitted) return null;
    final handle = _handle.text.trim();
    if (!isValidHandle(handle)) return l10n.pixContactHandleInvalid;
    final taken = _others.any((contact) => contact.handle == handle);
    return taken ? l10n.pixContactHandleTaken : null;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _submitted = true;
      _serverError = null;
    });
    final blocked = [
      _nameError(l10n),
      _keyError(l10n),
      _handleError(l10n),
    ].any((error) => error != null);
    if (blocked) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(pixContactsControllerProvider.notifier)
        .save(_draft, id: _original?.id);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(_EditorOutcome.saved);
      return;
    }
    setState(() {
      _saving = false;
      _serverError = failure.userMessage(l10n);
    });
  }

  TextInputType get _keyboard => switch (_kind) {
    PixKeyKind.taxId => TextInputType.number,
    PixKeyKind.phone => TextInputType.phone,
    PixKeyKind.email => TextInputType.emailAddress,
    PixKeyKind.evp => TextInputType.visiblePassword,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final serverError = _serverError;
    final handle = _handle.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CdTextField(
          key: PixContactEditor.nameKey,
          controller: _name,
          label: l10n.pixContactName,
          errorText: _nameError(l10n),
          textInputAction: TextInputAction.next,
          onChanged: _onName,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          l10n.pixContactKeyKind,
          style: AppTextStyles.labelLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        CdSegmented<PixKeyKind>(
          segments: [
            for (final kind in PixKeyKind.values)
              CdSegment(
                kind,
                pixKeyKindLabel(l10n, kind),
                key: PixContactEditor.kindKey(kind),
              ),
          ],
          selected: _kind,
          onChanged: (kind) => setState(() => _kind = kind),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: PixContactEditor.pixKeyKey,
          controller: _key,
          label: l10n.pixContactKey,
          keyboardType: _keyboard,
          errorText: _keyError(l10n),
          suffix: Icon(pixKeyKindIcon(_kind)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        CdTextField(
          key: PixContactEditor.handleKey,
          controller: _handle,
          label: l10n.pixContactHandle,
          errorText: _handleError(l10n),
          helperText: handle.isEmpty ? null : l10n.pixContactHandleHelp(handle),
          inputFormatters: [_lowercase, _handleChars],
          onChanged: (_) => setState(() => _handleTouched = true),
        ),
        if (serverError != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            serverError,
            key: PixContactEditor.errorKey,
            style: AppTextStyles.bodyMd.copyWith(color: context.money.failed),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        CdButton.filled(
          key: PixContactEditor.saveKey,
          expand: true,
          label: l10n.pixContactSave,
          loading: _saving,
          onPressed: _save,
        ),
        if (_original != null) ...[
          const SizedBox(height: AppSpacing.sm),
          CdButton.text(
            key: PixContactEditor.deleteKey,
            expand: true,
            icon: Symbols.delete_rounded,
            label: l10n.pixContactDelete,
            onPressed: () => Navigator.of(context).pop(_EditorOutcome.delete),
          ),
        ],
      ],
    );
  }
}

class _DeleteSheet extends ConsumerStatefulWidget {
  const new({required this.contact});

  final PixContact contact;

  @override
  ConsumerState<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends ConsumerState<_DeleteSheet> {
  var _deleting = false;

  Future<void> _delete() async {
    CdHaptics.warning();
    setState(() => _deleting = true);
    final navigator = Navigator.of(context);
    final failure = await ref
        .read(pixContactsControllerProvider.notifier)
        .delete(widget.contact);
    if (!mounted) return;
    if (failure == null) {
      navigator.pop(true);
      return;
    }
    setState(() => _deleting = false);
    await showOutcomeToast(context, failure, success: '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.pixContactDeleteMessage(widget.contact.handle),
          style: AppTextStyles.bodyLg.copyWith(
            color: context.palette.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        CdButton.danger(
          key: PixContactEditor.deleteKey,
          expand: true,
          label: l10n.pixContactDelete,
          loading: _deleting,
          onPressed: _delete,
        ),
        const SizedBox(height: AppSpacing.sm),
        CdButton.text(
          expand: true,
          label: l10n.cancelButton,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
