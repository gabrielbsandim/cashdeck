import 'package:cashdeck/app/router/app_routes.dart';
import 'package:cashdeck/core/error/app_failure.dart';
import 'package:cashdeck/core/result/result.dart';
import 'package:cashdeck/core/widgets/states/cd_error_state.dart';
import 'package:cashdeck/features/entities/domain/entity_profile.dart';
import 'package:cashdeck/features/entities/domain/entity_scope.dart';
import 'package:cashdeck/features/entities/entities_providers.dart';
import 'package:cashdeck/features/entities/presentation/entity_profiles_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_harness.dart';
import '../../../support/pump_app.dart';

const _rejection = 'Tax id is not a valid CPF or CNPJ.';

final class _Rejecting implements EntityProfileRepository {
  bool failList = true;

  @override
  Future<Result<List<EntityProfile>>> list() async {
    if (failList) return const Err(NetworkFailure());
    return const Ok([
      EntityProfile(
        id: 'personal',
        kind: EntityKind.personal,
        name: 'Conta pessoal',
        taxId: '52998224725',
      ),
    ]);
  }

  @override
  Future<Result<EntityProfile>> update(EntityProfile profile) async =>
      const Err(ValidationFailure(_rejection));
}

Finder _field(Key key) =>
    find.descendant(of: find.byKey(key), matching: find.byType(TextField));

void main() {
  const personal = EntityKind.personal;
  const company = EntityKind.company;

  testWidgets('edits the company and the new name shows', (tester) async {
    await pumpRoute(tester, AppRoutes.entityProfiles);
    expect(find.text(l10n.profilesTitle), findsOneWidget);
    expect(find.text(l10n.profilesIntro), findsOneWidget);
    expect(find.text('529.982.247-25'), findsOneWidget);
    expect(find.text('11.222.333/0001-81'), findsOneWidget);
    expect(find.byKey(EntityProfilesScreen.regimeKey), findsOneWidget);

    await tester.enterText(
      _field(EntityProfilesScreen.nameKey(company)),
      'Empresa Nova Ltda',
    );
    await tester.enterText(
      _field(EntityProfilesScreen.taxIdKey(company)),
      '11444777000161',
    );
    await tester.tap(find.byKey(EntityProfilesScreen.regimeKey));
    await settle(tester);
    await tester.tap(find.text(l10n.taxRegimeLucroPresumido).last);
    await settle(tester);
    expect(find.text('11.444.777/0001-61'), findsOneWidget);
    expect(find.text('Empresa Nova Ltda'), findsOneWidget);

    await tester.tap(find.byKey(EntityProfilesScreen.saveKey(company)));
    await settle(tester);

    expect(find.text(l10n.profileSavedToast), findsOneWidget);
    expect(find.text('Empresa Nova Ltda'), findsNWidgets(2));
    expect(find.text(l10n.taxRegimeLucroPresumido), findsOneWidget);
  });

  testWidgets('checks the name and the check digits before sending', (
    tester,
  ) async {
    await pumpRoute(tester, AppRoutes.entityProfiles);

    await tester.enterText(_field(EntityProfilesScreen.nameKey(personal)), ' ');
    await tester.enterText(
      _field(EntityProfilesScreen.taxIdKey(personal)),
      '52998224724',
    );
    await tester.enterText(
      _field(EntityProfilesScreen.taxIdKey(company)),
      '11222333000182',
    );
    await tester.tap(find.byKey(EntityProfilesScreen.saveKey(personal)));
    await tester.tap(find.byKey(EntityProfilesScreen.saveKey(company)));
    await settle(tester);

    expect(find.text(l10n.profileNameRequired), findsOneWidget);
    expect(find.text(l10n.profileCpfInvalid), findsOneWidget);
    expect(find.text(l10n.profileCnpjInvalid), findsOneWidget);
    expect(find.text(l10n.profileSavedToast), findsNothing);
  });

  testWidgets('a failed load retries and a rejected id shows why', (
    tester,
  ) async {
    final repository = _Rejecting();
    await pumpRoute(
      tester,
      AppRoutes.entityProfiles,
      overrides: [
        entityProfileRepositoryProvider.overrideWithValue(repository),
      ],
    );
    expect(find.text(l10n.errorNetwork), findsOneWidget);

    repository.failList = false;
    await tester.tap(find.byKey(CdErrorState.retryKey));
    await settle(tester);
    expect(find.byKey(EntityProfilesScreen.regimeKey), findsNothing);

    await tester.tap(find.byKey(EntityProfilesScreen.saveKey(personal)));
    await settle(tester);

    expect(find.text(_rejection), findsNWidgets(2));
  });
}
