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

Requirements: Node 24 and pnpm 9.

```bash
pnpm install
cp .env.example .env        # optional: the API runs on in-memory fakes without it
pnpm build
pnpm -C apps/api dev        # http://localhost:3100/api/v1/health
```

Without provider credentials every payment rail reports itself unconfigured, so
each bill walks the ladder down to the assisted step, where the app hands you
the code to pay.

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
