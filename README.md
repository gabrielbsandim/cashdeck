# Cashdeck

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![API](https://img.shields.io/badge/API-Next.js%2016%20%7C%20TypeScript-black.svg?logo=next.js&logoColor=white)](https://nextjs.org/)
[![Mobile](https://img.shields.io/badge/Mobile-Flutter-02569B.svg?logo=flutter&logoColor=white)](https://flutter.dev/)
[![Database](https://img.shields.io/badge/Database-PostgreSQL%20(Neon)-00E599.svg?logo=postgresql&logoColor=black)](https://neon.tech/)
[![Open Finance](https://img.shields.io/badge/Open%20Finance-Pluggy-blueviolet.svg)](https://pluggy.ai/)

Open-source, self-hosted financial operating system designed for households in Brazil managing personal accounts (PF) and small business operations (PJ).

Cashdeck aggregates your bank accounts via Open Finance, ingests incoming bills from multiple sources, processes them through a safe, escalating payment ladder, and provides intelligent monthly planning ("safe-to-spend"), tax calculations, and an interactive AI copilot over your entire financial ledger.

---

## How It Works

```
   [Bank Sync (Pluggy)]     [Gmail Invoices]     [Bank DDA]     [Camera / PDF]
            │                       │                 │                │
            └───────────────────────┼─────────────────┴────────────────┘
                                    ▼
                     ┌─────────────────────────────┐
                     │   Categorization Engine     │
                     │  (Rule Engine ➔ AI Parsing) │
                     └──────────────┬──────────────┘
                                    ▼
       ┌────────────────────────────┴────────────────────────────┐
       ▼                                                         ▼
┌───────────────────────────────┐               ┌─────────────────────────────────┐
│     Escalating Payment        │               │      Financial Planning         │
│           Ladder              │               │                                 │
│  1. Fully Automatic (Pix)     │               │  • Real-time Safe-to-Spend      │
│  2. Bank Approval Gate        │               │  • Monthly Budgets & Recaps     │
│  3. Assisted (Copy Code)      │               │  • Wealth (FIPE, Assets, Loans) │
│  * Always human-controllable  │               │  • PJ: NFS-e & DAS (Fator R)    │
└───────────────────────────────┘               └────────────────┬────────────────┘
                                                                 ▼
                                                ┌─────────────────────────────────┐
                                                │      AI Financial Copilot       │
                                                │   Tool-assisted ledger query    │
                                                └─────────────────────────────────┘
```

---

## Core Capabilities

| Domain | Highlights |
| :--- | :--- |
| **Banking & Accounts** | Pluggy Open Finance synchronization, intraday feeds, manual cash accounts, credit card statement parsing, and internal transfers. |
| **Transaction Classification** | Deterministic rules execute first; AI categorizes the remaining edge cases. Full review queue and automated recurring subscription detection. |
| **Bills & Payments** | Automated capture from Gmail, C6 DDA, file uploads, and barcode/QR scans. Secure escalating payment ladder with spending caps and an instant emergency kill-switch. |
| **Safe-to-Spend Planning** | Real-time liquidity forecasting, envelopes, savings goals, cash-flow outlooks, threshold alerts, and monthly recap digests. |
| **Net Worth & Assets** | Consolidated investment performance, vehicle equity tracking via live FIPE valuation, property rental returns, and loan amortization. |
| **Business / PJ Mode** | Integrated NFS-e invoice generation (via Notaas), recurring invoice schedules, DAS tax calculation with Fator R deduction, and accountant CSV exports. |
| **AI Assistant** | Natural language queries over your transaction ledger using Gemini or Vercel AI SDK with sandboxed function calling. |

---

## Monorepo Architecture

Cashdeck follows strict Clean Architecture (Ports & Adapters) enforced by `dependency-cruiser`:

```
cashdeck/
├── apps/
│   ├── api/                   # Next.js 16 route handlers (/api/v1), crons, webhooks
│   └── mobile/                # Flutter companion app (Riverpod, feature-first)
├── packages/
│   ├── domain/                # Pure business entities & validation rules (zero external I/O)
│   ├── application/           # Use cases, ports (interfaces), Zod DTOs, in-memory test fakes
│   ├── infrastructure/        # Prisma 7 repositories, bank adapters, secret vaults
│   ├── client/                # Typed TypeScript client generated from OpenAPI specs
│   ├── i18n/                  # Bilingual localization (pt-BR and en)
│   └── config/                # Shared ESLint, Prettier, and Vitest presets
├── docs/                      # Architectural decisions, deploy guides, provider setup
└── design/                    # UI component specifications & prototypes
```

---

## Quickstart

### Prerequisites

- **Node.js:** `24.x` (see `.nvmrc`)
- **pnpm:** `9.x`
- **Flutter SDK:** `^3.13.5` (Dart `^3.13.5`)

### 1. Launch the API

```bash
pnpm install
pnpm build

# Set a local development API secret (minimum 16 characters)
echo 'CASHDECK_API_TOKEN=local-dev-token-0001' > apps/api/.env.local

# Start API server on http://localhost:3100
pnpm -C apps/api dev
```

*Note: Without a `DATABASE_URL`, the API automatically boots using in-memory mock repositories pre-seeded with sample entities for instant evaluation.*

### 2. Launch the Mobile Client

The Flutter app can run against its offline mock backend or connect to your local API:

```bash
cd apps/mobile
flutter pub get

# Option A: Run with built-in mock backend (no server required)
flutter run

# Option B: Run pointing to your local API (Android emulator)
flutter run --dart-define=BACKEND=api --dart-define=API_BASE_URL=http://10.0.2.2:3100
```

---

## Self-Hosting Guide

Cashdeck is designed as a single-household instance. You control your database and secrets.

1. **Provision Database:** Spin up a PostgreSQL instance (e.g., [Neon](https://neon.tech)), deploy migrations, and run seeds:
   ```bash
   DATABASE_URL='<connection-string>' pnpm -C packages/infrastructure db:deploy
   DATABASE_URL='<connection-string>' pnpm -C packages/infrastructure db:seed
   ```
2. **Deploy API:** Deploy to Vercel (Root Directory: `apps/api`) with four core environment variables:
   - `DATABASE_URL`: Connection string to Postgres.
   - `CASHDECK_API_TOKEN`: Root administrative token.
   - `CASHDECK_MASTER_KEY`: 32-byte base64 encryption key (generate via `node -e "console.log(require('crypto').randomBytes(32).toString('base64'))"`).
   - `CRON_SECRET`: Secret token for scheduled crons.
3. **Build Android APK:**
   ```bash
   cd apps/mobile
   flutter build apk --release --split-per-abi --target-platform android-arm64 \
     --dart-define=BACKEND=api --dart-define=API_BASE_URL=https://<your-api-domain>
   ```
4. **Authenticate:** Open the app, input your API domain and `CASHDECK_API_TOKEN`. The client exchanges this for an encrypted device session token.

Detailed guides for crons, webhooks, Gmail OAuth, and push notifications are in [`docs/deploy.md`](docs/deploy.md).

---

## Development & Testing

```bash
# Full monorepo verification (lint, typecheck, format, boundary rules, test coverage)
pnpm check

# Test specific package
pnpm -C packages/domain test

# Mobile automated test suite
apps/mobile/tool/check.sh

# Regenerate API client after schema changes
pnpm -C apps/api openapi:export
pnpm -C packages/client generate
```

*Quality Standards: 100% test coverage enforced on `domain` and `application`; >=95% everywhere else.*

---

## Documentation

- [Documentation Index](docs/README.md)
- [System Architecture](docs/architecture.md)
- [Deployment & Env Vars](docs/deploy.md)
- [Provider Integrations](docs/providers.md)
- [API Contract & OpenAPI](docs/api.md)

---

## License

[MIT](LICENSE) © Gabriel Sandim
