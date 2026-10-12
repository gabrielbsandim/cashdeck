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
    location/               LocationReader and Geocoder ports, GeoPoint, adapters
    result/                 Result<T> (sealed)
    money/                  Money (integer cents + currency), MoneyFormat
    network/                Dio factory, error mapping, guardRequest, JSON reading
    preferences/            the privacy toggle (hide amounts)
    push/                   PushMessaging port, disabled default, Firebase adapter
    time/                   Clock port, CalendarDate, Brazil local time
    theme/                  tokens (AppPalette, spacing, radius, motion, type)
    widgets/                design system components, see design.md
  features/
    entities/               PF, PJ, consolidated scope and the switcher
    bills/                  bills list, bill detail, the payment ladder
    home/                   tab placeholder until the design lands
    home_widget/            the Android home screen widget, fed by Início and a background refresh
    transactions/           list by day, filters, detail, category and note, transfers
    chat/                   threads, conversation, attachments, action cards
    alerts/                 inbox, mute settings, push listener and token registration
    settings/               Ajustes: a hub of groups (sections/), the safe zones and the app version
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
  Budgets follow it through `budgetEntityProvider`, with Consolidado keeping
  the person's, since a budget belongs to one entity. Safe to spend is read
  per entity (`safeToSpendOfProvider`); the widget keeps the person's.
- `displayPreferencesProvider` (`core/preferences`): `hideAmounts`, saved on
  the device. `AmountText` and `PrivacyToggle` read it, so every amount
  follows the toggle without the screens passing a flag. The theme has no
  setting: it follows the system.
- `safeModeProvider` (`core/security`): the safe zones saved on the device and
  whether the phone is inside one, checked at launch and on every return to
  the screen. With a zone saved and the phone away from all of them (or with
  no fix), `safeModeLimitedProvider` is true: amounts stay hidden, the API
  client refuses every request but GET, the confirm sheet refuses, and the
  router sends the chat, receipts, shared files and every Ajustes group but
  security back home. Ten quick taps on the version in Ajustes, plus the
  device check, release it for an hour. A zone comes from the current
  location, named by its street address, or from a typed address (both
  through the `Geocoder` port), and can be renamed. Zones change only while
  not limited.

## Navigation

`app/router/app_router.dart` is a `StatefulShellRoute` with five branches:
Início (`/home`), Transações (`/transactions`, with
`/transactions/:transactionId`), Contas a pagar (`/bills`, with
`/bills/:billId`), Chat (`/chat`, with `/chat/:threadId`) and Mais (`/more`).
The bottom bar shows only on the tab roots (`AppRoutes.tabs`).

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

## Platform setup

- Android: `MainActivity` extends `FlutterFragmentActivity` and the launch
  theme is AppCompat, both required by `local_auth`. The manifest receives a
  shared PDF or image (`ACTION_SEND`) and the `cashdeck://capture` link the
  mailbox OAuth callback redirects to. `compileSdk` is at least 37 for
  `receive_sharing_intent`.
- Android card notifications: `notifications/CardNotificationListener` is a
  `NotificationListenerService` the user enables in system settings. It
  remembers which apps notify, queues the notifications of the apps picked in
  Ajustes and hands them to `CardNotificationUploader`, a WorkManager job that
  posts them to `POST /api/v1/card-notifications` with the session token,
  retrying while offline and stopping on a 401. Notifications still in the
  shade are read again when the listener connects and when forwarding turns
  on, so a charge from before setup is not lost. Settings, queue and token sit
  in app-private preferences; signing out clears them. Dart reaches it through
  the `io.cashdeck.app/card_notifications` channel
  (`features/card_notifications`).
- Android home screen widget: `widget/CashdeckWidgetProvider` (a
  `home_widget` `HomeWidgetProvider`, RemoteViews layout
  `res/layout/cashdeck_widget.xml`, 4x2 and resizable) shows what is free to
  spend today, the next open bill and the current card bill, plus when they
  were last written. While the app is open, `HomeWidgetSync`, mounted by
  Início, maps the loaded safe-to-spend, bills and insights overview into a
  `WidgetSnapshot` (`features/home_widget`) every time one of them loads or
  privacy changes. While it is closed, `widget/WidgetRefreshWorker`
  (WorkManager, every 3 hours with a connection, once more on boot, on an
  app update and when the first widget is added; cancelled when the last
  one is removed) wakes `refreshHomeWidgetInBackground` through the
  `home_widget` background callback, which the app registers at launch.
  That isolate reads the session from secure storage only for the request
  (never into the widget's preferences), and `RefreshHomeWidget` fetches the
  same three sources through the regular repositories: a 401 empties the
  widget so it asks to open the app, a failed request keeps the last numbers
  and their time. Amounts follow "Mostrar valores no widget" in Ajustes,
  Segurança (`widgetShowsAmountsProvider`): privacy mode always masks them,
  otherwise the user's choice decides, and until there is one a saved safe
  zone masks them, since the home screen cannot check where the phone is.
  Masked, the background refresh fetches nothing. The session ending
  (sign-out or a 401) clears it. Tapping opens the app on
  Início; the bill and card parts open `/bills` and `/cards` through
  `cashdeck://widget/<path>` and Flutter's deep linking. Labels live in
  `res/values` (Portuguese, the default) and `res/values-en`, colors in
  `widget_colors.xml` with a `values-night` twin. iOS has no widget: the
  publisher is a no-op off Android.
- Location: the Android manifest asks for coarse and fine location and
  `Info.plist` carries `NSLocationWhenInUseUsageDescription`; only the
  foreground fix is read, never in the background.
- iOS: `Info.plist` carries the Face ID and camera usage strings and the
  `cashdeck` URL scheme. Receiving a shared file needs a Share Extension
  target, which only Xcode can add: follow the iOS section of the
  `receive_sharing_intent` README (extension target, shared App Group,
  `AppGroupId` in both `Info.plist` files). Until then iOS opens files only
  through the file picker.
- Hardening: Android sets `FLAG_SECURE` in `MainActivity`, turns backups
  off (`allowBackup="false"` plus `res/xml/backup_rules.xml` and
  `data_extraction_rules.xml` excluding every domain) and refuses cleartext
  in `res/xml/network_security_config.xml`; the debug build overrides it to
  allow `localhost`, `127.0.0.1` and `10.0.2.2`. iOS blurs the window when
  the scene enters the background (`PrivacyCover` in `SceneDelegate.swift`)
  and `Info.plist` sets no App Transport Security exception.
- Sessions: sign-in trades the server's static token for a device session
  (`POST /api/v1/sessions`) and keeps only the session token. A static token
  stored by an older version is exchanged once at startup and deleted.
- Icon and splash come from `assets/brand/`, rendered from `CdMarkPainter`.
  Regenerate with `dart run flutter_launcher_icons` and
  `dart run flutter_native_splash:create` after changing them.
