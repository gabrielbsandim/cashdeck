import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => InMemoryCredentialStore(),
);

/// What the store held at launch; main reads it before the first frame so
/// the router knows where to start.
final initialCredentialsProvider = Provider<ServerCredentials?>(
  (ref) => switch (ref.watch(appConfigProvider).backend) {
    Backend.fake => ServerCredentials.demo,
    Backend.api => null,
  },
);

/// The server this device is signed in to, or null when signed out.
class ServerSessionController extends Notifier<ServerCredentials?> {
  @override
  ServerCredentials? build() => ref.read(initialCredentialsProvider);

  Future<void> signIn(ServerCredentials credentials) async {
    await ref.read(credentialStoreProvider).write(credentials);
    state = credentials;
  }

  Future<void> signOut() async {
    await ref.read(credentialStoreProvider).clear();
    state = null;
  }
}

final serverSessionProvider =
    NotifierProvider<ServerSessionController, ServerCredentials?>(
      ServerSessionController.new,
    );
