import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/money/cd_payment_ladder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  CdLadderStep step(
    int number,
    CdLadderState state, {
    String? summary,
    List<Widget> actions = const [],
    String? body,
  }) => CdLadderStep(
    number: number,
    title: 'Passo $number',
    icon: Symbols.bolt_rounded,
    state: state,
    tone: MoneyTone.scheduled,
    key: Key('step-$number-${state.name}'),
    summary: summary,
    actions: actions,
    body: body,
    badge: state == CdLadderState.failed
        ? const CdStatusBadge(tone: MoneyTone.failed, label: 'Falhou')
        : null,
    trailingLabel: state == CdLadderState.upcoming ? 'Rede de segurança' : null,
    lines: const [
      CdLadderLine('Pix via API, sem saldo', time: '07:00'),
      CdLadderLine('Sem horário'),
    ],
    stepDown: state == CdLadderState.failed ? 'Desceu para o passo 3' : null,
  );

  testWidgets('every state draws, and a collapsed step opens on tap', (
    tester,
  ) async {
    var marked = false;
    await tester.pumpApp(
      SingleChildScrollView(
        child: CdPaymentLadder(
          title: 'Escada de pagamento',
          subtitle: 'PF · passo 3 de 3',
          nextAction: 'Aprove no banco até 18h',
          footnote: 'Vence 15/10',
          steps: [
            step(1, CdLadderState.failed, summary: 'Falhou 3 vezes'),
            step(2, CdLadderState.skipped, body: 'Não disponível'),
            step(3, CdLadderState.done),
            step(4, CdLadderState.active),
            step(5, CdLadderState.expired),
            step(6, CdLadderState.upcoming),
            step(
              7,
              CdLadderState.ready,
              body: 'Pague com o código',
              actions: [
                TextButton(
                  onPressed: () => marked = true,
                  child: const Text('Marcar como paga'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    expect(find.text('Falhou 3 vezes'), findsOneWidget);
    expect(find.text('Desceu para o passo 3'), findsNothing);
    await tester.tap(find.text('Falhou 3 vezes'));
    await tester.pump();
    expect(find.text('Desceu para o passo 3'), findsOneWidget);

    expect(find.text('2 · Passo 2'), findsOneWidget);
    expect(find.text('Não disponível'), findsOneWidget);
    expect(find.text('Rede de segurança'), findsOneWidget);
    expect(find.text('Aprove no banco até 18h'), findsOneWidget);
    expect(find.text('Vence 15/10'), findsOneWidget);
    expect(find.text('07:00'), findsWidgets);
    expect(find.byIcon(Symbols.block_rounded), findsOneWidget);

    await tester.ensureVisible(find.text('Marcar como paga'));
    await tester.tap(find.text('Marcar como paga'));
    expect(marked, isTrue);
  });

  testWidgets('a ladder without a next action or footnote stays short', (
    tester,
  ) async {
    await tester.pumpApp(
      CdPaymentLadder(
        title: 'Escada',
        subtitle: 'Paga',
        steps: [step(1, CdLadderState.done)],
      ),
    );

    expect(find.text('1 · Passo 1'), findsOneWidget);
    expect(find.byIcon(Symbols.notifications_active_rounded), findsNothing);
  });
}
