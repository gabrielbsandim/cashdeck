# Cashdeck

Open-source, self-hosted finance for households in Brazil that run a personal
profile (PF) and, optionally, a small company (PJ).

Cashdeck reads your accounts through Open Finance, captures bills from email,
the bank DDA and the phone, pays them through an escalating payment ladder
(automatic, approval in the bank, assisted) and always keeps a human path open.
On top of that it plans the month: how much is safe to spend, budgets, goals,
subscriptions, investments, net worth, company taxes and invoices, with an AI
chat over all of it.

It is a monorepo with a TypeScript API (Next.js route handlers on Vercel,
Postgres on Neon) and a Flutter mobile app.

## Contents

- [What it does](#what-it-does)
- [Quickstart](#quickstart)
- [Repository layout](#repository-layout)
- [Configuration](#configuration)
- [Self-hosting](#self-hosting)
- [Development](#development)
- [Documentation](#documentation)
- [License](#license)

## What it does

| Area                | Highlights                                                                                                                                  |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Accounts            | Open Finance sync through Pluggy, an optional intraday preview feed, manual accounts and card bills, internal transfers                     |
| Transactions        | Categorization by rules first and AI second, a review queue, subscriptions detected from history                                            |
| Bills and payments  | Capture from Gmail, C6 DDA, shared files, pasted codes and the camera; a payment ladder with Pix first, safety caps and a kill switch       |
| Planning            | Safe to spend for the month, budgets, goals, a life plan, cash-flow outlook, alerts and a monthly recap                                     |
| Wealth              | Investments with history and performance, goods (including vehicles priced by FIPE and rented properties), loans and net worth              |
| Company             | NFS-e invoices through Notaas, recurring templates, DAS estimate with Fator R, payroll entries and an accountant export                    |
| AI                  | Card statement and bill reading, categorization and a chat with tools over your data (Gemini or Vercel AI Gateway)                          |

Every integration is optional and switched on by its credentials. Without any,
the API runs on fakes and every bill walks the ladder down to the assisted
step, where the app hands you the code to pay.

## Quickstart

Requirements: Node 24 (see `.nvmrc`), pnpm 9 and, for the app, the Flutter SDK
(CI uses 3.47 stable).

```bash
pnpm install
pnpm build

# The API refuses every request until it has a token (16+ characters).
echo 'CASHDECK_API_TOKEN=local-dev-token-0001' > apps/api/.env.local
pnpm -C apps/api dev          # http://localhost:3100/api/v1/health
```

Without `DATABASE_URL` the API keeps everything in memory with two sample
entities, which is enough to explore it. Sign a device in to get a session
token for the other routes:

```bash
curl -X POST http://localhost:3100/api/v1/sessions \
  -H 'Authorization: Bearer local-dev-token-0001' \
  -d '{"deviceName":"curl","platform":"WEB"}'
```

Run the app against its built-in fake backend (no server needed), or against
your local API:

```bash
cd apps/mobile
flutter pub get
flutter run                                    # fake backend
flutter run --dart-define=BACKEND=api \
  --dart-define=API_BASE_URL=http://10.0.2.2:3100   # Android emulator to host
```

## Repository layout

```
apps/
  api/             Next.js route handlers under /api/v1, crons, webhooks, composition root
  mobile/          Flutter app (feature-first clean architecture, Riverpod)
packages/
  domain/          entities, value objects and pure rules (no I/O, no dependencies)
  application/     use cases, ports, DTOs (zod) and a fake for every port
  infrastructure/  Prisma repositories, provider adapters, LLM, secret vault
  client/          typed API client generated from the OpenAPI document
  i18n/            pt-BR and en messages
  config/          shared tsconfig, eslint and vitest presets
docs/              API contract, architecture, providers, deploy, product plan
design/            design system and screen prototypes (HTML)
```

The layers follow ports and adapters, enforced by dependency-cruiser. See
[docs/architecture.md](docs/architecture.md).

## Configuration

`.env.example` lists every variable with an empty or fake value. Where each
file is read:

| File                  | Read by                                                     |
| --------------------- | ----------------------------------------------------------- |
| `apps/api/.env.local` | the API dev server (Next.js loads env files from its app)   |
| `.env` at the root    | Prisma migrations and the seed (`packages/infrastructure`) |
| Vercel project        | the deployed API                                            |

Only four variables are required on a deployed server: `DATABASE_URL`,
`CASHDECK_API_TOKEN`, `CASHDECK_MASTER_KEY` and `CRON_SECRET`. The full table
is in [docs/deploy.md](docs/deploy.md#environment-variables); provider
credentials can also be saved from the app, sealed in the database.

## Self-hosting

Cashdeck is single-household: you run your own API and point the app at it.

1. **Database.** Create a Neon (or any Postgres) database, then apply the
   migrations and the seed:

   ```bash
   DATABASE_URL='<connection string>' pnpm -C packages/infrastructure db:deploy
   DATABASE_URL='<connection string>' pnpm -C packages/infrastructure db:seed
   ```

2. **API.** Import the repository in Vercel with Root Directory `apps/api` and
   set the four required variables. Generate the master key with
   `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`.
3. **App.** Build the Android APK against your API and install it:

   ```bash
   cd apps/mobile
   flutter build apk --release --split-per-abi --target-platform android-arm64 \
     --dart-define=BACKEND=api --dart-define=API_BASE_URL=https://<api domain>
   adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```

4. **Sign in.** Open the app and enter the API URL and `CASHDECK_API_TOKEN`.
   The app trades the token for a device session and keeps only that.

The full guide, with crons, webhooks, Gmail OAuth and push notifications, is
[docs/deploy.md](docs/deploy.md). Provider setup is in
[docs/providers.md](docs/providers.md).

## Development

```bash
pnpm check                      # lint, typecheck, format, dependency rules, tests with coverage
pnpm -C packages/domain test    # one package
apps/mobile/tool/check.sh       # the mobile gate
```

Coverage is 100% on `domain` and `application` and at least 95% elsewhere.
After changing an API schema, regenerate the client:

```bash
pnpm -C apps/api openapi:export   # writes packages/client/openapi.json
pnpm -C packages/client generate  # regenerates src/generated/schema.ts
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

## Documentation

Start at the [documentation index](docs/README.md).

## License

[MIT](LICENSE)
