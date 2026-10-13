import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:cashdeck/features/household/household_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The household as the server stored it; every change saves the whole list.
class HouseholdController extends AsyncNotifier<Household> {
  @override
  Future<Household> build() async =>
      (await ref.watch(loadHouseholdProvider).call()).orThrow;

  Household get _current => state.value ?? const Household([]);

  /// Adds the member typed in the form; null when it worked.
  Future<AppFailure?> add(String name, String cpf) =>
      _save(_current.adding(name, cpf));

  Future<AppFailure?> remove(HouseholdMember member) =>
      _save(_current.removing(member));

  Future<AppFailure?> _save(Household next) async {
    final result = await ref.read(saveHouseholdProvider).call(next);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProvider<HouseholdController, Household>
householdControllerProvider =
    AsyncNotifierProvider.autoDispose<HouseholdController, Household>(
      HouseholdController.new,
      retry: noRetry,
    );
