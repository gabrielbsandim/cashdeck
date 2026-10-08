import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// The device check behind every in-app confirmation: fingerprint, face or
/// the device PIN.
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

final class LocalAuthBiometricAuthenticator implements BiometricAuthenticator {
  new([LocalAuthentication? auth]) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  /// A device with no lock at all has nothing to check, so it passes; the
  /// PIN counts as well as biometrics.
  @override
  Future<bool> authenticate(String reason) async {
    try {
      if (!await _auth.isDeviceSupported()) return true;
      return await _auth.authenticate(localizedReason: reason);
    } on PlatformException {
      return false;
    } on LocalAuthException {
      return false;
    }
  }
}

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>(
  (ref) => FakeBiometricAuthenticator(),
);
