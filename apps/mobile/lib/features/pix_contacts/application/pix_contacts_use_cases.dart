import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';

final class ListPixContacts {
  const new(this._repository);

  final PixContactsRepository _repository;

  Future<Result<List<PixContact>>> call() => _repository.list();
}

/// Creates a contact, or changes the one with `id`. A draft that breaks a
/// rule never reaches the server.
final class SavePixContact {
  const new(this._repository);

  final PixContactsRepository _repository;

  Future<Result<PixContact>> call(PixContactDraft draft, {String? id}) {
    if (draft.problem != null) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    if (id == null) return _repository.create(draft);
    return _repository.update(id, draft);
  }
}

final class DeletePixContact {
  const new(this._repository);

  final PixContactsRepository _repository;

  Future<Result<void>> call(String id) => _repository.delete(id);
}

final class PreviewPixTransfer {
  const new(this._repository);

  final PixContactsRepository _repository;

  Future<Result<PixPreview>> call(PixPayee payee, EntityKind entity) =>
      _repository.preview(payee, entity);
}

/// Resolves with the bill the Pix became. A zero amount never leaves the app.
final class SendPixTransfer {
  const new(this._repository);

  final PixContactsRepository _repository;

  Future<Result<String>> call(PixPayee payee, EntityKind entity, Money amount) {
    if (amount.cents <= 0) {
      return Future.value(const Err(UnexpectedFailure()));
    }
    return _repository.send(payee, entity, amount);
  }
}
