import 'package:equatable/equatable.dart';

/// Where the self-hosted server lives and the access token it accepts.
final class ServerCredentials extends Equatable {
  const new({required this.baseUrl, required this.token});

  /// What the fake backend signs in with, so the demo opens on Home.
  static const demo = ServerCredentials(
    baseUrl: 'https://cashdeck.casa.local',
    token: 'demo-token',
  );

  final String baseUrl;
  final String token;

  String get host => Uri.tryParse(baseUrl)?.host ?? baseUrl;

  @override
  List<Object?> get props => [baseUrl, token];
}

/// The address as typed, with a scheme and without a trailing slash; https
/// unless the user wrote http.
String normalizeServerUrl(String input) {
  final trimmed = input.trim();
  final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
  return withScheme.endsWith('/')
      ? withScheme.substring(0, withScheme.length - 1)
      : withScheme;
}

bool isValidServerUrl(String input) {
  final uri = Uri.tryParse(normalizeServerUrl(input));
  if (uri == null || uri.host.isEmpty) return false;
  return uri.scheme == 'https' || uri.scheme == 'http';
}
