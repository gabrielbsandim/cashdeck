import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/time/clock.dart';
import 'package:cashdeck/features/pix_contacts/domain/pix_contact.dart';

/// Fictional contacts in memory, with the server's uniqueness rules.
final class FakePixContactsRepository implements PixContactsRepository {
  new(this._clock, {this.latency = const Duration(milliseconds: 300)});

  final Clock _clock;
  final Duration latency;
  var _counter = 0;
  late final Map<String, PixContact> _contacts = {
    for (final contact in _seed()) contact.id: contact,
  };

  List<PixContact> _seed() {
    final now = _clock.now();
    return [
      PixContact(
        id: 'contact-1',
        name: 'Marina Exemplo',
        handle: 'marina',
        pixKey: '+5541999990001',
        pixKeyType: PixKeyType.phone,
        timesPaid: 4,
        lastPaidAt: now.subtract(const Duration(days: 3)),
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      PixContact(
        id: 'contact-2',
        name: 'João Fictício',
        handle: 'joao.ficticio',
        pixKey: 'joao@exemplo.com',
        pixKeyType: PixKeyType.email,
        timesPaid: 1,
        lastPaidAt: now.subtract(const Duration(days: 20)),
        createdAt: now.subtract(const Duration(days: 40)),
      ),
      PixContact(
        id: 'contact-3',
        name: 'Diarista Modelo',
        handle: 'diarista',
        pixKey: '123e4567-e89b-42d3-a456-426614174000',
        pixKeyType: PixKeyType.evp,
        createdAt: now.subtract(const Duration(days: 10)),
      ),
    ];
  }

  static int _byRecency(PixContact a, PixContact b) {
    final paid = (b.lastPaidAt ?? DateTime(0)).compareTo(
      a.lastPaidAt ?? DateTime(0),
    );
    return paid != 0 ? paid : a.name.compareTo(b.name);
  }

  @override
  Future<Result<List<PixContact>>> list({String? search}) async {
    await Future<void>.delayed(latency);
    final found =
        _contacts.values
            .where((contact) => contact.matches(search ?? ''))
            .toList()
          ..sort(_byRecency);
    return Ok(found);
  }

  @override
  Future<Result<PixContact>> create(PixContactDraft draft) =>
      _save(draft, null);

  @override
  Future<Result<PixContact>> update(String id, PixContactDraft draft) =>
      _save(draft, id);

  Future<Result<PixContact>> _save(PixContactDraft draft, String? id) async {
    await Future<void>.delayed(latency);
    final key = draft.normalizedKey;
    if (key == null) {
      return const Err(ValidationFailure('Chave Pix inválida.'));
    }
    final current = id == null ? null : _contacts[id];
    if (id != null && current == null) return const Err(NotFoundFailure());
    final others = _contacts.values.where((contact) => contact.id != id);
    if (others.any((contact) => contact.pixKey == key.$1)) {
      return const Err(ValidationFailure('Essa chave já é de um contato.'));
    }
    final handle = draft.handle.trim();
    if (others.any((contact) => contact.handle == handle)) {
      return const Err(ValidationFailure('Esse @ já está em uso.'));
    }
    final saved = PixContact(
      id: id ?? 'contact-new-${++_counter}',
      name: draft.name.trim(),
      handle: handle,
      pixKey: key.$1,
      pixKeyType: key.$2,
      timesPaid: current?.timesPaid ?? 0,
      lastPaidAt: current?.lastPaidAt,
      createdAt: current?.createdAt ?? _clock.now(),
    );
    _contacts[saved.id] = saved;
    return Ok(saved);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await Future<void>.delayed(latency);
    final removed = _contacts.remove(id);
    if (removed == null) return const Err(NotFoundFailure());
    return const Ok(null);
  }
}
