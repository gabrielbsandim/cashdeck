import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Pull to refresh over everything a screen shows: it refetches each of
/// [providers] and keeps the spinner until all of them answered.
class CdRefresh extends ConsumerWidget {
  const new({
    required this.providers,
    required this.child,
    this.edgeOffset = 0,
    super.key,
  });

  final List<ProviderBase<AsyncValue<Object?>>> providers;
  final Widget child;
  final double edgeOffset;

  @override
  Widget build(BuildContext context, WidgetRef ref) => RefreshIndicator(
    edgeOffset: edgeOffset,
    onRefresh: () => refreshShown(ref, providers),
    child: child,
  );
}

/// Refetches the providers that are alive and completes once each settled.
/// One nobody reads is skipped: it loads fresh when a widget next watches it.
Future<void> refreshShown(
  WidgetRef ref,
  List<ProviderBase<AsyncValue<Object?>>> providers,
) async {
  await Future.wait([
    for (final provider in providers)
      if (provider case final AsyncProviderListenable<Object?> loader
          when ref.exists(provider))
        ref.refresh(loader.future).then<void>((_) {}, onError: (_) {}),
  ]);
}
