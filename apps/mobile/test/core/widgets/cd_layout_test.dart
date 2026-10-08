import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/cd_inline_banner.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/cd_toast.dart';
import 'package:cashdeck/core/widgets/feedback/tone_icon.dart';
import 'package:cashdeck/core/widgets/layout/cd_bottom_sheet.dart';
import 'package:cashdeck/core/widgets/layout/cd_card.dart';
import 'package:cashdeck/core/widgets/layout/cd_entity_badge.dart';
import 'package:cashdeck/core/widgets/layout/cd_icon_tile.dart';
import 'package:cashdeck/core/widgets/layout/cd_key_value_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_list_row.dart';
import 'package:cashdeck/core/widgets/layout/cd_nav_bar.dart';
import 'package:cashdeck/core/widgets/layout/cd_section_header.dart';
import 'package:cashdeck/core/widgets/layout/cd_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  test('every tone has its own icon and label', () {
    final icons = MoneyTone.values.map((tone) => tone.icon).toSet();
    final labels = MoneyTone.values.map((tone) => tone.label(l10n)).toSet();

    expect(icons, hasLength(MoneyTone.values.length));
    expect(labels, hasLength(MoneyTone.values.length));
  });

  testWidgets('cards, tiles, badges and rows lay out every variant', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpApp(
      Builder(
        builder: (context) => ListView(
          children: [
            CdCard(onTap: () => taps.add('card'), child: const Text('Card')),
            const CdCard(selected: true, child: Text('Selected')),
            CdCard(
              tone: context.tone(MoneyTone.pending),
              child: const Text('Toned'),
            ),
            const CdEntityBadge(entity: EntityTone.personal, label: 'PF'),
            const CdEntityBadge(entity: EntityTone.consolidated),
            CdIconTile(
              Symbols.bolt_rounded,
              tone: context.tone(MoneyTone.paid),
              filled: true,
            ),
            const CdIconTile(Symbols.receipt_rounded, circle: false),
            CdCategoryIcon(
              icon: Symbols.shopping_cart_rounded,
              label: 'Mercado',
              onTap: () => taps.add('category'),
            ),
            CdCategoryChip(
              icon: Symbols.restaurant_rounded,
              label: 'Restaurantes',
              suggested: true,
              onTap: () => taps.add('suggested'),
            ),
            const CdCategoryChip(icon: Symbols.home_rounded, label: 'Casa'),
            const CdKeyValueRow(label: 'Valor', value: Text(r'R$ 10,00')),
            const CdKeyValueRow(
              label: 'Código',
              value: Text('E123'),
              stacked: true,
              monospace: true,
              strong: true,
            ),
            CdListRow(
              title: 'Navegar',
              subtitle: 'Abre outra tela',
              icon: Symbols.settings_rounded,
              chevron: true,
              onTap: () => taps.add('row'),
            ),
            const CdListRow(
              title: 'Remover',
              icon: Symbols.delete_rounded,
              danger: true,
            ),
            const CdListRow(
              title: 'Com badge',
              leading: Text('L'),
              trailing: Text('T'),
            ),
            CdSectionHeader(
              title: 'Seção',
              subtitle: const Text('Detalhe'),
              actionLabel: 'Ver tudo',
              actionKey: const Key('see-all'),
              onAction: () => taps.add('section'),
            ),
            const CdSectionHeader(title: 'Pequena', small: true),
            const CdStepper(steps: ['Um', 'Dois', 'Três'], current: 1),
            const CdStatusBadge(tone: MoneyTone.paid),
            CdStatusBadge.custom(
              colors: context.entities.of(EntityTone.company),
              label: 'PJ',
              icon: Symbols.business_center_rounded,
            ),
            CdInlineBanner(
              icon: Symbols.pause_rounded,
              title: 'Pausado',
              message: 'Nada sai sozinho',
              actionLabel: 'Retomar',
              actionKey: const Key('banner-action'),
              onAction: () => taps.add('banner'),
            ),
            const CdInlineBanner(
              icon: Symbols.info_rounded,
              message: 'Só mensagem',
              tone: MoneyTone.pending,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Card'));
    await tester.tap(find.text('Mercado'));
    await tester.tap(find.text('Restaurantes'));
    await tester.tap(find.text('Navegar'));
    await tester.tap(find.byKey(const Key('see-all')));
    await tester.scrollUntilVisible(
      find.byKey(const Key('banner-action')),
      200,
    );
    await tester.tap(find.byKey(const Key('banner-action')));

    expect(taps, ['card', 'category', 'suggested', 'row', 'section', 'banner']);
    expect(find.text(l10n.tonePaid), findsOneWidget);
    expect(find.text('Só mensagem'), findsOneWidget);
  });

  testWidgets('the nav bar shows a badge and reports the tab', (tester) async {
    final selected = <int>[];
    await tester.pumpApp(
      Align(
        alignment: Alignment.bottomCenter,
        child: CdNavBar(
          selectedIndex: 0,
          onSelected: selected.add,
          items: const [
            CdNavItem(icon: Symbols.home_rounded, label: 'Início'),
            CdNavItem(
              icon: Symbols.event_upcoming_rounded,
              label: 'A pagar',
              badge: 3,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(CdNavBar.itemKey(1)));

    expect(selected, [1]);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('a sheet opens with its title and a toast honors its action', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpApp(
      Builder(
        builder: (inner) {
          context = inner;
          return const SizedBox();
        },
      ),
    );

    final sheet = showCdBottomSheet<void>(
      context,
      title: 'Detalhes',
      builder: (_) => const Text('Corpo'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Detalhes'), findsOneWidget);
    expect(find.text('Corpo'), findsOneWidget);
    Navigator.of(tester.element(find.text('Corpo'))).pop();
    await tester.pumpAndSettle();
    await sheet;

    var undone = false;
    final closed = showCdToast(
      context,
      message: 'Marcada como paga',
      icon: Symbols.task_alt_rounded,
      actionLabel: 'Desfazer',
      onAction: () => undone = true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(await closed, SnackBarClosedReason.action);
    expect(undone, isTrue);

    final plain = showCdToast(context, message: 'Sem ação', actionLabel: 'Ok');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ok'));
    await tester.pumpAndSettle();
    expect(await plain, SnackBarClosedReason.action);

    showOutcomeToast(context, null, success: 'Salvo').ignore();
    await tester.pumpAndSettle();
    expect(find.text('Salvo'), findsOneWidget);
    showOutcomeToast(
      context,
      const NetworkFailure(),
      success: 'Salvo',
    ).ignore();
    await tester.pumpAndSettle();
    expect(find.text(l10n.errorNetwork), findsOneWidget);
  });
}
