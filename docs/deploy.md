# Deploy

The API runs on Vercel and the database on Neon Postgres.

## Vercel project

- Import the repository and set **Root Directory** to `apps/api`.
  `apps/api/vercel.json` pins the install and build commands to the monorepo
  root (`pnpm turbo run build --filter=@cashdeck/api`), so the workspace
  packages and the Prisma client are built first.
- Node.js 24 (the root `engines` field).
- `apps/api/vercel.json` declares the crons (UTC):

  | Path | Schedule |
  |---|---|
  | `/api/cron/open-finance-sync` | `0 15 * * *` |
  | `/api/cron/capture` | `30 9 * * *` |
  | `/api/cron/payment-ladder` | `0 11 * * 1-5` |
  | `/api/cron/reconcile-payments` | `0 21 * * 1-5` |
  | `/api/cron/invoices` | `0 12 * * 1-5` |
  | `/api/cron/alerts` | `0 12 * * *` |

  Vercel sends `Authorization: Bearer $CRON_SECRET`; a cron without the secret
  answers 401. Cron routes allow 300 seconds each.

## Database

Create a Neon project and copy the pooled connection string into
`DATABASE_URL`. Apply the migrations from your machine or CI, never from the
build:

```sh
DATABASE_URL='<neon connection string>' pnpm -C packages/infrastructure db:deploy
DATABASE_URL='<neon connection string>' pnpm -C packages/infrastructure db:seed
```

The seed creates the personal and company entities once, from
`CASHDECK_PF_NAME`, `CASHDECK_PF_TAX_ID`, `CASHDECK_PJ_NAME`, `CASHDECK_PJ_TAX_ID`
and `CASHDECK_PJ_TAX_REGIME`, falling back to public test tax ids. Running it
again never overwrites an entity; change one with `PATCH /api/v1/entities/{id}`
(or the app settings) before connecting an issuer, a rail or the DDA, since
they all send the entity tax id. Without `DATABASE_URL` the API keeps
everything in memory, which only suits local development; a Vercel deploy
refuses to start without it.

## Environment variables

Set them in the Vercel project (Production and Preview). `.env.example` at the
repository root lists every name. Provider names and where each credential is
read from are in [providers.md](providers.md).

| Name | Required | What |
|---|---|---|
| `DATABASE_URL` | yes | Neon pooled connection string |
| `CASHDECK_API_TOKEN` | yes | Bearer token the app signs in with, 16+ characters; without it every route answers 503 `NOT_CONFIGURED` |
| `CASHDECK_MASTER_KEY` | yes | Vault key that seals stored credentials |
| `CRON_SECRET` | yes | Bearer token Vercel sends to the crons |
| `CASHDECK_TENANT_ID` | no | Defaults to `local` |
| `CASHDECK_SERVER_NAME` | no | Shown by `GET /auth/check`, defaults to `Cashdeck` |
| `CASHDECK_APP_SCHEME` | no | Deep link scheme of the OAuth redirect, defaults to `cashdeck` |
| `SENTRY_DSN` | no | Error reporting |
| `LLM_PROVIDER`, `GEMINI_API_KEY`, `GEMINI_MODEL_ID`, `AI_GATEWAY_API_KEY`, `AI_GATEWAY_FALLBACK_MODEL` | for AI | Card statements, shared bills, categorization and the chat. `LLM_PROVIDER` is `gateway`, `gemini` or `fake` (the default, no network) |
| `CHAT_ENABLED` | no | `false` turns the AI chat off (503); defaults to `true` |
| `CHAT_DAILY_TURN_LIMIT` | no | Chat messages per tenant per day, defaults to `100` |
| `CHAT_DAILY_COST_LIMIT_CENTS` | no | Model spend per tenant per day in BRL cents, defaults to `200` |
| `CHAT_MAX_ROUNDS` | no | Model calls per chat turn, 1 to 12, defaults to `6` |
| `CHAT_TURN_BUDGET_MS` | no | Wall time of a chat turn, 1000 to 50000, defaults to `25000` (the route allows 60 s) |
| `BRL_PER_USD` | no | Fallback exchange rate |
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET` | for Open Finance | Aggregator |
| `PIERRE_API_KEY` | optional | Preview feed between Pluggy's daily collections |
| `ASAAS_API_KEY`, `ASAAS_ENVIRONMENT` | no | Tenant-wide Asaas fallback |
| `MERCADO_PAGO_ACCESS_TOKEN`, `MERCADO_PAGO_SIGNING_KEY`, `MERCADO_PAGO_ENVIRONMENT` | no | Tenant-wide Mercado Pago fallback |
| `INTER_CLIENT_ID`, `INTER_CLIENT_SECRET`, `INTER_CERT`, `INTER_KEY`, `INTER_ACCOUNT`, `INTER_ENVIRONMENT` | no | Tenant-wide Inter fallback |
| `C6_CLIENT_ID`, `C6_CLIENT_SECRET`, `C6_CERT`, `C6_KEY`, `C6_TOKEN_URL`, `C6_UPLOADER_NAME`, `C6_ENVIRONMENT` | no | Tenant-wide C6 fallback and DDA |
| `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REDIRECT_URI` | for Gmail capture | Google OAuth client |
| `NOTAAS_API_KEY`, `NOTAAS_WEBHOOK_SECRET`, `NOTAAS_ALIQUOTA_ISS`, `NOTAAS_LOCAL_PRESTACAO`, `NOTAAS_EXPORT_COUNTRY` | for invoices | NFS-e issuer |
| `ASAAS_WEBHOOK_TOKEN`, `MERCADO_PAGO_WEBHOOK_SECRET`, `INTER_WEBHOOK_TOKEN`, `PLUGGY_WEBHOOK_SECRET` | for webhooks | Shared secrets of each provider webhook; without one that webhook answers 401 |
| `FCM_SERVICE_ACCOUNT_JSON` | for push | Firebase service account |

Rail credentials saved from the app live in the database, sealed with
`CASHDECK_MASTER_KEY`; the env names above are only the fallback when the app
has stored nothing. Rotating `CASHDECK_MASTER_KEY` makes stored credentials
unreadable, so they must be saved again.

## Gmail OAuth

In the Google Cloud console, create an OAuth client of type Web application and
add `https://<api domain>/api/v1/capture/mailboxes/oauth/callback` as an
authorized redirect URI. Use the same URL as `GMAIL_REDIRECT_URI`. The app opens
the consent page from `POST /capture/mailboxes/oauth/start` and comes back
through `cashdeck://capture`.

## Webhooks

Webhooks make payments, Open Finance and invoices update minutes after the
provider knows, instead of at the next cron. They are optional: without them
the crons do the same work on their schedule. For each provider you use:

1. Generate a secret (`openssl rand -hex 32`) and store it, either in the
   Vercel project under the name below or from the app as a sealed credential.
   For separate PF and PJ accounts at the same provider, store
   `NAME@<entityId>` and add `?entity=<entityId>` to that account's URL.
2. Register the URL at the provider:
   - **Asaas** (each account, under Integrations, Webhooks): URL
     `https://<api domain>/api/webhooks/asaas`, authentication token = the
     secret (`ASAAS_WEBHOOK_TOKEN`), events for transfers and bill payments.
   - **Mercado Pago** (Your integrations, Webhooks): URL
     `https://<api domain>/api/webhooks/mercado-pago`; copy the signing secret
     the panel shows into `MERCADO_PAGO_WEBHOOK_SECRET`.
   - **Inter Empresas** (banking webhook API, once per type):
     `https://<api domain>/api/webhooks/inter?token=<INTER_WEBHOOK_TOKEN>`.
   - **Pluggy** (dashboard webhook form, or `POST /webhooks`): URL
     `https://<api domain>/api/webhooks/pluggy?token=<PLUGGY_WEBHOOK_SECRET>`,
     event `all`. The form takes only a URL and an event, so the token goes in
     the URL.
   - **Notaas** (webhook endpoints): URL
     `https://<api domain>/api/webhooks/notaas`; the endpoint secret goes into
     `NOTAAS_WEBHOOK_SECRET`.
3. Send a test event from the provider panel. The answer is 200 with
   `received: 1`; a 401 means the secret differs. The migration
   `20261014120000_webhooks_invoice_lifecycle` must be applied first, since
   event ids are stored in `webhook_events`, and
   `20261021120000_webhook_event_outcome` before deploying the code that
   records each event's outcome there.

The provider-specific details and what is still unconfirmed are in
[providers.md](providers.md#webhooks).

## Push notifications

Alerts always land in the in-app inbox; push is an extra that stays off until
both sides below are configured. Without them the API stores alerts and skips
the send, and the app runs with push disabled.

1. In the Firebase console, create a project (or add Firebase to an existing
   Google Cloud project) and enable Cloud Messaging.
2. Server: under Project settings, Service accounts, generate a new private key.
   Paste the whole JSON file, on one line, as `FCM_SERVICE_ACCOUNT_JSON` in the
   Vercel project. The API sends through the HTTP v1 API with that account.
3. Android: add an Android app with package name `io.cashdeck.app`, download
   `google-services.json` and place it at `apps/mobile/android/app/`. The file
   is git ignored; the Gradle build applies the Google services plugin only when
   it is present, so builds without it keep working.
4. iOS (not wired yet): add an iOS app, place `GoogleService-Info.plist` in
   `apps/mobile/ios/Runner/`, upload an APNs key in Cloud Messaging and enable
   the Push Notifications capability in Xcode.

The app asks for notification permission and registers its token with
`POST /api/v1/devices` after sign-in. Tokens FCM reports as unregistered are
deleted on the next send. The `/api/cron/alerts` cron (daily, 12:00 UTC) emits
the due-soon and low reserve balance alerts. Alerts and device tokens need
the migration `20261013120000_alerts_and_devices`.

## After the first deploy

1. `curl -H "Authorization: Bearer $CASHDECK_API_TOKEN" https://<api domain>/api/v1/auth/check`
   lists both entities.
2. Sign in from the app with the API URL and the same token.
