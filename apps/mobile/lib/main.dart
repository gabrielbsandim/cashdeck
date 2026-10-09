import 'package:cashdeck/app/app.dart';
import 'package:cashdeck/core/config/app_config.dart';
import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/files/file_chooser.dart';
import 'package:cashdeck/core/links/link_opener.dart';
import 'package:cashdeck/core/preferences/key_value_store.dart';
import 'package:cashdeck/core/push/firebase_push_messaging.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/scan/camera_code_scanner.dart';
import 'package:cashdeck/core/scan/code_scanner.dart';
import 'package:cashdeck/core/security/app_lock.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/session/credential_store.dart';
import 'package:cashdeck/core/session/server_credentials.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/share/file_sharer.dart';
import 'package:cashdeck/core/share/share_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  final config = AppConfig.fromEnvironment();
  const store = SecureCredentialStore();
  final credentials = switch (config.backend) {
    Backend.fake => ServerCredentials.demo,
    Backend.api => await store.read(),
  };
  final preferences = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        credentialStoreProvider.overrideWithValue(store),
        initialCredentialsProvider.overrideWithValue(credentials),
        initiallyLockedProvider.overrideWithValue(
          config.backend == Backend.api && credentials != null,
        ),
        keyValueStoreProvider.overrideWithValue(
          SharedPreferencesStore(preferences),
        ),
        biometricAuthenticatorProvider.overrideWithValue(
          LocalAuthBiometricAuthenticator(),
        ),
        fileChooserProvider.overrideWithValue(const PlatformFileChooser()),
        fileSharerProvider.overrideWithValue(PlatformFileSharer()),
        linkOpenerProvider.overrideWithValue(const PlatformLinkOpener()),
        shareIntakeProvider.overrideWithValue(PlatformShareIntake()),
        codeScannerProvider.overrideWithValue(cameraScanner),
        pushMessagingProvider.overrideWithValue(FirebasePushMessaging()),
      ],
      child: const CashdeckApp(),
    ),
  );
}
