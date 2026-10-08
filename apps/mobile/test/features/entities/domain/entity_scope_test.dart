import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each scope includes its own entity, consolidated includes both', () {
    expect(EntityScope.personal.includes(EntityKind.personal), isTrue);
    expect(EntityScope.personal.includes(EntityKind.company), isFalse);
    expect(EntityScope.company.includes(EntityKind.company), isTrue);
    expect(EntityScope.company.includes(EntityKind.personal), isFalse);
    for (final kind in EntityKind.values) {
      expect(EntityScope.consolidated.includes(kind), isTrue);
    }
  });
}
