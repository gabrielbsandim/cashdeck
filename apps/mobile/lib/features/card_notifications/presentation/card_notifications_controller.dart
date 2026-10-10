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

  bool get canEnable => allows(status.packages, status.accountId);

  bool allows(Set<String> packages, String? accountId) =>
      status.access &&
      packages.isNotEmpty &&
      cards.any((card) => card.id == accountId);

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
      _save((status) => (enabled, status.packages, status.accountId));

  Future<AppFailure?> selectCard(String accountId) =>
      _save((status) => (status.enabled, status.packages, accountId));

  Future<AppFailure?> toggleApp(String package, {required bool watched}) =>
      _save(
        (status) => (
          status.enabled,
          watched
              ? {...status.packages, package}
              : ({...status.packages}..remove(package)),
          status.accountId,
        ),
      );

  Future<AppFailure?> _save(
    (bool, Set<String>, String?) Function(CardNotificationStatus) change,
  ) async {
    final current = state.value;
    if (current == null) return null;
    final (enabled, packages, accountId) = change(current.status);
    final result = await ref
        .read(saveCardNotificationsProvider)
        .call(
          enabled: enabled && current.allows(packages, accountId),
          packages: packages,
          accountId: accountId,
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
