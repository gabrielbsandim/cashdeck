import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/widgets/inputs/cd_checkbox_row.dart';
import 'package:cashdeck/core/widgets/inputs/cd_currency_input.dart';
import 'package:cashdeck/core/widgets/inputs/cd_filter_chip.dart';
import 'package:cashdeck/core/widgets/inputs/cd_search_field.dart';
import 'package:cashdeck/core/widgets/inputs/cd_segmented.dart';
import 'package:cashdeck/core/widgets/inputs/cd_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  test('typed cents fill from the right and stop at 13 digits', () {
    const formatter = CentsInputFormatter();

    expect(CentsInputFormatter.centsOf(''), 0);
    expect(CentsInputFormatter.centsOf('1.234,56'), 123456);
    expect(CentsInputFormatter.centsOf('12345678901234567'), 1234567890123);
    expect(
      formatter
          .formatEditUpdate(
            TextEditingValue.empty,
            const TextEditingValue(text: '123'),
          )
          .text,
      '1,23',
    );
  });

  testWidgets('the currency input reports cents and shows its line state', (
    tester,
  ) async {
    final values = <Money>[];
    await tester.pumpApp(
      Column(
        children: [
          CdCurrencyInput(
            label: 'Valor',
            helperText: 'Em reais',
            onChanged: values.add,
          ),
          CdCurrencyInput(
            label: 'Em dólar',
            large: false,
            initial: const Money(2000, currency: 'USD'),
            errorText: 'Valor alto',
            currencyChip: const Text('USD'),
            onChanged: values.add,
          ),
        ],
      ),
    );

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '12345');
    await tester.enterText(find.byType(TextField).last, '500');
    await tester.pump();

    expect(values, [const Money(12345), const Money(500, currency: 'USD')]);
    expect(find.text('Em reais'), findsOneWidget);
    expect(find.text('Valor alto'), findsOneWidget);
    expect(find.text(r'US$'), findsOneWidget);
  });

  testWidgets('the text field reveals a secret and marks valid or wrong', (
    tester,
  ) async {
    final typed = <String>[];
    final controller = TextEditingController(text: 'abc');
    addTearDown(controller.dispose);
    await tester.pumpApp(
      Column(
        children: [
          CdTextField(label: 'Senha', secret: true, onChanged: typed.add),
          const CdTextField(label: 'Válido', valid: true, initialValue: 'ok'),
          const CdTextField(label: 'Errado', errorText: 'Inválido'),
          CdTextField(
            label: 'Código',
            controller: controller,
            monospace: true,
            enabled: false,
            suffix: const Icon(Symbols.qr_code_rounded),
          ),
        ],
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'segredo');
    expect(typed, ['segredo']);
    expect(find.byTooltip(l10n.showTyped), findsOneWidget);
    await tester.tap(find.byTooltip(l10n.showTyped));
    await tester.pump();
    expect(find.byTooltip(l10n.hideTyped), findsOneWidget);
    expect(find.text('Inválido'), findsOneWidget);
    expect(find.byIcon(Symbols.check_circle_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.qr_code_rounded), findsOneWidget);
  });

  testWidgets('the search field clears with one tap', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpApp(
      Column(
        children: [
          CdSearchField(
            controller: controller,
            hint: 'Buscar',
            onChanged: changes.add,
          ),
          CdSearchField(
            controller: TextEditingController(),
            hint: 'Carregando',
            loading: true,
          ),
        ],
      ),
    );

    expect(find.byKey(CdSearchField.clearKey), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'mercado');
    await tester.pump();
    await tester.tap(find.byKey(CdSearchField.clearKey));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes, ['mercado', '']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('segments select and skip a disabled one', (tester) async {
    final picked = <int>[];
    await tester.pumpApp(
      CdSegmented<int>(
        segments: const [
          CdSegment(1, 'Um'),
          CdSegment(2, 'Dois', key: Key('two')),
          CdSegment(3, 'Três', enabled: false),
        ],
        selected: 1,
        onChanged: picked.add,
      ),
    );

    await tester.tap(find.byKey(const Key('two')));
    await tester.tap(find.text('Três'));

    expect(picked, [2]);
    expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
  });

  testWidgets('filter chips select, remove and open a picker', (tester) async {
    final events = <String>[];
    await tester.pumpApp(
      Wrap(
        children: [
          CdFilterChip(label: 'Todos', onTap: () => events.add('tap')),
          CdFilterChip(
            label: 'Pagas',
            selected: true,
            onTap: () => events.add('selected'),
          ),
          CdFilterChip(label: 'Julho', onRemove: () => events.add('remove')),
          CdFilterChip(
            label: 'Conta',
            dropdown: true,
            icon: Symbols.account_balance_rounded,
            onTap: () => events.add('dropdown'),
          ),
          const CdFilterChip(label: 'Desligado'),
        ],
      ),
    );

    for (final label in ['Todos', 'Pagas', 'Julho', 'Conta', 'Desligado']) {
      await tester.tap(find.text(label));
    }

    expect(events, ['tap', 'selected', 'remove', 'dropdown']);
    expect(find.byIcon(Symbols.close_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_drop_down_rounded), findsOneWidget);
  });

  testWidgets('a checkbox row toggles from the row or the box', (tester) async {
    final values = <bool>[];
    await tester.pumpApp(
      Column(
        children: [
          CdCheckboxRow(
            title: 'Extratos',
            value: false,
            subtitle: const Text('OFX'),
            trailing: const Text('12'),
            onChanged: values.add,
          ),
          const CdCheckboxRow(title: 'Bloqueado', value: true, onChanged: null),
        ],
      ),
    );

    await tester.tap(find.text('Extratos'));
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.text('Bloqueado'));

    expect(values, [true, true]);
    expect(find.text('OFX'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
