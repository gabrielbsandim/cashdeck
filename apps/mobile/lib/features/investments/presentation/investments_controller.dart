import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final FutureProvider<Investments> investmentsProvider =
    FutureProvider.autoDispose<Investments>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      return (await ref.watch(loadInvestmentsProvider)(scope)).orThrow;
    }, retry: noRetry);
