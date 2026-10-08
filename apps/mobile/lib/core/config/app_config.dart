import 'package:equatable/equatable.dart';

enum Backend { fake, api }

final class AppConfig extends Equatable {
  const new({required this.backend, required this.apiBaseUrl});

  factory fromEnvironment() => AppConfig.parse(
    backend: const String.fromEnvironment('BACKEND'),
    apiBaseUrl: const String.fromEnvironment('API_BASE_URL'),
  );

  factory parse({required String backend, required String apiBaseUrl}) {
    return AppConfig(
      backend: backend.isEmpty ? Backend.fake : Backend.values.byName(backend),
      apiBaseUrl: apiBaseUrl.isEmpty ? defaultApiBaseUrl : apiBaseUrl,
    );
  }

  // Self-hosted: each deployment passes its own API_BASE_URL.
  static const defaultApiBaseUrl = 'http://localhost:3000';

  final Backend backend;
  final String apiBaseUrl;

  @override
  List<Object?> get props => [backend, apiBaseUrl];
}
