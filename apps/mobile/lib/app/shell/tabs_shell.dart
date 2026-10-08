import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/widgets/layout/cd_nav_bar.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The five tabs. The bar shows only on the tab roots; deeper screens take
/// the whole height.
class TabsShell extends ConsumerWidget {
  const new({required this.navigationShell, required this.location, super.key});

  final StatefulNavigationShell navigationShell;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final showsBar = AppRoutes.tabs.contains(location);
    final billsBadge = ref.watch(billsNeedingYouCountProvider);
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: showsBar
          ? CdNavBar(
              selectedIndex: navigationShell.currentIndex,
              onSelected: (index) => navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              ),
              items: [
                CdNavItem(icon: Symbols.home_rounded, label: l10n.tabHome),
                CdNavItem(
                  icon: Symbols.receipt_long_rounded,
                  label: l10n.tabTransactions,
                ),
                CdNavItem(
                  icon: Symbols.event_upcoming_rounded,
                  label: l10n.tabBills,
                  badge: billsBadge,
                ),
                CdNavItem(icon: Symbols.forum_rounded, label: l10n.tabChat),
                CdNavItem(icon: Symbols.menu_rounded, label: l10n.tabMore),
              ],
            )
          : null,
    );
  }
}
