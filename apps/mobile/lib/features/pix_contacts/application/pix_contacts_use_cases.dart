import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
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
