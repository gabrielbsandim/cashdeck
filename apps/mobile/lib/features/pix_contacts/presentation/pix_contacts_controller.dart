import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';
import 'package:cashdeck/features/pix_contacts/pix_contacts_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PixContactsController extends AsyncNotifier<List<PixContact>> {
  @override
  Future<List<PixContact>> build() async =>
      (await ref.watch(listPixContactsProvider).call()).orThrow;

  /// Creates the contact, or changes the one with `id`; null when it worked.
  Future<AppFailure?> save(PixContactDraft draft, {String? id}) async {
    final result = await ref.read(savePixContactProvider).call(draft, id: id);
    switch (result) {
      case Ok(:final value):
        final others = (state.value ?? const <PixContact>[]).where(
          (contact) => contact.id != value.id,
        );
        state = AsyncData([...others, value]);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> delete(PixContact contact) async {
    final result = await ref.read(deletePixContactProvider).call(contact.id);
    switch (result) {
      case Ok():
        state = AsyncData([
          for (final kept in state.value ?? const <PixContact>[])
            if (kept.id != contact.id) kept,
        ]);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProvider<PixContactsController, List<PixContact>>
pixContactsControllerProvider =
    AsyncNotifierProvider.autoDispose<PixContactsController, List<PixContact>>(
      PixContactsController.new,
      retry: noRetry,
    );
