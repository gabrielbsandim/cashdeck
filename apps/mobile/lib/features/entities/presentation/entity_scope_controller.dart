import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The entity the app opens on is the one the user left it on.
class EntityScopeController extends Notifier<EntityScope> {
  static const storeKey = 'entity_scope';

  @override
  EntityScope build() => savedEntityScope(ref.read(keyValueStoreProvider));

  void select(EntityScope scope) {
    if (scope == state) return;
    state = scope;
    ref.read(keyValueStoreProvider).setString(storeKey, scope.name).ignore();
  }
}

/// The scope [EntityScopeController] saved in [store], personal until one is.
EntityScope savedEntityScope(KeyValueStore store) {
  final saved = store.getString(EntityScopeController.storeKey);
  return EntityScope.values.where((scope) => scope.name == saved).firstOrNull ??
      EntityScope.personal;
}

final entityScopeProvider =
    NotifierProvider<EntityScopeController, EntityScope>(
      EntityScopeController.new,
    );
