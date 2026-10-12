import 'package:cashdeck/features/auth/domain/server_access.dart';

/// How a phone on [operatingSystem] (as `Platform.operatingSystem` names it)
/// introduces itself; the app ships only for Android and iOS.
DeviceIdentity deviceIdentityFor(
  String operatingSystem,
) => switch (operatingSystem) {
  'ios' => const DeviceIdentity(name: 'iPhone', platform: SessionPlatform.ios),
  _ => const DeviceIdentity(name: 'Android', platform: SessionPlatform.android),
};
