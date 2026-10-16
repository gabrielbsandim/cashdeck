import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/card_notifications/card_notifications_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hands the session to forwarding at launch and after every sign-in.
void resumeCardNotificationsOnSignIn(WidgetRef ref) =>
    ref.listenManual(serverSessionProvider, (_, session) {
      if (session == null) return;
      ref.read(resumeCardNotificationsProvider)(session).ignore();
    }, fireImmediately: true);
