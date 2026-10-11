import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/inputs/cd_search_field.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/presentation/contact_avatar.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_editor.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contact_labels.dart';
import 'package:cashdeck/features/pix_contacts/presentation/pix_contacts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The people the chat can send a Pix to by name or @handle.
class PixContactsScreen extends ConsumerStatefulWidget {
  const new({super.key});

  static const addKey = Key('pix-contacts-add');
  static const searchKey = Key('pix-contacts-search');

  static Key rowKey(String id) => Key('pix-contact-$id');

  @override
  ConsumerState<PixContactsScreen> createState() => _PixContactsScreenState();
}

class _PixContactsScreenState extends ConsumerState<PixContactsScreen> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final contacts = ref.watch(pixContactsControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pixContactsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        key: PixContactsScreen.addKey,
        onPressed: () => showPixContactEditor(context),
        icon: const Icon(Symbols.person_add_rounded),
        label: Text(l10n.pixContactsAdd),
      ),
      body: switch (contacts) {
        AsyncData(:final value) when value.isEmpty => CdEmptyState(
          icon: Symbols.contacts_rounded,
          title: l10n.pixContactsEmptyTitle,
          message: l10n.pixContactsEmptyMessage,
        ),
        AsyncData(:final value) => _list(l10n, value),
        AsyncError(:final error) => CdErrorState(
          failure: failureOf(error),
          onRetry: () => ref.invalidate(pixContactsControllerProvider),
        ),
        _ => const CdSkeleton(),
      },
    );
  }

  Widget _list(AppLocalizations l10n, List<PixContact> contacts) {
    final shown = contacts.where((contact) => contact.matches(_query)).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.sm,
          ),
          child: CdSearchField(
            key: PixContactsScreen.searchKey,
            controller: _search,
            hint: l10n.pixContactsSearch,
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Text(l10n.pixContactsNoMatch, textAlign: TextAlign.center),
          ),
        for (final contact in shown)
          CdListRow(
            key: PixContactsScreen.rowKey(contact.id),
            leading: ContactAvatar(contact: contact),
            title: contact.name,
            subtitle:
                '${contact.mention} · '
                '${pixKeyLine(l10n, contact.pixKeyType, contact.pixKey)}\n'
                '${paidLine(l10n, contact)}',
            chevron: true,
            onTap: () => showPixContactEditor(context, contact: contact),
          ),
      ],
    );
  }
}
