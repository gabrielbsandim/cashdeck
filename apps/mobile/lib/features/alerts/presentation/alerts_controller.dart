import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/alerts/alerts_providers.dart';
import 'package:cashdeck/features/alerts/domain/app_alert.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AlertsController extends AsyncNotifier<AlertPage> {
  @override
  Future<AlertPage> build() async =>
      (await ref.watch(alertsRepositoryProvider).list()).orThrow;

  Future<AppFailure?> loadMore() async {
    final current = state.value;
    final cursor = current?.nextCursor;
    if (current == null || cursor == null) return null;
    final result = await ref
        .read(alertsRepositoryProvider)
        .list(cursor: cursor);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(
          AlertPage(
            items: [...current.items, ...value.items],
            nextCursor: value.nextCursor,
          ),
        );
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> markRead(String id) async {
    final result = await ref.read(alertsRepositoryProvider).markRead(id);
    switch (result) {
      case Ok(:final value):
        _replace((alert) => alert.id == id ? value : alert);
        ref.invalidate(unreadAlertsProvider);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  Future<AppFailure?> markAllRead(DateTime now) async {
    final result = await ref.read(alertsRepositoryProvider).markAllRead();
    switch (result) {
      case Ok():
        _replace((alert) => alert.read(now));
        ref.invalidate(unreadAlertsProvider);
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  void _replace(AppAlert Function(AppAlert alert) update) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      AlertPage(
        items: current.items.map(update).toList(),
        nextCursor: current.nextCursor,
      ),
    );
  }
}

final alertsControllerProvider =
    AsyncNotifierProvider<AlertsController, AlertPage>(
      AlertsController.new,
      retry: noRetry,
    );

/// The bell badge; a failed count reads as nothing unread.
final unreadAlertsProvider = FutureProvider<int>((ref) async {
  final result = await ref.watch(alertsRepositoryProvider).unreadCount();
  return switch (result) {
    Ok(:final value) => value,
    Err() => 0,
  };
});

class AlertSettingsController extends AsyncNotifier<Map<AlertKind, bool>> {
  @override
  Future<Map<AlertKind, bool>> build() async =>
      (await ref.watch(alertsRepositoryProvider).settings()).orThrow;

  Future<AppFailure?> setMuted(AlertKind kind, {required bool muted}) async {
    final result = await ref
        .read(alertsRepositoryProvider)
        .setMuted(kind, muted: muted);
    switch (result) {
      case Ok(:final value):
        state = AsyncData(value);
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final alertSettingsControllerProvider =
    AsyncNotifierProvider<AlertSettingsController, Map<AlertKind, bool>>(
      AlertSettingsController.new,
      retry: noRetry,
    );
