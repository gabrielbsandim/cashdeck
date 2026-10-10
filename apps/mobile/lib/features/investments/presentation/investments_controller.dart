import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/features/entities/presentation/entity_scope_controller.dart';
import 'package:cashdeck/features/investments/domain/investments.dart';
import 'package:cashdeck/features/investments/investments_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

final FutureProvider<Investments> investmentsProvider =
    FutureProvider.autoDispose<Investments>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      return (await ref.watch(loadInvestmentsProvider)(scope)).orThrow;
    }, retry: noRetry);

class PerformancePeriodController extends Notifier<PerformancePeriod> {
  @override
  PerformancePeriod build() => PerformancePeriod.month;

  PerformancePeriod get period => state;

  set period(PerformancePeriod period) => state = period;
}

/// One window for the home card, the investments screen and each position.
final performancePeriodProvider =
    NotifierProvider<PerformancePeriodController, PerformancePeriod>(
      PerformancePeriodController.new,
    );

final FutureProvider<InvestmentPerformance> investmentPerformanceProvider =
    FutureProvider.autoDispose<InvestmentPerformance>((ref) async {
      final scope = ref.watch(entityScopeProvider);
      final period = ref.watch(performancePeriodProvider);
      return (await ref.watch(loadInvestmentPerformanceProvider)(
        scope,
        period,
      )).orThrow;
    }, retry: noRetry);

final FutureProviderFamily<InvestmentDetail, String> investmentDetailProvider =
    FutureProvider.autoDispose.family<InvestmentDetail, String>((
      ref,
      id,
    ) async {
      final period = ref.watch(performancePeriodProvider);
      return (await ref.watch(loadInvestmentDetailProvider)(
        id,
        period,
      )).orThrow;
    }, retry: noRetry);
