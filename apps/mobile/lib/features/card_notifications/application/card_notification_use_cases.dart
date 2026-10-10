import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/features/card_notifications/domain/card_notifications.dart';
import 'package:cashdeck/features/transactions/domain/transaction.dart';

/// The cards a notification can land on, by name.
final class ListNotificationCards {
  const new(this._repository);

  final TransactionsRepository _repository;

  Future<Result<List<TransactionAccount>>> call() async {
    final result = await _repository.accounts();
    return switch (result) {
      Ok(:final value) => Ok(
        value
            .where((account) => account.type == AccountType.creditCard)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name)),
      ),
      Err(:final failure) => Err(failure),
    };
  }
}

/// Forwarding only runs with a card and a session to send with.
final class SaveCardNotifications {
  const new(this._bridge);

  final CardNotificationBridge _bridge;

  Future<Result<CardNotificationStatus>> call({
    required bool enabled,
    required Set<String> packages,
    required String? accountId,
    required ServerCredentials? session,
  }) {
    final ready = enabled && accountId != null && session != null;
    return _bridge.configure(
      CardNotificationConfig(
        enabled: ready,
        packages: packages,
        accountId: accountId,
        baseUrl: ready ? session.baseUrl : null,
        token: ready ? session.token : null,
      ),
    );
  }
}

/// A signed-out phone stops forwarding and forgets the token.
final class StopCardNotifications {
  const new(this._bridge);

  final CardNotificationBridge _bridge;

  Future<void> call() async {
    if (!_bridge.supported) return;
    await _bridge.configure(CardNotificationConfig.off);
  }
}
