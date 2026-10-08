import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/app_palette.dart';
import 'package:cashdeck/core/theme/app_spacing.dart';
import 'package:cashdeck/core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';

final class CdNavItem {
  const new({required this.icon, required this.label, this.badge = 0});

  final IconData icon;
  final String label;

  /// How many things wait for the user there; zero hides the badge.
  final int badge;
}

/// The bottom navigation: an 80 high bar, the active tab in a pill.
class CdNavBar extends StatelessWidget {
  const new({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  static Key itemKey(int index) => Key('cd-nav-$index');

  final List<CdNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surfaceContainerLow,
        border: Border(top: BorderSide(color: palette.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 80,
          child: Row(
            children: [
              for (final (index, item) in items.indexed)
                Expanded(
                  child: _NavItem(
                    key: itemKey(index),
                    item: item,
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const new({
    required this.item,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CdNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final money = context.money;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: AppMotion.of(context, AppMotion.medium),
                  curve: AppMotion.standard,
                  width: 56,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppSpacing.lg),
                  ),
                  child: Icon(
                    item.icon,
                    size: 22,
                    fill: selected ? 1 : 0,
                    color: selected
                        ? palette.onPrimaryContainer
                        : palette.onSurfaceVariant,
                  ),
                ),
                if (item.badge > 0)
                  Positioned(
                    top: -2,
                    left: 34,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: money.failed,
                        borderRadius: BorderRadius.circular(AppSpacing.sm),
                      ),
                      child: Text(
                        '${item.badge}',
                        style: AppTextStyles.labelMd.copyWith(
                          fontSize: 11,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w700,
                          color: palette.surface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelMd.copyWith(
                letterSpacing: 0,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? palette.onSurface : palette.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
