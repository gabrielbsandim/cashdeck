import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/recap/domain/monthly_recap.dart';
import 'package:cashdeck/features/recap/recap_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// A month as the route names it (`2026-09`), the entity it covers and the
/// language of its story.
typedef RecapRequest = ({String month, EntityKind entity, String locale});

final FutureProviderFamily<MonthlyRecap, RecapRequest> monthlyRecapProvider =
    FutureProvider.autoDispose.family<MonthlyRecap, RecapRequest>((
      ref,
      request,
    ) async {
      final today = CalendarDate.brazilToday(ref.watch(clockProvider).now());
      return (await ref
              .watch(getMonthlyRecapProvider)
              .call(
                request.month,
                today: today,
                locale: request.locale,
                entity: request.entity,
              ))
          .orThrow;
    }, retry: noRetry);
