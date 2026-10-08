import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The entity the app opens on is the one the user left it on.
class EntityScopeController extends Notifier<EntityScope> {
  static const storeKey = 'entity_scope';

  @override
  EntityScope build() {
    final saved = ref.read(keyValueStoreProvider).getString(storeKey);
    return EntityScope.values
            .where((scope) => scope.name == saved)
            .firstOrNull ??
        EntityScope.personal;
  }

  void select(EntityScope scope) {
    if (scope == state) return;
    state = scope;
    ref.read(keyValueStoreProvider).setString(storeKey, scope.name).ignore();
  }
}

final entityScopeProvider =
    NotifierProvider<EntityScopeController, EntityScope>(
      EntityScopeController.new,
    );
