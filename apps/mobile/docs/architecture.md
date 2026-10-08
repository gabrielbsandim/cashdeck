# Architecture

The app is a **client of the Cashdeck API**. Rules that decide money (which
rail pays a bill, caps, tax estimates) live on the server. The app owns the
experience: reading, capturing, confirming, and showing where every bill
stands on the payment ladder.

The structure is **feature-first clean architecture**: one folder per product
area, each split into the same four layers, plus a shared `core`.

## Guiding principles

1. **Modular by feature.** Deleting a feature is deleting a folder.
2. **Dependencies point inward.** `presentation` to `application` to `domain`,
   and `data` to `domain`. The domain imports nothing from the other three.
3. **The domain is plain Dart.** No Flutter, no Dio, no Riverpod, no JSON.
4. **External systems sit behind ports**, abstract in `domain` (or `core`),
   concrete in `data` (or `core`).
5. **The fake backend is the default.** A fresh clone runs with no server:
   `BACKEND=fake` wires in-memory repositories with fictional data. The real
   API is opt-in with `--dart-define=BACKEND=api` and
   `--dart-define=API_BASE_URL=<url>`.
6. **Errors are values.** Repositories return `Result<T>`, never throw across a
   layer boundary.

## Folder layout

```
lib/
  main.dart                 entrypoint: pt_BR intl default, ProviderScope
  app/
    app.dart                MaterialApp.router, light and dark themes, locale
    router/                 GoRouter and route paths
    shell/                  the five-tab bottom navigation
  core/
    config/                 AppConfig from --dart-define
    di/                     core providers (AppConfig, Dio, Clock)
    error/                  AppFailure (sealed), LoadFailure, user messages
    result/                 Result<T> (sealed)
    money/                  Money (integer cents + currency), MoneyFormat
    network/                Dio factory, error mapping, guardRequest, JSON reading
    preferences/            theme mode and the privacy toggle (hide amounts)
    time/                   Clock port, CalendarDate, Brazil local time
    theme/                  tokens (AppPalette, spacing, radius, motion, type)
    widgets/                design system components, see design.md
  features/
    entities/               PF, PJ, consolidated scope and the switcher
    bills/                  bills list, bill detail, the payment ladder
    home/ transactions/ chat/   tab placeholders until the design lands
    settings/               the Mais tab: theme and privacy
  l10n/                     app_pt.arb, app_en.arb, generated AppLocalizations
tool/
  check.sh                  the gate
  coverage_gate.dart        per-layer coverage thresholds
test/                       mirrors lib/ one to one
```

## Layers

- **Domain** (`features/<f>/domain`): entities, value objects, pure rules and
  the repository contract (`abstract interface class`). `payment_ladder.dart`
  is the example of a pure rule: given a bill's plan and attempts it decides
  the state of each of the three steps.
- **Application** (`features/<f>/application`): one use case per operation,
  ports through the constructor, a single `call`. `ListBills` scopes and
  orders; it is written even when it only forwards, because the next rule goes
  there.
- **Data** (`features/<f>/data`): DTO mapping, the API repository over Dio and
  `guardRequest`, and the fake repository.
- **Presentation** (`features/<f>/presentation`): screens, widgets and
  Riverpod controllers. A screen reads controllers; it never touches a
  repository or Dio.
- **Core**: no feature knowledge. A `core` file importing `features/` is a
  defect.

## Global state

- `entityScopeProvider` (`features/entities`): Pessoal, Empresa or
  Consolidado. Every list controller watches it, so switching refetches.
- `displayPreferencesProvider` (`core/preferences`): theme mode and
  `hideAmounts`. `AmountText` and `PrivacyToggle` read it, so every amount
  follows the toggle without the screens passing a flag. Both live in memory
  for now; persisting them is a follow-up.

## Navigation

`app/router/app_router.dart` is a `StatefulShellRoute` with five branches:
Início (`/home`), Transações (`/transactions`), Contas a pagar (`/bills`, with
`/bills/:billId`), Chat (`/chat`) and Mais (`/more`). The bottom bar shows only
on the tab roots (`AppRoutes.tabs`).

## Composition root

Riverpod providers are the container. Each feature wires itself in
`<feature>_providers.dart`, switching fake or API by `AppConfig.backend`:

```
appConfigProvider, dioProvider, clockProvider (core)
  -> billsRepositoryProvider (fake or api) -> listBillsProvider -> billsControllerProvider
```

Tests replace a port with `ProviderScope(overrides: [...])`.

## The layer rule, enforced

`test/architecture/layer_rules_test.dart` fails when a `domain` file imports
Flutter, Dio, Riverpod or another layer; an `application` file imports Flutter,
Dio, `data` or `presentation`; a `presentation` file imports `data` or Dio; a
`core` file imports a feature; or any file uses a relative import.
