import 'package:cashdeck/core/theme/app_chart_colors.dart';
import 'package:cashdeck/core/theme/app_money_colors.dart';
import 'package:cashdeck/core/time/calendar_date.dart';
import 'package:cashdeck/core/time/year_month.dart';
import 'package:cashdeck/core/widgets/insights/cd_calendar_month.dart';
import 'package:cashdeck/core/widgets/insights/cd_column_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_comparison_pill.dart';
import 'package:cashdeck/core/widgets/insights/cd_flow_bars.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_card.dart';
import 'package:cashdeck/core/widgets/insights/cd_insight_row.dart';
import 'package:cashdeck/core/widgets/insights/cd_institution_logo.dart';
import 'package:cashdeck/core/widgets/insights/cd_segment_bar.dart';
import 'package:cashdeck/core/widgets/insights/cd_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  const colors = SeriesColors(
    fill: Color(0xFF4C7DD9),
    foreground: Color(0xFF305EB7),
    container: Color(0xFFDDEEFF),
  );

  group('CdCalendarMonth', () {
    testWidgets('starts on the right weekday, rings today and selects', (
      tester,
    ) async {
      CalendarDate? picked;
      await tester.pumpApp(
        CdCalendarMonth(
          month: const YearMonth(2026, 10),
          weekdays: const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'],
          today: const CalendarDate(2026, 10, 8),
          selected: const CalendarDate(2026, 10, 12),
          dots: const {
            5: [Color(0xFF00FF00), Color(0xFFFF0000), Color(0xFF0000FF)],
            12: [Color(0xFF00FF00)],
          },
          onSelect: (date) => picked = date,
        ),
      );

      expect(find.text('31'), findsOneWidget);
      expect(find.text('32'), findsNothing);
      final first = tester.getTopLeft(find.byKey(CdCalendarMonth.dayKey(1)));
      final sunday = tester.getTopLeft(find.byKey(CdCalendarMonth.dayKey(4)));
      expect(first.dx, greaterThan(sunday.dx));

      await tester.tap(find.byKey(CdCalendarMonth.dayKey(20)));
      expect(picked, const CalendarDate(2026, 10, 20));
    });

    testWidgets('without a handler the days are not buttons', (tester) async {
      await tester.pumpApp(
        const CdCalendarMonth(
          month: YearMonth(2026, 2),
          weekdays: ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'],
          today: CalendarDate(2026, 10, 8),
        ),
      );

      expect(find.text('28'), findsOneWidget);
      expect(find.text('29'), findsNothing);
      await tester.tap(find.byKey(CdCalendarMonth.dayKey(3)));
    });
  });

  group('CdInstitutionLogo', () {
    test('picks the monogram from the meaningful words', () {
      expect(CdInstitutionLogo.monogram('Banco Aurora'), 'BA');
      expect(CdInstitutionLogo.monogram('Nuvem Pagamentos'), 'NP');
      expect(CdInstitutionLogo.monogram('Aurora'), 'AU');
      expect(CdInstitutionLogo.monogram('X'), 'X');
      expect(CdInstitutionLogo.monogram('Banco de Serra'), 'BS');
      expect(CdInstitutionLogo.monogram('Banco do Brasil Leste'), 'BL');
      expect(CdInstitutionLogo.monogram('Banco de'), 'BD');
      expect(CdInstitutionLogo.monogram('  '), '');
    });

    testWidgets('falls back to the monogram while or when the image fails', (
      tester,
    ) async {
      await tester.pumpApp(
        const Column(
          children: [
            CdInstitutionLogo(name: 'Banco Aurora', colors: colors),
            CdInstitutionLogo(
              name: 'Nuvem Pagamentos',
              colors: colors,
              imageUrl: 'https://example.test/logo.png',
            ),
          ],
        ),
      );
      await tester.pump();

      expect(find.text('BA'), findsOneWidget);
      expect(find.text('NP'), findsOneWidget);
    });

    test('tells an SVG logo by its path', () {
      expect(CdInstitutionLogo.isSvg('https://cdn.test/icons/726.svg'), isTrue);
      expect(CdInstitutionLogo.isSvg('https://cdn.test/a.SVG?v=2'), isTrue);
      expect(
        CdInstitutionLogo.isSvg('https://cdn.test/icons/804.png'),
        isFalse,
      );
    });

    testWidgets('draws an SVG logo, the monogram while it loads', (
      tester,
    ) async {
      CdInstitutionLogo.debugSvgClient = MockClient(
        (_) async => http.Response(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"> '
          '<style>.a{fill:#3263C3}</style> '
          '<rect class="a" width="10" height="10"/></svg>',
          200,
        ),
      );
      addTearDown(() => CdInstitutionLogo.debugSvgClient = null);
      await tester.pumpApp(
        const CdInstitutionLogo(
          name: 'Banco Aurora',
          colors: colors,
          imageUrl: 'https://example.test/logo.svg',
        ),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.text('BA'), findsOneWidget);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(find.text('BA'), findsNothing);
    });
  });

  testWidgets('CdTimeline marks done, current and future steps', (
    tester,
  ) async {
    await tester.pumpApp(
      const CdTimeline(
        entries: [
          CdTimelineEntry(
            title: 'Parcela 1',
            subtitle: 'Agosto',
            trailing: Text(r'R$ 10'),
            state: CdTimelineState.done,
          ),
          CdTimelineEntry(
            title: 'Parcela 2',
            subtitle: 'Setembro',
            trailing: Text(r'R$ 10'),
            state: CdTimelineState.current,
          ),
          CdTimelineEntry(
            title: 'Parcela 3',
            subtitle: 'Outubro',
            trailing: Text(r'R$ 10'),
            state: CdTimelineState.future,
          ),
        ],
      ),
    );

    expect(find.text('Parcela 2'), findsOneWidget);
    expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
  });

  testWidgets('CdInsightCard shows its action and CdInsightRow its chevron', (
    tester,
  ) async {
    var actions = 0;
    var taps = 0;
    await tester.pumpApp(
      Builder(
        builder: (context) => Column(
          children: [
            CdInsightCard(
              title: 'Resumo',
              actionLabel: 'Ver todas',
              onAction: () => actions++,
              child: const SizedBox(height: 10),
            ),
            CdInsightRow(
              icon: Symbols.savings_rounded,
              tone: ToneColors(
                foreground: context.money.paid,
                background: context.money.paidContainer,
              ),
              sentence: 'Você guardou mais',
              onTap: () => taps++,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Ver todas'));
    await tester.tap(find.text('Você guardou mais'));
    expect((actions, taps), (1, 1));
    expect(find.byIcon(Symbols.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('CdComparisonPill is neutral at zero and shows its label', (
    tester,
  ) async {
    await tester.pumpApp(
      const Column(
        children: [
          CdComparisonPill(direction: 0, value: '0%', label: 'vs setembro'),
          CdComparisonPill(direction: 1, value: '5%', goodWhen: GoodWhen.up),
          CdComparisonPill(direction: -1, value: '5%'),
        ],
      ),
    );

    expect(find.text('vs setembro'), findsOneWidget);
    expect(find.byIcon(Symbols.remove_rounded), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_upward_rounded), findsOneWidget);
  });

  testWidgets('CdSegmentBar draws an empty track when every value is zero', (
    tester,
  ) async {
    await tester.pumpApp(
      const CdSegmentBar(
        semanticsLabel: 'Saldo',
        segments: [CdBarSegment(0, Color(0xFF000000))],
      ),
    );

    expect(find.bySemanticsLabel('Saldo'), findsOneWidget);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
  });

  testWidgets('CdSegmentBar fills each segment to the full height', (
    tester,
  ) async {
    await tester.pumpApp(
      const CdSegmentBar(
        semanticsLabel: 'Saldo',
        segments: [
          CdBarSegment(3, Color(0xFF000000)),
          CdBarSegment(1, Color(0xFFFFFFFF)),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final fills = find.byType(FractionallySizedBox).evaluate().toList();
    expect(fills, hasLength(2));
    for (final fill in fills) {
      expect(tester.getSize(find.byWidget(fill.widget)).height, greaterThan(0));
    }
  });

  testWidgets('CdFlowBars fills both bars on one scale', (tester) async {
    await tester.pumpApp(
      const CdFlowBars(
        income: 400,
        expenses: 100,
        incomeLabel: 'In',
        expensesLabel: 'Out',
        incomeAmount: Text('400'),
        expensesAmount: Text('100'),
      ),
    );
    await tester.pumpAndSettle();

    final fills = tester
        .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .toList();
    expect(fills.map((fill) => fill.widthFactor), [1, 0.25]);
    for (final fill in find.byType(FractionallySizedBox).evaluate()) {
      expect(tester.getSize(find.byWidget(fill.widget)).height, 10);
    }
  });

  testWidgets('CdColumnBars prints a caption under the label', (tester) async {
    await tester.pumpApp(
      const CdColumnBars(
        semanticsLabel: 'Meses',
        columns: [
          CdBarColumn(
            label: 'out',
            caption: '2,2 mil',
            bars: [(10, Color(0xFF000000))],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2,2 mil'), findsOneWidget);
  });
}
