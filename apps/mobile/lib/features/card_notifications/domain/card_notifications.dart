import 'package:cashdeck/core/result/result.dart';
import 'package:equatable/equatable.dart';

/// An app that posted a notification on this phone.
final class NotifyingApp extends Equatable {
  const new({required this.package, required this.label});

  final String package;
  final String label;

  @override
  List<Object?> get props => [package, label];
}

/// Where forwarding stands on this phone.
final class CardNotificationStatus extends Equatable {
  const new({
    required this.access,
    required this.enabled,
    required this.routes,
    required this.pending,
    required this.apps,
  });

  static const unsupported = CardNotificationStatus(
    access: false,
    enabled: false,
    routes: {},
    pending: 0,
    apps: [],
  );

  /// Whether the user let Cashdeck read notifications in system settings.
  final bool access;
  final bool enabled;

  /// The card each watched app's charges land on, by package.
  final Map<String, String> routes;

  /// Notifications waiting for the network.
  final int pending;
  final List<NotifyingApp> apps;

  @override
  List<Object?> get props => [access, enabled, routes, pending, apps];
}

/// What forwarding sends and where; the server and token are the session's.
final class CardNotificationConfig extends Equatable {
  const new({
    required this.enabled,
    required this.routes,
    this.baseUrl,
    this.token,
  });

  static const off = CardNotificationConfig(enabled: false, routes: {});

  final bool enabled;
  final Map<String, String> routes;
  final String? baseUrl;
  final String? token;

  @override
  List<Object?> get props => [enabled, routes, baseUrl, token];
}

/// The phone side that reads other apps' notifications, Android only.
abstract interface class CardNotificationBridge {
  bool get supported;

  Future<Result<CardNotificationStatus>> status();

  Future<Result<void>> openAccessSettings();

  Future<Result<CardNotificationStatus>> configure(
    CardNotificationConfig config,
  );
}
