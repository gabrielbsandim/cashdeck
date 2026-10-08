import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

void main() {
  test('every failure has a user message', () {
    final cases = {
      const NetworkFailure(): l10n.errorNetwork,
      const UnauthorizedFailure(): l10n.errorSessionExpired,
      const ForbiddenFailure(): l10n.errorForbidden,
      const NotFoundFailure(): l10n.errorNotFound,
      const ValidationFailure('Campo inválido'): 'Campo inválido',
      const RateLimitedFailure(): l10n.errorRateLimited,
      const ServerFailure(): l10n.errorServer,
      const UnexpectedFailure(): l10n.errorUnexpected,
    };
    for (final MapEntry(:key, :value) in cases.entries) {
      expect(key.userMessage(l10n), value);
    }
  });

  test('failureOf unwraps a LoadFailure and hides anything else', () {
    const load = LoadFailure(NetworkFailure());

    expect(failureOf(load), const NetworkFailure());
    expect(failureOf(StateError('boom')), const UnexpectedFailure());
    expect(load.toString(), contains('NetworkFailure'));
    expect(noRetry(1, load), isNull);
  });
}
