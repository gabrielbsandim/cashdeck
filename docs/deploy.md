# Deploy

The API runs on Vercel and the database on Neon Postgres.

## Vercel project

- Import the repository and set **Root Directory** to `apps/api`. Vercel
  detects Next.js and pnpm; the build runs from the monorepo root, so the
  workspace packages build through Turborepo.
- Node.js 24 (the root `engines` field).
- `apps/api/vercel.json` declares the crons (UTC):

  | Path | Schedule |
  |---|---|
  | `/api/cron/open-finance-sync` | `0 9 * * *` |
  | `/api/cron/capture` | `30 9 * * *` |
  | `/api/cron/payment-ladder` | `0 11 * * 1-5` |
  | `/api/cron/reconcile-payments` | `0 21 * * 1-5` |

  Vercel sends `Authorization: Bearer $CRON_SECRET`; a cron without the secret
  answers 401.

## Database

Create a Neon project and copy the pooled connection string into
`DATABASE_URL`. Apply the migrations from your machine or CI, never from the
build:

```sh
DATABASE_URL='<neon connection string>' pnpm -C packages/infrastructure db:deploy
DATABASE_URL='<neon connection string>' pnpm -C packages/infrastructure db:seed
```

The seed creates the personal and company entities once. Without
`DATABASE_URL` the API keeps everything in memory, which only suits local
development.

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
| `LLM_PROVIDER`, `GEMINI_API_KEY`, `GEMINI_MODEL_ID`, `AI_GATEWAY_API_KEY`, `AI_GATEWAY_FALLBACK_MODEL` | for AI | Card statements and shared bills |
| `BRL_PER_USD` | no | Fallback exchange rate |
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET` | for Open Finance | Aggregator |
| `ASAAS_API_KEY`, `ASAAS_ENVIRONMENT` | no | Tenant-wide Asaas fallback |
| `MERCADO_PAGO_ACCESS_TOKEN`, `MERCADO_PAGO_SIGNING_KEY`, `MERCADO_PAGO_ENVIRONMENT` | no | Tenant-wide Mercado Pago fallback |
| `INTER_CLIENT_ID`, `INTER_CLIENT_SECRET`, `INTER_CERT`, `INTER_KEY`, `INTER_ACCOUNT`, `INTER_ENVIRONMENT` | no | Tenant-wide Inter fallback |
| `C6_CLIENT_ID`, `C6_CLIENT_SECRET`, `C6_CERT`, `C6_KEY`, `C6_TOKEN_URL`, `C6_UPLOADER_NAME`, `C6_ENVIRONMENT` | no | Tenant-wide C6 fallback and DDA |
| `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REDIRECT_URI` | for Gmail capture | Google OAuth client |
| `NOTAAS_API_KEY`, `NOTAAS_WEBHOOK_SECRET`, `NOTAAS_ALIQUOTA_ISS`, `NOTAAS_LOCAL_PRESTACAO`, `NOTAAS_EXPORT_COUNTRY` | for invoices | NFS-e issuer |
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

## After the first deploy

1. `curl -H "Authorization: Bearer $CASHDECK_API_TOKEN" https://<api domain>/api/v1/auth/check`
   lists both entities.
2. Sign in from the app with the API URL and the same token.
