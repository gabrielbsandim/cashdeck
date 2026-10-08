import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EntityScopeController extends Notifier<EntityScope> {
  @override
  EntityScope build() => EntityScope.personal;

  void select(EntityScope scope) {
    if (scope == state) return;
    state = scope;
  }
}

final entityScopeProvider =
    NotifierProvider<EntityScopeController, EntityScope>(
      EntityScopeController.new,
    );
