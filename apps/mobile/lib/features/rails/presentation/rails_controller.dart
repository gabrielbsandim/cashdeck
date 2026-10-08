import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/rails/domain/payment_rail.dart';
import 'package:cashdeck/features/rails/rails_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

class RailsController extends AsyncNotifier<List<PaymentRail>> {
  new(this.owner);

  final EntityKind owner;

  @override
  Future<List<PaymentRail>> build() async =>
      (await ref.watch(railsRepositoryProvider).rails(owner)).orThrow;

  Future<AppFailure?> authorize(String id) async {
    final result = await ref.read(railsRepositoryProvider).authorize(id);
    switch (result) {
      case Ok(:final value):
        state = AsyncData([
          for (final rail in state.value ?? const <PaymentRail>[])
            if (rail.id == id) value else rail,
        ]);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final AsyncNotifierProviderFamily<
  RailsController,
  List<PaymentRail>,
  EntityKind
>
railsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<RailsController, List<PaymentRail>, EntityKind>(
      RailsController.new,
      retry: noRetry,
    );

final FutureProviderFamily<RailCredentials, String> railCredentialsProvider =
    FutureProvider.autoDispose.family<RailCredentials, String>(
      (ref, id) async =>
          (await ref.watch(railsRepositoryProvider).credentials(id)).orThrow,
      retry: noRetry,
    );
