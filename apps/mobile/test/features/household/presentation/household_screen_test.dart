import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/error/failure_message.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/features/household/domain/household.dart';
import 'package:cashdeck/features/household/household_providers.dart';
import 'package:cashdeck/features/household/presentation/household_controller.dart';
import 'package:cashdeck/features/household/presentation/household_member_sheet.dart';
import 'package:cashdeck/features/household/presentation/household_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/app_harness.dart';
import '../../../support/mocks.dart';
import '../../../support/pump_app.dart';

const _cpf = '11144477735';
const _member = HouseholdMember(name: 'Ana Exemplo', taxId: _cpf);

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(HouseholdScreen.addKey));
  await settle(tester);
}

Future<void> _fill(WidgetTester tester, {String? name, String? cpf}) async {
  for (final (field, text) in [
    (HouseholdMemberSheet.nameKey, name),
    (HouseholdMemberSheet.cpfKey, cpf),
  ]) {
    if (text == null) continue;
    await tester.enterText(find.byKey(field), text);
    await tester.pump();
  }
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.byKey(HouseholdMemberSheet.saveKey));
  await settle(tester);
}

void main() {
  setUpAll(() => registerFallbackValue(const Household([])));

  testWidgets('lists the members with the CPF masked and the why', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.household);

    expect(find.text(l10n.householdTitle), findsOneWidget);
    expect(find.text(l10n.householdIntro), findsOneWidget);
    expect(find.byKey(HouseholdScreen.rowKey(_cpf)), findsOneWidget);
    expect(find.text('Ana Exemplo'), findsOneWidget);
    expect(find.text(l10n.householdCpfLine('***.444.777-**')), findsOneWidget);
    expect(find.textContaining('111.444.777-35'), findsNothing);
  });

  testWidgets('checks the form before saving', (tester) async {
    await pumpRoute(tester, AppRoutes.household);
    await _openSheet(tester);

    await _save(tester);
    expect(find.text(l10n.householdNameMissing), findsOneWidget);

    await _fill(tester, name: 'Bia Exemplo', cpf: '11144477734');
    await _save(tester);
    expect(find.text('111.444.777-34'), findsOneWidget);
    expect(find.text(l10n.householdCpfInvalid), findsOneWidget);

    await _fill(tester, cpf: '11144477735');
    await _save(tester);
    expect(find.text(l10n.householdCpfTaken), findsOneWidget);
  });

  testWidgets('removes a member and adds one, saving the whole list', (
    tester,
  ) async {
    final app = await pumpRoute(tester, AppRoutes.household);

    await tester.tap(find.byKey(HouseholdScreen.removeKey(_cpf)));
    await settle(tester);

    expect(find.text(l10n.householdMemberRemoved('Ana Exemplo')), findsOne);
    expect(find.text(l10n.householdEmptyTitle), findsOneWidget);
    expect(app.read(householdControllerProvider).value, const Household([]));
    await waitForToast(tester);

    await _openSheet(tester);
    await _fill(tester, name: ' Ana Exemplo ', cpf: '111.444.777-35');
    await _save(tester);

    expect(find.text(l10n.householdMemberAdded), findsOneWidget);
    expect(find.byKey(HouseholdScreen.rowKey(_cpf)), findsOneWidget);
    expect(
      app.read(householdControllerProvider).value,
      const Household([_member]),
    );
  });

  group('with a mocked server', () {
    late MockHouseholdRepository repository;

    Future<void> open(WidgetTester tester) => pumpRoute(
      tester,
      AppRoutes.household,
      overrides: [householdRepositoryProvider.overrideWithValue(repository)],
    );

    setUp(() => repository = MockHouseholdRepository());

    testWidgets('a load that fails can be tried again', (tester) async {
      when(repository.get).thenAnswer((_) async => const Err(NetworkFailure()));

      await open(tester);

      expect(find.byKey(HouseholdScreen.addKey), findsNothing);
      when(repository.get)
          .thenAnswer((_) async => const Ok(Household([_member])));
      await tester.tap(find.text(l10n.retryButton));
      await settle(tester);

      expect(find.byKey(HouseholdScreen.rowKey(_cpf)), findsOneWidget);
    });

    testWidgets('a refused save says why and keeps the list', (tester) async {
      when(repository.get)
          .thenAnswer((_) async => const Ok(Household([_member])));
      when(() => repository.save(any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      await open(tester);

      await tester.tap(find.byKey(HouseholdScreen.removeKey(_cpf)));
      await settle(tester);

      expect(find.text(const NetworkFailure().userMessage(l10n)), findsOne);
      expect(find.byKey(HouseholdScreen.rowKey(_cpf)), findsOneWidget);
    });

    testWidgets('the server refusing a new member shows in the form', (
      tester,
    ) async {
      when(repository.get).thenAnswer((_) async => const Ok(Household([])));
      when(
        () => repository.save(any()),
      ).thenAnswer((_) async => const Err(ValidationFailure('CPF recusado.')));
      await open(tester);

      await _openSheet(tester);
      await _fill(tester, name: 'Ana Exemplo', cpf: '111.444.777-35');
      await _save(tester);

      expect(find.byKey(HouseholdMemberSheet.errorKey), findsOneWidget);
      expect(find.text('CPF recusado.'), findsOneWidget);
    });

    testWidgets('a full household offers no add', (tester) async {
      final members = [
        for (var index = 0; index < Household.maxMembers; index++)
          HouseholdMember(name: 'Pessoa $index', taxId: 'member-$index'),
      ];
      when(repository.get).thenAnswer((_) async => Ok(Household(members)));

      await open(tester);

      expect(find.byKey(HouseholdScreen.addKey), findsNothing);
      expect(find.text(l10n.householdFull(Household.maxMembers)), findsOne);
    });
  });

  test('every problem has a message', () {
    for (final problem in MemberProblem.values) {
      expect(memberProblemLabel(l10n, problem), isNotEmpty);
    }
  });
}
