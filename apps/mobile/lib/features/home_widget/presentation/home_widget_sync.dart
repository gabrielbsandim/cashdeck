import 'package:cashdeck/core/di/core_providers.dart';
import 'package:cashdeck/core/session/server_session.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/features/home_widget/domain/widget_snapshot.dart';
import 'package:cashdeck/features/home_widget/home_widget_providers.dart';
import 'package:cashdeck/features/home_widget/presentation/widget_values_controller.dart';
import 'package:cashdeck/features/insights/presentation/insights_controller.dart';
import 'package:cashdeck/features/outlook/presentation/outlook_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The widget's numbers from what Início already loads, masked unless
/// [widgetShowsAmountsProvider] allows them.
final Provider<WidgetSnapshot> homeWidgetSnapshotProvider =
    Provider.autoDispose<WidgetSnapshot>(
      (ref) => WidgetSnapshot.from(
        now: ref.watch(clockProvider).now(),
        hide: !ref.watch(widgetShowsAmountsProvider),
        safeToSpend: ref.watch(
          safeToSpendProvider.select((free) => free.value),
        ),
        bills: ref.watch(
          billsControllerProvider.select((listing) => listing.value?.bills),
        ),
        overview: ref.watch(
          insightsOverviewProvider.select((overview) => overview.value),
        ),
      ),
    );

/// Writes the widget each time a source loads or privacy changes, while
/// Início is alive. It draws nothing.
class HomeWidgetSync extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<HomeWidgetSync> createState() => _HomeWidgetSyncState();
}

class _HomeWidgetSyncState extends ConsumerState<HomeWidgetSync> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(
      homeWidgetSnapshotProvider,
      (_, snapshot) => ref.read(publishHomeWidgetProvider)(snapshot).ignore(),
      fireImmediately: true,
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Empties the widget whenever the session ends, by sign-out or by a 401.
void clearHomeWidgetOnSignOut(WidgetRef ref) => ref.listenManual(
  serverSessionProvider.select((session) => session == null),
  (_, signedOut) {
    if (!signedOut) return;
    ref.read(clearHomeWidgetProvider)().ignore();
  },
);

/// Lets Android wake the app to refresh the widget while it is closed.
void enableHomeWidgetRefresh(WidgetRef ref) =>
    ref.read(enableHomeWidgetRefreshProvider)().ignore();
