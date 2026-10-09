import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/layout/cd_ask_bar.dart';
import 'package:cashdeck/core/widgets/layout/cd_nav_bar.dart';
import 'package:cashdeck/features/bills/presentation/bills_controller.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The four tabs and the ask bar above them. Both show only on the tab
/// roots; the ask bar steps aside while the user scrolls down.
class TabsShell extends ConsumerStatefulWidget {
  const new({required this.navigationShell, required this.location, super.key});

  final StatefulNavigationShell navigationShell;
  final String location;

  @override
  ConsumerState<TabsShell> createState() => _TabsShellState();
}

class _TabsShellState extends ConsumerState<TabsShell> {
  bool _askVisible = true;

  bool _onScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _askVisible,
    };
    if (visible != _askVisible) setState(() => _askVisible = visible);
    return false;
  }

  void _select(int index) {
    final shell = widget.navigationShell;
    setState(() => _askVisible = true);
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final showsBar = AppRoutes.tabs.contains(widget.location);
    final billsBadge = ref.watch(billsNeedingYouCountProvider);
    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: widget.navigationShell,
      ),
      bottomNavigationBar: showsBar
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: AppMotion.of(context, AppMotion.medium),
                  curve: AppMotion.standard,
                  child: _askVisible
                      ? CdAskBar(
                          hint: l10n.askBarHint,
                          onTap: () => context.push(AppRoutes.chat),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                CdNavBar(
                  selectedIndex: widget.navigationShell.currentIndex,
                  onSelected: _select,
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
                    CdNavItem(
                      icon: Symbols.insights_rounded,
                      label: l10n.tabInsights,
                    ),
                  ],
                ),
              ],
            )
          : null,
    );
  }
}
