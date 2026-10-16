import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/card_notifications/card_notifications_providers.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class CardNotificationsView extends Equatable {
  const new({
    required this.supported,
    required this.status,
    required this.cards,
  });

  final bool supported;
  final CardNotificationStatus status;
  final List<TransactionAccount> cards;

  bool get canEnable => allows(status.routes);

  bool allows(Map<String, String> routes) =>
      status.access &&
      routes.isNotEmpty &&
      routes.values.every((id) => cards.any((card) => card.id == id));

  TransactionAccount? cardOf(String package) =>
      cards.where((card) => card.id == status.routes[package]).firstOrNull;

  CardNotificationsView withStatus(CardNotificationStatus status) =>
      CardNotificationsView(supported: supported, status: status, cards: cards);

  @override
  List<Object?> get props => [supported, status, cards];
}

class CardNotificationsController extends AsyncNotifier<CardNotificationsView> {
  @override
  Future<CardNotificationsView> build() async {
    final bridge = ref.watch(cardNotificationBridgeProvider);
    if (!bridge.supported) {
      return const CardNotificationsView(
        supported: false,
        status: CardNotificationStatus.unsupported,
        cards: [],
      );
    }
    final status = await bridge.status();
    final cards = await ref.watch(listNotificationCardsProvider).call();
    return switch ((status, cards)) {
      (Ok(value: final status), Ok(value: final cards)) =>
        CardNotificationsView(supported: true, status: status, cards: cards),
      (Err(:final failure), _) ||
      (_, Err(:final failure)) => throw LoadFailure(failure),
    };
  }

  Future<AppFailure?> openAccessSettings() async {
    final result = await ref
        .read(cardNotificationBridgeProvider)
        .openAccessSettings();
    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
  }

  Future<AppFailure?> setEnabled({required bool enabled}) =>
      _save((status) => (enabled, status.routes));

  /// Sends [package]'s charges to [accountId], or stops watching it on null.
  Future<AppFailure?> routeApp(String package, String? accountId) => _save(
    (status) => (
      status.enabled,
      accountId == null
          ? ({...status.routes}..remove(package))
          : {...status.routes, package: accountId},
    ),
  );

  Future<AppFailure?> _save(
    (bool, Map<String, String>) Function(CardNotificationStatus) change,
  ) async {
    final current = state.value;
    if (current == null) return null;
    final (enabled, routes) = change(current.status);
    final result = await ref
        .read(saveCardNotificationsProvider)
        .call(
          enabled: enabled && current.allows(routes),
          routes: routes,
          session: ref.read(serverSessionProvider),
        );
    switch (result) {
      case Ok(:final value):
        state = AsyncData(current.withStatus(value));
        return null;
      case Err(:final failure):
        return failure;
    }
  }
}

final cardNotificationsControllerProvider =
    AsyncNotifierProvider<CardNotificationsController, CardNotificationsView>(
      CardNotificationsController.new,
      retry: noRetry,
    );
