import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device check behind every in-app confirmation: fingerprint, face or
/// the device PIN. A real adapter wraps the platform; the fake approves.
abstract interface class BiometricAuthenticator {
  Future<bool> authenticate(String reason);
}

final class FakeBiometricAuthenticator implements BiometricAuthenticator {
  new({this.approve = true});

  bool approve;
  final List<String> reasons = [];

  @override
  Future<bool> authenticate(String reason) async {
    reasons.add(reason);
    return approve;
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => FakeBiometricAuthenticator(),
);
