import 'package:cashdeck/features/auth/domain/server_access.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// The longest device name the server keeps.
const _maxNameLength = 80;

/// How a phone on [operatingSystem] (as `Platform.operatingSystem` names it)
/// introduces itself: by its [model] when the phone reports one, else by its
/// platform. The app ships only for Android and iOS.
DeviceIdentity deviceIdentityFor(String operatingSystem, {String? model}) {
  final platform = operatingSystem == 'ios'
      ? SessionPlatform.ios
      : SessionPlatform.android;
  final named = model?.trim() ?? '';
  if (named.isEmpty) {
    return DeviceIdentity(
      name: platform == SessionPlatform.ios ? 'iPhone' : 'Android',
      platform: platform,
    );
  }
  final name = named.length > _maxNameLength
      ? named.substring(0, _maxNameLength)
      : named;
  return DeviceIdentity(name: name, platform: platform);
}

/// `Google Pixel 8` from a maker and a model that may already start with it,
/// as `samsung` and `Galaxy S23` or `Google` and `Pixel 8`.
String androidModelName(String manufacturer, String model) {
  final maker = manufacturer.trim();
  final name = model.trim();
  if (maker.isEmpty || name.toLowerCase().startsWith(maker.toLowerCase())) {
    return name;
  }
  return '${maker[0].toUpperCase()}${maker.substring(1)} $name';
}

/// The model this phone reports, such as `Google Pixel 8` or `iPhone 15
/// Pro`; null when the platform does not say or the plugin is missing.
Future<String?> readDeviceModel(
  String operatingSystem, [
  DeviceInfoPlugin? plugin,
]) async {
  final info = plugin ?? DeviceInfoPlugin();
  try {
    return switch (operatingSystem) {
      'ios' => (await info.iosInfo).modelName,
      'android' => _android(await info.androidInfo),
      _ => null,
    };
  } on Object {
    return null;
  }
}

String _android(AndroidDeviceInfo info) =>
    androidModelName(info.manufacturer, info.model);
