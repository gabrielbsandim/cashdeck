import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/load_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orThrow returns the value or throws a LoadFailure', () {
    expect(const Ok(3).orThrow, 3);
    expect(
      () => const Err<int>(NetworkFailure()).orThrow,
      throwsA(
        isA<LoadFailure>().having(
          (error) => error.failure,
          'failure',
          const NetworkFailure(),
        ),
      ),
    );
  });

  test('the fake device check records why and answers as told', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final fake = container.read(
      biometricAuthenticatorProvider,
    ) as FakeBiometricAuthenticator;

    expect(await fake.authenticate('Pagar'), isTrue);
    fake.approve = false;
    expect(await fake.authenticate('Desbloquear'), isFalse);
    expect(fake.reasons, ['Pagar', 'Desbloquear']);
  });
}
