# Cashdeck

Open-source, self-hosted finance for people in Brazil who run a personal profile
and, optionally, a small company. Cashdeck reads accounts through Open Finance,
captures bills from every channel, pays them through an escalating payment
ladder (automatic, approval in the bank, assisted) and keeps a human path open
for every bill.

The product and architecture plan lives in [docs/plan.md](docs/plan.md); the
design brief for the mobile app is in [docs/design-brief.md](docs/design-brief.md).

## Layout

```
apps/
  api/            Next.js route handlers under /api/v1, composition root, cron
  mobile/         Flutter app
packages/
  domain/         entities, value objects, payment codes, ladder rules (no I/O)
  application/    ports, use cases, DTOs and the fakes every test uses
  infrastructure/ Prisma (Neon), LLM providers, secret vault, provider adapters
  client/         typed API client generated from the OpenAPI document
  config/         shared tsconfig, eslint and vitest presets
  i18n/           pt-BR and en messages
```

## Getting started

Requirements: Node 24, pnpm 9 and, for the app, the Flutter SDK.

```bash
pnpm install
cp .env.example .env        # optional: the API runs on in-memory fakes without it
pnpm build
pnpm -C apps/api dev        # http://localhost:3100/api/v1/health
```

Without provider credentials every payment rail reports itself unconfigured, so
each bill walks the ladder down to the assisted step, where the app hands you
the code to pay.

## Self-hosting

Cashdeck is single-tenant: you run your own API and point the app at it.
You need a Neon (or any Postgres) database, a Vercel account and the Flutter
SDK to build the app. The full guide is [docs/deploy.md](docs/deploy.md).

1. **Database.** Create a Neon project, then apply the migrations and the seed
   from your machine:

   ```bash
   DATABASE_URL='<connection string>' pnpm -C packages/infrastructure db:deploy
   DATABASE_URL='<connection string>' pnpm -C packages/infrastructure db:seed
   ```

2. **API.** Import the repository in Vercel with Root Directory `apps/api` and
   set the four required variables: `DATABASE_URL`, `CASHDECK_API_TOKEN` (16+
   characters, the app signs in with it), `CASHDECK_MASTER_KEY` (generate it
   with `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`)
   and `CRON_SECRET`. `.env.example` lists every other name.
3. **App.** Build the Android APK against your API and install it:

   ```bash
   cd apps/mobile
   flutter build apk --release --split-per-abi --target-platform android-arm64 \
     --dart-define=BACKEND=api --dart-define=API_BASE_URL=https://<api domain>
   adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```

4. **Sign in.** Open the app and enter the API URL and `CASHDECK_API_TOKEN`.
   Check the server first with
   `curl -H "Authorization: Bearer $CASHDECK_API_TOKEN" https://<api domain>/api/v1/auth/check`.

With only the required variables, you can add bills by hand, paste a boleto or
Pix code, and pay through the assisted step. Every integration is optional and
switched on by its credentials, either as env variables or saved from the app
settings:

| Integration | What it adds |
|---|---|
| Pluggy | Accounts, balances and card statements through Open Finance |
| Asaas, Inter Empresas, C6 Empresas | Automatic payments and bank approval |
| Gmail, C6 DDA | Bills captured from email and from the DDA |
| Notaas | NFS-e invoices for the company profile |
| Firebase Cloud Messaging | Push alerts |
| Gemini or Vercel AI Gateway | Statement reading, categorization and the chat |

Credentials and setup for each provider are in [docs/providers.md](docs/providers.md);
the HTTP contract is in [docs/api.md](docs/api.md) and the app in
[apps/mobile/README.md](apps/mobile/README.md).

## Quality gates

```bash
pnpm check   # lint, typecheck, format, dependency rules, tests with coverage
```

Coverage is 100% on `domain` and `application` and at least 95% everywhere
else. Layering is enforced by dependency-cruiser (`.dependency-cruiser.cjs`).

## API client

```bash
pnpm -C apps/api openapi:export   # writes packages/client/openapi.json
pnpm -C packages/client generate  # regenerates src/generated/schema.ts
```

## License

MIT
