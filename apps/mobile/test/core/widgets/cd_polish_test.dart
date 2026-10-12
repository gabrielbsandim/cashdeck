import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/widgets/charts/cd_bar_chart.dart';
import 'package:cashdeck/core/widgets/charts/cd_chart_scrub.dart';
import 'package:cashdeck/core/widgets/charts/cd_line_chart.dart';
import 'package:cashdeck/core/widgets/feedback/cd_haptics.dart';
import 'package:cashdeck/core/widgets/insights/cd_spend_chart.dart';
import 'package:cashdeck/core/widgets/layout/cd_expand_hero.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_count_up.dart';
import 'package:cashdeck/core/widgets/states/cd_shimmer.dart';
import 'package:cashdeck/core/widgets/states/cd_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/pump_app.dart';

String _brl(int cents) => MoneyFormat.format(Money(cents));

Widget _still(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: child,
);

/// Records every vibration the app asks the platform for.
List<String> _recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method.startsWith('HapticFeedback')) {
        calls.add('${call.method}:${call.arguments}');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

void main() {
  group('counting amounts', () {
    testWidgets('glide from the figure shown to the new one', (tester) async {
      Widget amount(int cents) => CdAmount(Money(cents), countUp: true);
      await tester.pumpApp(amount(10_000));
      await tester.pumpAndSettle();
      expect(find.text(_brl(10_000)), findsOneWidget);

      await tester.pumpApp(amount(20_000));
      await tester.pump(const Duration(milliseconds: 40));
      final shown = tester.widget<Text>(find.byType(Text)).data!;
      expect(shown, isNot(_brl(10_000)));
      expect(shown, isNot(_brl(20_000)));
      expect(shown, isNot(_brl(0)));

      await tester.pumpAndSettle();
      expect(find.text(_brl(20_000)), findsOneWidget);
    });

    testWidgets('land at once with reduced motion', (tester) async {
      await tester.pumpApp(_still(const CdAmount(Money(4_200), countUp: true)));
      expect(find.text(_brl(4_200)), findsOneWidget);
    });

    testWidgets('a hidden amount shows the mask and never counts', (
      tester,
    ) async {
      await tester.pumpApp(
        const CdAmount(Money(4_200), countUp: true),
        overrides: [hideAmountsProvider.overrideWithValue(true)],
      );
      expect(find.byType(CdCountUp), findsNothing);
      expect(
        find.text(MoneyFormat.format(const Money(4_200), hide: true)),
        findsOneWidget,
      );
    });
  });

  group('haptics', () {
    testWidgets('each moment asks for its own vibration', (tester) async {
      final calls = _recordHaptics(tester);

      CdHaptics.selection();
      CdHaptics.confirm();
      CdHaptics.warning();
      CdHaptics.celebrate();
      CdHaptics.outcome(null);
      CdHaptics.outcome(const NetworkFailure());
      await tester.pump();

      expect(calls, [
        'HapticFeedback.vibrate:HapticFeedbackType.selectionClick',
        'HapticFeedback.vibrate:HapticFeedbackType.mediumImpact',
        'HapticFeedback.vibrate:HapticFeedbackType.heavyImpact',
        'HapticFeedback.vibrate:HapticFeedbackType.heavyImpact',
        'HapticFeedback.vibrate:HapticFeedbackType.lightImpact',
        'HapticFeedback.vibrate:null',
      ]);
    });
  });

  group('skeletons', () {
    testWidgets('shimmer over the shapes each screen lists', (tester) async {
      await tester.pumpApp(
        const CdSkeleton(
          parts: [
            CdSkeletonHeadline(),
            CdSkeletonCard(),
            CdSkeletonCards(count: 2),
            CdSkeletonTiles(),
            CdSkeletonChips(count: 2),
            CdSkeletonRows(count: 2, header: true),
          ],
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(ShaderMask), findsOneWidget);
      expect(find.byType(CdBone), findsWidgets);
      expect(find.byType(CdSkeletonRows), findsOneWidget);
    });

    testWidgets('a plain skeleton is a list of rows', (tester) async {
      await tester.pumpApp(const CdSkeleton(rows: 2));
      expect(find.byType(CdSkeletonRows), findsOneWidget);
    });

    testWidgets('stay still with reduced motion', (tester) async {
      Widget shimmer({required bool still}) => MediaQuery(
        data: MediaQueryData(disableAnimations: still),
        child: const CdShimmer(child: CdBone(width: 40)),
      );
      await tester.pumpApp(shimmer(still: true));
      expect(find.byType(ShaderMask), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);

      await tester.pumpApp(shimmer(still: false));
      expect(find.byType(ShaderMask), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpApp(shimmer(still: true));
      expect(find.byType(ShaderMask), findsNothing);
      await tester.pumpAndSettle();
    });
  });

  group('chart scrubbing', () {
    Finder tooltip(String text) => find.descendant(
      of: find.byKey(CdChartScrub.tooltipKey),
      matching: find.text(text),
    );

    testWidgets('a drag reads the point under the finger, then lets go', (
      tester,
    ) async {
      final calls = _recordHaptics(tester);
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: CdLineChart(
            values: const [10, 30, 20],
            floor: 5,
            xLabels: const ['a', 'b'],
            semanticsLabel: 'saldo',
            pointLabel: (index) => 'ponto $index',
          ),
        ),
      );
      final chart = find.byType(CdChartScrub);
      final box = tester.getRect(chart);

      final gesture = await tester.startGesture(
        box.centerLeft + const Offset(2, 0),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(tooltip('ponto 0'), findsOneWidget);

      await gesture.moveTo(box.centerRight - const Offset(2, 0));
      await tester.pump();
      expect(tooltip('ponto 2'), findsOneWidget);
      expect(calls, isNotEmpty);

      await gesture.up();
      await tester.pump();
      expect(find.byKey(CdChartScrub.tooltipKey), findsNothing);
    });

    testWidgets('a tap keeps the point until the same point is tapped', (
      tester,
    ) async {
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: CdBarChart(
            groups: const [CdBarGroup('jan', 10, 5), CdBarGroup('fev', 8, 9)],
            incomeLabel: 'Ativos',
            expenseLabel: 'Dívidas',
            semanticsLabel: 'barras',
            groupLabel: (index) => 'grupo $index',
          ),
        ),
      );
      final box = tester.getRect(find.byType(CdChartScrub));

      await tester.tapAt(box.centerRight - const Offset(4, 0));
      await tester.pump();
      expect(tooltip('grupo 1'), findsOneWidget);

      await tester.tapAt(box.centerLeft + const Offset(4, 0));
      await tester.pump();
      expect(tooltip('grupo 0'), findsOneWidget);

      await tester.tapAt(box.centerLeft + const Offset(4, 0));
      await tester.pump();
      expect(find.byKey(CdChartScrub.tooltipKey), findsNothing);
    });

    testWidgets('the spend chart reads each day of this period', (
      tester,
    ) async {
      await tester.pumpApp(
        Padding(
          padding: const EdgeInsets.only(top: 80),
          child: CdSpendChart(
            current: const [0, 10, 25],
            previous: const [0, 5, 15, 20, 30],
            xLabels: const ['1', '5'],
            todayLabel: 'hoje',
            semanticsLabel: 'gastos',
            pointLabel: (index) => 'dia $index',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(CdChartScrub));

      await tester.tapAt(box.center);
      await tester.pump();
      expect(tooltip('dia 2'), findsOneWidget);
    });

    testWidgets('charts without labels do not scrub', (tester) async {
      await tester.pumpApp(
        const Column(
          children: [
            CdLineChart(values: [1, 2], xLabels: [], semanticsLabel: 'l'),
            CdBarChart(
              groups: [],
              incomeLabel: 'a',
              expenseLabel: 'b',
              semanticsLabel: 'b',
            ),
          ],
        ),
      );
      expect(find.byType(CdChartScrub), findsNothing);

      await tester.pumpApp(
        CdChartScrub(
          count: 0,
          labelOf: (_) => '',
          pointOf: (_, _) => Offset.zero,
          child: const Text('vazio'),
        ),
      );
      expect(find.text('vazio'), findsOneWidget);
    });
  });

  group('expanding cards', () {
    Widget app({required bool still}) {
      final child = Builder(
        builder: (context) => CdExpandHero(
          tag: CdExpandHero.tagOf('goal', '1'),
          child: Card(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: CdExpandHero(
                      tag: CdExpandHero.tagOf('goal', '1'),
                      child: const Center(child: Text('detalhe')),
                    ),
                  ),
                ),
              ),
              child: const Text('cartão'),
            ),
          ),
        ),
      );
      return still ? _still(child) : child;
    }

    testWidgets('the card grows into the screen and shrinks back', (
      tester,
    ) async {
      await tester.pumpApp(app(still: false));
      expect(find.byType(Hero), findsOneWidget);

      await tester.tap(find.text('cartão'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('detalhe'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('detalhe'), findsOneWidget);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text('cartão'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('detalhe'), findsNothing);
    });

    testWidgets('reduced motion keeps the plain transition', (tester) async {
      await tester.pumpApp(app(still: true));
      expect(find.byType(Hero), findsNothing);
    });
  });
}
