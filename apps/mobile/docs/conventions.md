# Code conventions

A violation is a defect. Companion documents: [architecture.md](architecture.md)
and [testing.md](testing.md).

## Imports

Package imports only (`package:cashdeck/...`), never a relative path. The one
exception is a test importing `test/support`.

## This is Dart 3.13

`environment.sdk` is `^3.13.5`. Two forms that look wrong to an older model are
the house style, and `dart fix` produces them:

```dart
final class ListBills {
  const new(this._repository);   // `new` instead of repeating the class name
  final BillsRepository _repository;
}

final class MockBillsRepository extends Mock implements BillsRepository;
```

When unsure about an API, read the SDK or the package source in `~/.pub-cache`
rather than recalling it.

## Dart

- Lints: `very_good_analysis`, tuned in `analysis_options.yaml`.
- `final` by default. Value classes extend `Equatable` and are immutable.
- Contracts are `abstract interface class`. Closed hierarchies (`Result`,
  `AppFailure`) are `sealed` and consumed with an exhaustive `switch`.
- JSON is read through `core/network/json_reader.dart`, which throws
  `FormatException` on a wrong shape; `guardRequest` maps that to
  `UnexpectedFailure`. No `as` casts on network data.
- Formatting is `dart format`.

## Control flow

No `if` inside an `if`, no `else` after `return`, three or more branches on one
value become a `switch` or a table, no nested ternary.

## Naming

| Context              | Convention                 | Example                         |
| -------------------- | -------------------------- | ------------------------------- |
| Files and folders    | snake_case                 | `bills_use_cases.dart`          |
| Contracts (ports)    | PascalCase noun            | `BillsRepository`               |
| Implementations      | Technology or role prefix  | `ApiBillsRepository`, `FakeBillsRepository` |
| Use cases            | Verb phrase                | `ListBills`, `GetBill`          |
| Screens              | PascalCase + `Screen`      | `BillDetailScreen`              |
| Controllers          | PascalCase + `Controller`  | `BillsController`               |
| Providers            | camelCase + `Provider`     | `billsRepositoryProvider`       |

## Errors

Repositories return `Result<T>`. `core/network/api_error_mapper.dart` maps
once:

| Failure               | When                                               |
| --------------------- | -------------------------------------------------- |
| `NetworkFailure`      | No connection, timeout                             |
| `UnauthorizedFailure` | 401                                                |
| `ForbiddenFailure`    | 403                                                |
| `NotFoundFailure`     | 404                                                |
| `ValidationFailure`   | 400, 409, 422 with `error.message`, shown as is    |
| `RateLimitedFailure`  | 429                                                |
| `ServerFailure`       | 5xx                                                |
| `UnexpectedFailure`   | Anything else, including a JSON shape we did not expect |

Controllers turn an `Err` into a thrown `LoadFailure`, so screens read it from
`AsyncError` with `failureOf(error)` and show `ErrorState` with a retry.

## Money, dates, language

- Money is `Money(cents, currency: 'BRL')`, never a `double`. Shown through
  `AmountText` (privacy aware) or `MoneyFormat.format`: `R$ 1.234,56`,
  `-R$ 1.234,56`, a foreign currency with its ISO code.
- Due dates are `CalendarDate`, travel as `YYYY-MM-DD`, and "today" is
  computed in Brazil time (`CalendarDate.brazilToday`).
- pt-BR is the default language; English is the second. The device language
  wins when the app speaks it (`CashdeckApp.resolveLocale`).
