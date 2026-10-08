import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/widgets/brand/cd_mark.dart';
import 'package:cashdeck/core/widgets/buttons/cd_button.dart';
import 'package:cashdeck/core/widgets/charts/cd_bar_chart.dart';
import 'package:cashdeck/core/widgets/charts/cd_donut.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/states/cd_empty_state.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:cashdeck/core/widgets/states/coming_soon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  group('CdButton', () {
    testWidgets('every variant taps, scales on press and can be disabled', (
      tester,
    ) async {
      var taps = 0;
      void tap() => taps++;
      await tester.pumpApp(
        ListView(
          children: [
            CdButton(label: 'Base', onPressed: tap),
            CdButton.filled(label: 'Filled', icon: Symbols.add, onPressed: tap),
            CdButton.tonal(label: 'Tonal', expand: true, onPressed: tap),
            CdButton.outlined(label: 'Outlined', onPressed: tap),
            CdButton.text(label: 'Text', dense: true, onPressed: tap),
            CdButton.danger(label: 'Danger', onPressed: tap),
            const CdButton.outlined(label: 'Off', onPressed: null),
            CdButton.filled(label: 'Busy', loading: true, onPressed: tap),
          ],
        ),
      );

      for (final label in ['Base', 'Filled', 'Tonal', 'Outlined', 'Text']) {
        await tester.tap(find.text(label));
      }
      await tester.tap(find.text('Danger'));
      await tester.tap(find.text('Off'));
      await tester.tap(find.text('Busy'));
      expect(taps, 6);

      final gesture = await tester.press(find.text('Filled'));
      await tester.pump(const Duration(milliseconds: 200));
      final scale = tester.widget<AnimatedScale>(
        find.ancestor(
          of: find.text('Filled'),
          matching: find.byType(AnimatedScale),
        ),
      );
      expect(scale.scale, 0.98);
      await gesture.up();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('the mark and the wordmark paint in both styles', (tester) async {
    await tester.pumpApp(
      const Column(
        children: [CdMark(), CdMark(mono: true, size: 24), CdWordmark()],
      ),
      dark: true,
    );

    expect(find.byType(CdMark), findsNWidgets(2));
    expect(find.text('Cashdeck', findRichText: true), findsOneWidget);
    const painter = CdMarkPainter(tile: null, card: Colors.black);
    expect(
      painter.shouldRepaint(
        const CdMarkPainter(tile: Colors.blue, card: Colors.black),
      ),
      isTrue,
    );
    expect(painter.shouldRepaint(painter), isFalse);
  });

  testWidgets('charts draw their labels and legends', (tester) async {
    await tester.pumpApp(
      ListView(
        children: const [
          CdBarChart(
            groups: [CdBarGroup('jul', 10, 8), CdBarGroup('ago', 12, 14)],
            incomeLabel: 'Entradas',
            expenseLabel: 'Saídas',
            semanticsLabel: 'Barras',
          ),
          CdBarChart(
            groups: [],
            incomeLabel: 'Entradas vazias',
            expenseLabel: 'Saídas vazias',
            semanticsLabel: 'Sem barras',
          ),
          CdBarChart(
            groups: [CdBarGroup('zero', 0, 0)],
            incomeLabel: 'Zero',
            expenseLabel: 'Nada',
            semanticsLabel: 'Barras zeradas',
          ),
          CdDonut(
            slices: [
              CdDonutSlice('Mercado', 0.6, Colors.green),
              CdDonutSlice('Casa', 0.4, Colors.blue),
            ],
            centerValue: r'R$ 4,3 mil',
            centerCaption: 'no mês',
          ),
          CdSplitBar(parts: [(0.7, Colors.blue), (0.3, Colors.teal)]),
          CdLineChart(
            values: [10, 6, 8, 12],
            xLabels: ['1', '15', '30'],
            semanticsLabel: 'Linha',
            floor: 7,
          ),
          CdLineChart(values: [5, 5], xLabels: ['a'], semanticsLabel: 'Plana'),
          CdLineChart(values: [5], xLabels: [], semanticsLabel: 'Um'),
        ],
      ),
    );

    expect(find.text('ago'), findsOneWidget);
    expect(find.text('Entradas'), findsOneWidget);
    expect(find.text(r'R$ 4,3 mil'), findsOneWidget);
    expect(find.text('Casa'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mercado 60%')), findsOneWidget);
  });

  group('states', () {
    testWidgets('empty, coming soon and skeleton', (tester) async {
      var acted = false;
      await tester.pumpApp(
        Column(
          children: [
            Expanded(
              child: CdEmptyState(
                title: 'Vazio',
                message: 'Nada aqui',
                actionLabel: 'Adicionar',
                onAction: () => acted = true,
              ),
            ),
            const Expanded(child: CdEmptyState(title: 'Só título')),
            const Expanded(child: ComingSoon()),
            const Expanded(child: CdSkeleton(rows: 2)),
            const Expanded(child: CdLoading()),
          ],
        ),
      );

      await tester.tap(find.text('Adicionar'));
      expect(acted, isTrue);
      expect(find.text(l10n.comingSoonTitle), findsOneWidget);
      expect(find.text('Só título'), findsOneWidget);
    });

    testWidgets('an error offers a retry only when it can', (tester) async {
      var retried = false;
      await tester.pumpApp(
        Column(
          children: [
            Expanded(
              child: CdErrorState(
                failure: const NetworkFailure(),
                onRetry: () => retried = true,
              ),
            ),
            const Expanded(child: CdErrorState(failure: ServerFailure())),
          ],
        ),
      );

      expect(find.text(l10n.errorNetwork), findsOneWidget);
      expect(find.text(l10n.errorServer), findsOneWidget);
      expect(find.byKey(CdErrorState.retryKey), findsOneWidget);
      await tester.tap(find.byKey(CdErrorState.retryKey));
      expect(retried, isTrue);
    });
  });
}
