import 'package:cashdeck/core/money/money.dart';
import 'package:cashdeck/core/money/money_format.dart';
import 'package:cashdeck/core/preferences/display_preferences.dart';
import 'package:cashdeck/core/security/biometric_authenticator.dart';
import 'package:cashdeck/core/theme/money_tone.dart';
import 'package:cashdeck/core/widgets/feedback/cd_status_badge.dart';
import 'package:cashdeck/core/widgets/feedback/tone_icon.dart';
import 'package:cashdeck/core/widgets/money/cd_account_card.dart';
import 'package:cashdeck/core/widgets/money/cd_amount.dart';
import 'package:cashdeck/core/widgets/money/cd_bill_card.dart';
import 'package:cashdeck/core/widgets/money/cd_budget_bar.dart';
import 'package:cashdeck/core/widgets/money/cd_confirm_sheet.dart';
import 'package:cashdeck/core/widgets/money/cd_copy_field.dart';
import 'package:cashdeck/core/widgets/money/cd_transaction_row.dart';
import 'package:cashdeck/core/widgets/money/privacy_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../support/pump_app.dart';

void main() {
  const nbsp = '\u00A0';
  const minus = MoneyFormat.minus;

  group('CdAmount', () {
    testWidgets('signs by kind and follows the privacy toggle', (tester) async {
      await tester.pumpApp(
        const Column(
          children: [
            PrivacyToggle(),
            CdAmount(Money(1050), kind: CdAmountKind.expense),
            CdAmount(
              Money(-2000),
              size: CdAmountSize.xl,
              kind: CdAmountKind.income,
              showIcon: true,
            ),
            CdAmount(
              Money(-3000),
              size: CdAmountSize.lg,
              kind: CdAmountKind.transfer,
            ),
            CdAmount(Money(4000), size: CdAmountSize.sm, color: Colors.white),
            CdAmount(
              Money(1000, currency: 'USD'),
              kind: CdAmountKind.expense,
              converted: Money(5490),
              rateLabel: r'US$ 1 = R$ 5,49',
            ),
            CdAmount(
              Money(500, currency: 'EUR'),
              size: CdAmountSize.row,
              converted: Money(3000),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      );

      expect(find.text('${minus}R\$${nbsp}10,50'), findsOneWidget);
      expect(find.text('+R\$${nbsp}20,00'), findsOneWidget);
      expect(find.text('R\$${nbsp}30,00'), findsOneWidget);
      expect(find.text('R\$${nbsp}40,00'), findsOneWidget);
      expect(
        find.text('≈ ${minus}R\$${nbsp}54,90 · US\$ 1 = R\$ 5,49'),
        findsOneWidget,
      );
      expect(find.text('≈ R\$${nbsp}30,00'), findsOneWidget);
      expect(find.byIcon(MoneyTone.income.icon), findsOneWidget);

      await tester.tap(find.byKey(PrivacyToggle.buttonKey));
      await tester.pump();

      expect(find.textContaining('10,50'), findsNothing);
      expect(find.text('R\$$nbsp••••'), findsNWidgets(4));
      expect(find.byTooltip(l10n.showAmounts), findsOneWidget);
    });

    testWidgets('private text masks every figure inside a sentence', (
      tester,
    ) async {
      await tester.pumpApp(
        CdPrivateText(
          (hide) =>
              'Gastou ${MoneyFormat.format(const Money(990), hide: hide)}',
          maxLines: 1,
        ),
        overrides: [hideAmountsProvider.overrideWithValue(true)],
      );

      expect(find.text('Gastou R\$$nbsp••••'), findsOneWidget);
    });
  });

  testWidgets('cards and rows show amounts, hints and actions', (tester) async {
    final taps = <String>[];
    await tester.pumpApp(
      ListView(
        children: [
          CdAccountCard(
            monogram: 'BA',
            name: 'Banco Aurora',
            balance: const Money(100000),
            syncIcon: Symbols.sync_rounded,
            syncLabel: 'Há 4 min',
            onTap: () => taps.add('account'),
          ),
          CdBillCard(
            icon: Symbols.bolt_rounded,
            title: 'Energia',
            dueLabel: 'Vence 12/10',
            amount: const Money(28740),
            status: const CdStatusBadge(tone: MoneyTone.scheduled),
            ladderHint: 'Pix via API',
            onTap: () => taps.add('bill'),
          ),
          CdBillCard(
            icon: Symbols.home_rounded,
            title: 'Aluguel',
            dueLabel: 'Vence 15/10',
            amount: const Money(240000),
            status: const CdStatusBadge(tone: MoneyTone.assisted),
            action: TextButton(
              onPressed: () => taps.add('action'),
              child: const Text('Pagar'),
            ),
          ),
          const CdBillCard(
            icon: Symbols.home_rounded,
            title: 'Sem dica',
            dueLabel: 'Vence 16/10',
            amount: Money(100),
            status: SizedBox(),
          ),
          CdBillRow(
            icon: Symbols.wifi_rounded,
            title: 'Internet',
            amount: const Money(11990),
            dateLabel: 'Ontem',
            status: const Text('Falhou'),
            onTap: () => taps.add('row'),
          ),
          const CdBillRow(
            icon: Symbols.wifi_rounded,
            title: 'Sem data',
            amount: Money(100),
            dateLabel: null,
            leading: Text('PJ'),
            status: SizedBox(),
          ),
          CdTransactionRow(
            icon: Symbols.flight_rounded,
            title: 'Hotel',
            subtitle: 'Cartão Viagem',
            amount: const Money(41200, currency: 'USD'),
            converted: const Money(226188),
            badge: const Text('Revisar'),
            onTap: () => taps.add('transaction'),
          ),
          const CdTransactionRow(
            icon: Symbols.payments_rounded,
            title: 'Salário',
            subtitle: 'Pix',
            amount: Money(780000),
            kind: CdAmountKind.income,
            leading: Text('PF'),
          ),
        ],
      ),
    );

    for (final label in ['Banco Aurora', 'Energia', 'Pagar', 'Internet']) {
      await tester.tap(find.text(label));
    }
    await tester.tap(find.text('Hotel'));

    expect(taps, ['account', 'bill', 'action', 'row', 'transaction']);
    expect(find.text('Pix via API'), findsOneWidget);
    expect(find.text('Ontem'), findsOneWidget);
    expect(find.text('Revisar'), findsOneWidget);
  });

  testWidgets('the paid pop springs in, or stays still with reduced motion', (
    tester,
  ) async {
    await tester.pumpApp(const CdPaidPop(child: Text('Paga')));
    expect(find.byType(ScaleTransition), findsWidgets);
    await tester.pumpAndSettle();

    await tester.pumpApp(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: CdPaidPop(child: Text('Parada')),
      ),
    );
    expect(find.text('Parada'), findsOneWidget);
  });

  testWidgets('budget bars warn at 80% and 100%', (tester) async {
    await tester.pumpApp(
      const Column(
        children: [
          CdBudgetBar(
            icon: Symbols.directions_bus_rounded,
            name: 'Transporte',
            spent: Money(15200),
            limit: Money(40000),
          ),
          CdBudgetBar(
            icon: Symbols.shopping_cart_rounded,
            name: 'Mercado',
            spent: Money(98400),
            limit: Money(120000),
            showAmounts: true,
          ),
          CdBudgetBar(
            icon: Symbols.restaurant_rounded,
            name: 'Restaurantes',
            spent: Money(62400),
            limit: Money(60000),
          ),
          CdBudgetBar(
            icon: Symbols.help_rounded,
            name: 'Sem limite',
            spent: Money(100),
            limit: Money(0),
          ),
        ],
      ),
    );

    expect(find.text('38%'), findsOneWidget);
    expect(find.text('R\$${nbsp}984 / R\$${nbsp}1.200'), findsOneWidget);
    expect(find.text(l10n.budgetAttention), findsOneWidget);
    expect(find.text(l10n.budgetExceeded), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(
      find.bySemanticsLabel(l10n.budgetSemantics('Restaurantes', '104')),
      findsOneWidget,
    );
  });

  group('CdConfirmSheet', () {
    Future<({Future<bool?> closed})> open(
      WidgetTester tester,
      FakeBiometricAuthenticator biometrics, {
      String? secondary,
    }) async {
      late BuildContext context;
      await tester.pumpApp(
        Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
        overrides: [
          biometricAuthenticatorProvider.overrideWithValue(biometrics),
        ],
      );
      final result = showCdConfirmSheet(
        context,
        title: 'Confirmar pagamento',
        reason: 'Novo favorecido',
        secondaryLabel: secondary,
        confirmLabel: 'Confirmar',
        rows: const [CdConfirmRow('Valor', r'R$ 149,90')],
      );
      await tester.pumpAndSettle();
      return (closed: result);
    }

    testWidgets('resolves true only after the device check passes', (
      tester,
    ) async {
      final biometrics = FakeBiometricAuthenticator(approve: false);
      final result = (await open(tester, biometrics)).closed;

      expect(find.text('Novo favorecido'), findsOneWidget);
      expect(find.text(r'R$ 149,90'), findsOneWidget);
      await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
      await tester.pumpAndSettle();
      expect(find.text(l10n.confirmDenied), findsOneWidget);

      biometrics.approve = true;
      await tester.tap(find.byKey(CdConfirmSheet.confirmKey));
      await tester.pumpAndSettle();

      expect(await result, isTrue);
      expect(biometrics.reasons, [
        'Confirmar pagamento',
        'Confirmar pagamento',
      ]);
    });

    testWidgets('the secondary action declines', (tester) async {
      final result = (await open(
        tester,
        FakeBiometricAuthenticator(),
        secondary: 'Pagar eu mesmo',
      )).closed;

      await tester.tap(find.byKey(CdConfirmSheet.secondaryKey));
      await tester.pumpAndSettle();

      expect(await result, isFalse);
    });
  });

  testWidgets('the copy field copies and confirms for two seconds', (
    tester,
  ) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add(
            (call.arguments as Map<Object?, Object?>)['text']! as String,
          );
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
    await tester.pumpApp(
      const Column(
        children: [
          CdCopyField(
            code: '23793.38128',
            label: 'Linha digitável',
            valid: true,
            buttonKey: Key('full'),
          ),
          CdCopyField(
            code: 'pix-payload',
            compact: true,
            buttonKey: Key('compact'),
          ),
        ],
      ),
    );

    expect(find.text('LINHA DIGITÁVEL'), findsOneWidget);
    expect(find.text(l10n.codeValid), findsOneWidget);
    await tester.tap(find.byKey(const Key('full')));
    await tester.tap(find.byKey(const Key('compact')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(copied, ['23793.38128', 'pix-payload']);
    expect(find.text(l10n.copied), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(l10n.copied), findsNothing);
    expect(find.text(l10n.copyShort), findsOneWidget);
    expect(find.text(l10n.copyCodeButton), findsOneWidget);
  });

  test('a privacy toggle flips the shared preference', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(displayPreferencesProvider.notifier).toggleHideAmounts();

    expect(container.read(hideAmountsProvider), isTrue);
  });
}
