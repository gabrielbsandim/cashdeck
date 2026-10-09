import 'dart:async';

import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/push/push_messaging.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/features/alerts/alerts_providers.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Where tapping [message] leads: its bill, or the inbox.
String pushLocation(PushMessage message) {
  final billId = message.billId;
  return billId == null ? AppRoutes.alerts : AppRoutes.bill(billId);
}

String pushPlatformOf(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => 'IOS',
  TargetPlatform.android => 'ANDROID',
  _ => 'WEB',
};

/// Starts push once, registers the token whenever a session exists, shows a
/// toast for a push that arrives in the foreground and follows a tapped one.
/// A registration that failed (no token yet, no network) is retried on resume.
class PushListener extends ConsumerStatefulWidget {
  const new({required this.child, required this.onOpen, super.key});

  final Widget child;
  final void Function(String location) onOpen;

  @override
  ConsumerState<PushListener> createState() => _PushListenerState();
}

class _PushListenerState extends ConsumerState<PushListener> {
  final List<StreamSubscription<Object?>> _subscriptions = [];
  late final AppLifecycleListener _lifecycle;
  var _registered = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _retry);
    unawaited(_start());
  }

  void _retry() {
    if (_registered) return;
    unawaited(_register());
  }

  Future<void> _start() async {
    final push = ref.read(pushMessagingProvider);
    if (!await push.start() || !mounted) return;
    _subscriptions.addAll([
      push.foreground().listen(_arrived),
      push.opened().listen(_open),
      push.tokenRefreshes().listen((token) => unawaited(_register(token))),
    ]);
    await _register();
    final launch = await push.launchedBy();
    if (launch == null || !mounted) return;
    _open(launch);
  }

  Future<void> _register([String? token]) async {
    if (ref.read(serverSessionProvider) == null) return;
    _registered = await ref
        .read(registerPushDeviceProvider)
        .call(platform: pushPlatformOf(defaultTargetPlatform), token: token);
  }

  void _arrived(PushMessage message) {
    ref
      ..invalidate(unreadAlertsProvider)
      ..invalidate(alertsControllerProvider);
    final l10n = AppLocalizations.of(context);
    unawaited(
      showCdToast(
        context,
        icon: Symbols.notifications_rounded,
        message: message.title ?? l10n.alertsTitle,
        actionLabel: l10n.alertOpenAction,
        onAction: () => _open(message),
      ),
    );
  }

  void _open(PushMessage message) => widget.onOpen(pushLocation(message));

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(serverSessionProvider, (previous, next) {
      if (next == null) _registered = false;
      if (previous != null || next == null) return;
      unawaited(_register());
    });
    return widget.child;
  }
}
