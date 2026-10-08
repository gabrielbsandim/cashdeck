# Testing

A feature or a fix is complete only when it ships with tests. Coverage is
enforced per layer.

## Running

```bash
flutter test                  # everything, no thresholds
flutter test test/features    # one folder
tool/check.sh                 # format, analyze, coverage, thresholds
```

Only `tool/check.sh` checks thresholds, and CI runs it.

## Thresholds

Defined in `tool/coverage_gate.dart`, on line coverage:

| Scope                     | Minimum |
| ------------------------- | ------- |
| `features/*/domain/`      | 100%    |
| `features/*/application/` | 100%    |
| `lib/core/`               | 95%     |
| Everything                | 90%     |

`lib/main.dart` and the generated localizations are excluded. The gate prints
every file below 100%, worst first.

## Where a test goes

`test/` mirrors `lib/`.

| Layer        | Kind of test              | Doubles                                     |
| ------------ | ------------------------- | ------------------------------------------- |
| domain       | Plain unit test           | Builders from `test/support/builders.dart`  |
| application  | Unit test                 | `MockBillsRepository` (mocktail)            |
| data         | Unit test over HTTP       | `stubDio` from `test/support/stub_http_adapter.dart` |
| presentation | `testWidgets` + `pumpApp` | Repository and `clockProvider` overrides    |
| app          | End to end on the fake backend | `FakeBillsRepository(latency: Duration.zero)` and a `FixedClock` |

## Shared support

| File                                  | Gives you                                     |
| ------------------------------------- | --------------------------------------------- |
| `test/support/pump_app.dart`          | `tester.pumpApp(widget, overrides:, dark:)` with pt localization and the theme, plus a top-level `l10n` |
| `test/support/builders.dart`          | `testNow`, `testToday`, `testBill`, `testAttempt`, `billJson` |
| `test/support/mocks.dart`             | mocktail mocks of ports                       |
| `test/support/stub_http_adapter.dart` | `stubDio(handler)`, `adapterOf(dio).requests` |

## Rules

- Assert on user-visible text through `l10n`, never a hardcoded copy.
- Screens expose `Key` constants for what tests drive (`BillsScreen.tileKey`).
- The test environment's locale is English; an app-level test pins
  `localesTestValue` to pt-BR.
- `test/architecture/layer_rules_test.dart` is part of the suite.
