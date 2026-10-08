import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

final class _MockAuth extends Mock implements LocalAuthentication;

void main() {
  test('asks the device and passes a device with no lock', () async {
    final auth = _MockAuth();
    when(auth.isDeviceSupported).thenAnswer((_) async => true);
    when(
      () => auth.authenticate(localizedReason: any(named: 'localizedReason')),
    ).thenAnswer((_) async => true);
    final authenticator = LocalAuthBiometricAuthenticator(auth);

    expect(await authenticator.authenticate('Desbloquear'), isTrue);
    verify(() => auth.authenticate(localizedReason: 'Desbloquear')).called(1);

    when(auth.isDeviceSupported).thenAnswer((_) async => false);
    expect(await authenticator.authenticate('Desbloquear'), isTrue);
  });

  test('a platform error or a cancel is a refusal', () async {
    final auth = _MockAuth();
    when(auth.isDeviceSupported).thenAnswer((_) async => true);
    when(
      () => auth.authenticate(localizedReason: any(named: 'localizedReason')),
    ).thenThrow(PlatformException(code: 'NotAvailable'));
    final authenticator = LocalAuthBiometricAuthenticator(auth);
    expect(await authenticator.authenticate('x'), isFalse);

    when(
      () => auth.authenticate(localizedReason: any(named: 'localizedReason')),
    ).thenThrow(
      const LocalAuthException(code: LocalAuthExceptionCode.userCanceled),
    );
    expect(await authenticator.authenticate('x'), isFalse);
    expect(LocalAuthBiometricAuthenticator(), isA<BiometricAuthenticator>());
  });
}
