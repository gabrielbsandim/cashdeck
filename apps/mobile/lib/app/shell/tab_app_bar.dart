import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:cashdeck/features/alerts/presentation/alerts_controller.dart';
import 'package:cashdeck/features/entities/presentation/entity_switcher.dart';
import 'package:cashdeck/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The header of every tab root: the avatar that opens Ajustes, the entity
/// chip, the privacy eye and the alerts bell.
class TabAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const new({this.background, super.key});

  static const double height = kToolbarHeight + 8;
  static const settingsKey = Key('tab-settings');
  static const alertsKey = Key('tab-alerts');

  /// Transparent over the home glow; the theme surface elsewhere.
  final Color? background;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final unread = ref.watch(unreadAlertsProvider).value ?? 0;
    return AppBar(
      backgroundColor: background,
      toolbarHeight: height,
      titleSpacing: AppSpacing.sm,
      title: Row(
        children: [
          IconButton(
            key: settingsKey,
            tooltip: l10n.settingsOpen,
            onPressed: () => context.push(AppRoutes.settings),
            icon: CircleAvatar(
              radius: 18,
              backgroundColor: palette.primaryContainer,
              child: Icon(
                Symbols.person_rounded,
                size: 20,
                color: palette.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Flexible(child: EntityChip()),
        ],
      ),
      actions: [
        const PrivacyToggle(),
        IconButton(
          key: alertsKey,
          tooltip: l10n.alertsTitle,
          onPressed: () => context.push(AppRoutes.alerts),
          icon: Badge(
            isLabelVisible: unread > 0,
            smallSize: 8,
            child: const Icon(Symbols.notifications_rounded),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }
}
