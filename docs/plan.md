# Cashdeck: product and architecture plan

Cashdeck is an open-source, self-hosted personal finance app for people in Brazil
who manage a personal profile (PF) and, optionally, a company (PJ). It reads
accounts through Open Finance, captures bills from every channel, pays them through
an escalating payment ladder, issues service invoices (NFS-e), and offers a
multimodal AI chat over the whole picture. It belongs to the Lifedeck family and is
built so it can merge into Life Deck later.

Design happens in Claude Design after this plan is approved. This document covers
product scope, architecture, integrations and delivery order.

## 1. Principles

1. **Generic.** No personal names, accounts or documents in code, seeds or docs.
   Every institution, provider and rule is configuration.
2. **Ports and adapters.** Every external system sits behind a port in the
   application layer. Adapters are swappable, and each one ships with a fake.
3. **Automatic first, human always available.** Every payment walks a ladder
   (automatic, approval in the bank, assisted). A failure moves one step down, never
   to silence.
4. **Self-hosted, multi-tenant ready.** One deployment serves one household, but
   every row carries `tenantId` and every query is scoped by it from day one.
5. **PF and PJ from the start.** A `FinancialEntity` (person or company) owns
   accounts, bills, budgets and invoices. Transfers between entities are first-class.
6. **Quality gates are code.** Coverage, layering and lint rules fail the build.

## 2. Decisions so far

| Topic | Decision |
|---|---|
| Name | Cashdeck |
| Distribution | Self-hosted; tenant scoping in place for a future hosted mode |
| Mobile | Flutter |
| Backend | Next.js 16 + TypeScript, REST under `/api/v1` |
| Database | Neon (Postgres) via Prisma, pgvector for chat memory |
| AI | Gemini, reusing the Obra Nova LLM infrastructure |
| Open Finance | Pluggy (Meu Pluggy free tier first) |
| PF reserve | A checking account yielding about 100% of CDI (Mercado Pago by default) |
| PF payer | Asaas (boleto, Pix QR) funded from the reserve on the due date |
| PJ payer | Inter Empresas if the API integration is approved, C6 Empresas otherwise |
| Invoices | Notaas (free tier) behind an `InvoiceIssuer` port |
| Base code | Obra Nova: its Next.js, Prisma 7, Neon and Vercel setup for the API, its Flutter app for mobile; Life Deck layout for the monorepo |
| Plan location | This repo, `docs/plan.md` |

## 3. Scope

### 3.1 Core finance

- **Institutions and accounts.** Connected (Pluggy), manual (no Open Finance, for
  example Nomad), and reserve (the account bills are funded from). Checking,
  savings, credit card, investment and wallet account types.
- **Transactions.** Sync, dedupe, transfers between own accounts, split, notes,
  attachments. AI categorization, since Meu Pluggy returns none.
- **Credit cards.** Bills (open, closed, paid), installments, per-card limits.
  Manual cards get a bill import every time a bill closes.
- **Budgets by category**, monthly, with rollover option and alerts at 80% and 100%.
- **Recurrences and subscriptions.** Detected from history, confirmed by the user,
  with price-change and duplicate alerts.
- **Investments and net worth.** Holdings from Pluggy, B3 position import, manual
  assets. Net worth timeline per entity and consolidated.
- **Goals ("caixinhas").** Target, deadline, linked account or virtual envelope,
  projected completion.

### 3.2 Bills and payments

- **Bill capture (`BillSource` port).**
  - Gmail scan (boletos, DARF, DAS, card bills as PDF or inline barcode).
  - Share to app (Android share intent, iOS share extension).
  - Camera (barcode and OCR via Gemini vision).
  - Chat (photo, PDF, audio or text in the AI chat).
  - DDA for the company through the C6 API `GET /query` (free with a C6 PJ account).
  - Polp Super DDA as an optional paid adapter for PF and PJ.
- **Bill model.** Payee, amount, due date, barcode or Pix payload, kind (`BOLETO`,
  `PIX_KEY`, `PIX_QR`, `TAX_BARCODE` for DARF, DAS and GPS with barcode,
  `DARF_NO_BARCODE`), owning entity, status, source, attachments.
- **Payment ladder** (section 5).

### 3.3 Company (PJ)

- Separate entity with its own accounts, bills, budgets and reports.
- Monthly tax calendar: DAS (Simples Nacional), DARF from DCTFWeb (pro-labore INSS
  and IRRF), and any other guide the accountant sends.
- Profit distribution to the PF modeled as an inter-entity transfer, so neither side
  reads it as income or expense twice.
- **Invoices (NFS-e)**, section 6.

### 3.4 AI

- Multimodal chat (text, image, audio, video, PDF) with tools over the user's data.
- Spending analysis: monthly narrative, anomalies, category drift, subscription
  creep, cash-flow forecast for the next 30 days.
- Categorization with a rule cache: user corrections become rules before the LLM is
  called again.
- Bill and statement extraction (vision and PDF).

### 3.5 Alerts

Bill due soon, bill paid, payment failed and moved down the ladder, approval pending
in a bank, budget threshold, unusual transaction, low reserve balance before a due
date, card bill closed, subscription price change, invoice not issued for a
recurring client, tax guide missing for the month. Delivered as push notifications
and in an in-app inbox; each alert type can be muted.

## 4. Architecture

### 4.1 Repository

pnpm + Turborepo, mirroring the Life Deck layout so the merge is a move, not a
rewrite.

```
apps/
  api/            Next.js 16 route handlers, composition root, cron entry points
  mobile/         Flutter app
packages/
  domain/         entities, value objects, domain services (no I/O)
  application/    use cases and ports
  infrastructure/ adapters (Prisma, Pluggy, payment rails, Gmail, Gemini, NFS-e)
  client/         typed API client generated from OpenAPI
  config/         shared tsconfig, eslint, vitest presets
  i18n/           pt-BR and en messages
docs/
```

### 4.2 Backend conventions (shared with Life Deck)

- Responses `{ data }` or `{ error: { code, message, details? } }`. Zod validation
  failures return 422. Cursor pagination. OpenAPI generated from Zod schemas.
- Auth: JWT in an httpOnly cookie for web, Bearer header for mobile. Single user per
  tenant at first; household members later.
- Composition root at `apps/api/src/server/container.ts`. Use cases receive ports,
  never adapters.
- Money is integer cents plus ISO currency. Dates are stored in UTC and computed in
  `America/Sao_Paulo` for due dates and business days.
- Every outbound side effect (payment, invoice, transfer) carries an idempotency key
  and writes an audit event.

### 4.3 Ports

| Port | Adapters |
|---|---|
| `OpenFinanceProvider` | Pluggy, Fake |
| `StatementImporter` | Nomad bill (PDF or CSV via Gemini), B3 position XLSX, generic OFX and CSV |
| `BillSource` | Gmail, ShareIntake, Camera, Chat, C6 DDA, Polp DDA |
| `PaymentRail` | MercadoPagoPayouts, Asaas, InterEmpresas, C6Empresas, Assisted, Fake |
| `InvoiceIssuer` | Notaas, SefinNacional, FocusNfe, Fake |
| `LlmProvider` | Gateway (Gemini Flash Lite with Flash fallback), Gemini direct, Mock |
| `Notifier` | FCM, InApp, Fake |
| `SecretVault` | Envelope encryption in Postgres (key from env), Fake |
| `Clock`, `IdGenerator` | System, Fixed |

### 4.4 Domain model (first cut)

`Tenant`, `User`, `FinancialEntity` (PF or PJ, tax id, tax regime), `Institution`,
`Connection` (provider, item id, status, last sync), `Account`, `Transaction`,
`Category`, `CategoryRule`, `Budget`, `Recurrence`, `CreditCardBill`, `Holding`,
`Goal`, `Bill`, `PaymentPlan`, `PaymentAttempt`, `Invoice`, `InvoiceTemplate`,
`InvoiceClient`, `TaxGuide`, `Alert`, `AuditEvent`, `ChatThread`, `ChatMessage`.

### 4.5 Mobile conventions (shared with the Obra Nova app)

- Feature-first clean architecture: `lib/features/<feature>/{domain,application,data,presentation}`.
- Riverpod 3 for DI and state, go_router, dio, `Result<T>` with `AppFailure`.
- Fake backend by default; `--dart-define=BACKEND=api` switches to the real API.
- mocktail; `test/architecture/layer_rules_test.dart` enforces the layers.
- Light and dark themes from design tokens exported by Claude Design.

## 5. Payment ladder

Each bill gets a `PaymentPlan`: the ordered list of rails able to pay it for its
owning entity. The orchestrator tries them in order and records every attempt.

| Step | Mode | What the user does | When it moves down |
|---|---|---|---|
| 1 | Automatic | Nothing | Rail error, unsupported kind, insufficient funds, cap exceeded |
| 2 | Approval in bank | Approves the batch in the bank's web banking | Not approved before the cutoff |
| 3 | Assisted | Pays with the copied code or Pix payload | Never; it stays open until marked paid or the bill is cancelled |

### 5.0 Pix first

Most boletos now carry a Pix BR Code next to the barcode ("boleto com Pix"),
and DAS guides do too. Whenever a bill carries a BR Code, the ladder pays it by
Pix first, with the entity's Pix QR rails, then tries the barcode rails, then
falls to assisted, which shows the Pix copy-and-paste first and the barcode
second. The order is the same for PF and PJ; PF still has no step 2. Once an
attempt on either method is paid or pending, no other step runs for that bill.

### 5.1 PF routing (default)

| Bill kind | Step 1 | Step 2 | Step 3 |
|---|---|---|---|
| Pix to a key | Mercado Pago Payouts from the reserve | none | Assisted |
| Pix QR, boleto | Pix from the reserve to Asaas on the due date, then Asaas pays (by Pix when the bill carries a BR Code, then by barcode) | none | Assisted (Pix code first) |
| Tax guide (PF DARF) | Asaas by Pix, only when the guide carries a BR Code | none | Assisted |

### 5.2 PJ routing (default)

| Bill kind | Step 1 | Step 2 | Step 3 |
|---|---|---|---|
| Pix to a key | Inter Empresas | C6 schedule-payments batch | Assisted |
| Boleto | Inter Empresas (Pix first when the bill carries a BR Code, then barcode) | C6 schedule-payments batch | Assisted (Pix code first) |
| DAS, DARF, GPS with barcode | Inter Empresas (Pix first when the guide carries a BR Code, then barcode) | none (C6 batch accepts only `BOLETO` and `PIX`) | Assisted |
| DARF without barcode | Inter Empresas `/banking/v2/pagamento/darf` | none | Assisted |

### 5.3 Safety rules

- Per-rail and per-day caps, configurable per entity.
- First payment to a new payee always requires an in-app confirmation.
- Amount above a threshold, or differing from the recurrence by more than a set
  percentage, requires confirmation.
- Funding transfers (reserve to Asaas) are scheduled for the morning of the due
  date and sized to the exact sum of that day's bills.
- A global kill switch pauses all automatic steps; bills fall to assisted.
- Webhooks and polling reconcile the final status; a bill is `PAID` only when a rail
  confirms or the user marks it with proof.

## 6. Invoices (NFS-e)

### 6.1 Context checked on 2026-10-08

- The reference profile for validation is a Simples Nacional IT services company
  in Mogi das Cruzes (SP), a city that illustrates the transition case.
- Mogi das Cruzes keeps its own issuer (SIL Tecnologia) integrated with the National
  Environment, and is **not** on the Emissor Nacional. Direct emission through the
  Sefin Nacional API is rejected there (error E0039) until the city joins.
- Simples Nacional companies must issue in the national standard from November 2026
  (CGSN; dates moved more than once, so this stays a configuration value).

### 6.2 Features

- **Issue NFS-e** for domestic clients and service exports (no ISS, PIS or COFINS on
  exports; amount in foreign currency with the conversion rate stored).
- **Recurring invoices.** `InvoiceTemplate` per client (description, service code,
  amount or rate, currency, day of month). Each cycle creates a draft and asks for
  approval in the app or chat before emission.
- **Taxes and reconciliation.**
  - Estimate the monthly DAS from issued invoices: RBT12, Annex III or V by Fator R,
    and export revenue excluded from ISS, PIS and COFINS.
  - Match each invoice to its receipt in the bank feed (including FX receipts).
  - Match each tax guide to its payment.
  - Flag gaps: an invoice not paid, a receipt without an invoice, a month without a
    DAS.
- Cancellation and replacement through the issuer, with the reason recorded.
- PDF and XML stored per invoice; monthly export for the accountant.

### 6.3 Issuer adapters

| Adapter | Use |
|---|---|
| Notaas | Default. Free tier: 50 invoices a month, 1 CNPJ, A1 certificate, webhooks. Coverage of Mogi das Cruzes not yet confirmed |
| SefinNacional | Direct, no per-invoice cost, A1 certificate. Usable once the municipality joins the Emissor Nacional |
| FocusNfe | Paid fallback (from R$89.90 a month); documents Mogi das Cruzes |

The A1 certificate is stored encrypted through `SecretVault` and never leaves the API.

## 7. Open Finance and imports

- **Meu Pluggy** (free, personal use): 5 connections, 24h refresh, no categorization,
  no identity, item ids copied from the Pluggy dashboard into Cashdeck settings,
  webhooks supported. The `OpenFinanceProvider` port also accepts a paid Pluggy
  plan without code changes.
- Coverage notes: Mercado Pago and Inter are fully listed; 99Pay returns accounts
  and transactions only; Nomad and B3 are not listed.
- **Nomad**: manual institution; card bill PDF or CSV imported at each closing,
  parsed by Gemini into a draft the user confirms.
- **B3**: the Área do Investidor API is licensed B2B (yearly fee floor), so Phase 1
  imports the position and movement XLSX; a `B3Licensed` adapter can be added later.
- Credit card bills, installments and up to 12 months of history come from the
  Pluggy `Bill` and transaction endpoints.

## 8. AI chat

Reused from Obra Nova (`src/infra/llm`, `src/application/usecases/whatsapp`), adapted
to the app chat instead of WhatsApp:

- `LlmProvider` with gateway fallback, pricing and embeddings.
- Tool framework (`types`, `runTool`, `registry`) with the server filling the
  context, so the model never chooses the tenant or entity.
- Two-step confirmation for any tool with side effects (pay, schedule, issue
  invoice, create rule).
- `runAgentTurn` (bounded rounds and time budget, retry after an empty answer),
  turn lock, rate limiter, quota with kill switch.
- Audio transcription and receipt reading through attachments.
- Prompt hardening (`redFlags`, `sanitize`) and pgvector memory.

First tools: query transactions, summarize period, compare categories, list bills,
create bill from attachment, schedule payment, explain a charge, create
categorization rule, draft invoice, net worth snapshot.

## 9. Security and privacy

- Self-hosted; no telemetry by default.
- Provider tokens, bank API credentials, client certificates and the A1 certificate
  are encrypted at rest with envelope encryption; the key lives only in env.
- mTLS client certificates (Inter, C6) loaded from the vault at call time.
- Every payment and invoice action writes an `AuditEvent` with actor, rail, request
  id and result.
- Webhooks verified by signature or shared secret, replay-protected by id.
- Backups are the operator's responsibility; the docs ship a Neon branch and restore
  recipe.

## 10. Quality gates

- Backend: Vitest, 95% coverage overall, 100% on `domain` and `application`;
  dependency-cruiser rules for layering; contract tests per adapter against recorded
  fixtures; every adapter has a Fake used by the use case tests.
- Mobile: `tool/check.sh` (format, analyze, test with coverage); domain and
  application at 100%, core at 95%, total at 90%.
- CI runs both gates on every pull request. No network in unit tests.

## 11. Delivery order

The payment ladder ships complete (all three steps) the first time payments ship.
Phases group features, not partial versions of the ladder.

### Phase 0: spikes (validate with real accounts before building)

1. Inter Empresas API integration approval, then a boleto, a DAS and a DARF payment
   in production with a small amount.
2. C6 Empresas homologation: DDA query and a schedule-payments batch.
3. Mercado Pago Payouts for a PF account (eligibility, signing key exchange).
4. Asaas PF: Pix in, boleto payment out, transfer token disabled.
5. Notaas: emission in Mogi das Cruzes for one domestic and one export invoice in
   the sandbox, then production.
6. Meu Pluggy: connect every institution in use, confirm the webhook flow.

Each spike ends with a short report in `docs/spikes/` and, when it fails, the
adapter falls back as section 5 or 6.3 describes.

### Phase 1: the daily loop

Monorepo, auth, entities (PF and PJ), Pluggy sync, manual institutions with Nomad
import, transactions with AI categorization, credit card bills, bill capture (all
sources), payment ladder (all rails that passed Phase 0), NFS-e with recurring
templates, alerts, AI chat with read tools and the payment and invoice tools.

### Phase 2: planning

Budgets, recurrences and subscriptions, goals, investments and net worth, B3 XLSX
import, DAS estimate and reconciliation, monthly AI analysis, accountant export.

### Phase 3: expansion

Household members, hosted multi-tenant mode, B3 licensed adapter, Polp DDA,
additional banks as rails, Life Deck merge.

## 12. Provider matrix

| Provider | Holder | Pix via API | Boleto and tax guides via API | Yield | Cost | Role |
|---|---|---|---|---|---|---|
| Mercado Pago | PF | Yes, to a key (Payouts) | No | about 100% CDI | Free | PF reserve |
| Asaas | PF and PJ | Yes, key and QR | Boleto yes; DARF no | No | Free (PF) | PF payer |
| Inter Empresas | PJ | Yes | Boleto, DAS, DARF (with or without barcode) | Only the manual "Porquinho" | Free | PJ payer |
| C6 Empresas | PJ | Batch, needs approval | Boleto batch, needs approval; no tax guides | No | Free after homologation | PJ step 2 and DDA |
| Pluggy | PF and PJ | Paid plan only | No | n/a | Meu Pluggy free | Read |
| Polp Super DDA | PF and PJ | No | Discovery only | n/a | R$199 a month plus R$0.35 per boleto | Optional source |
| Notaas | PJ | n/a | n/a | n/a | Free up to 50 invoices a month | NFS-e issuer |
| Focus NFe | PJ | n/a | n/a | n/a | From R$89.90 a month | NFS-e fallback |

Evaluated and not used: 99Pay, RecargaPay and InfinitePay (no payment API for
personal use), Efí Pro (Pix limit too low for personal accounts), Cora (each
payment approved in its app), Transfeera (commercial onboarding for established
companies), TecnoSpeed, Azify, Dock, Diletta, Oracle and Accesstage (B2B
infrastructure).

### Sources

- Pluggy: https://docs.pluggy.ai/en/reference, https://www.pluggy.ai/pricing
- Mercado Pago: https://www.mercadopago.com.br/developers/pt/reference
- C6 schedule-payments: https://developers.c6bank.com.br/yamls/schedule-payments.yaml
- Inter Empresas: https://developers.inter.co/references/banking,
  https://ajuda.kobana.com.br/pt-BR/articles/9580163-como-fazer-pagamentos-pela-api-do-banco-inter
- Inter API onboarding changes in 2026:
  https://www.reclameaqui.com.br/inter/api-do-banco-inter-desabilitada-impactando-clientes-pj__T_cOOLAjs904hv-/
- Notaas pricing: https://www.notaas.com.br/
- Mogi das Cruzes NFS-e status:
  https://www.projetoacbr.com.br/forum/topic/88024-acbrnfsex-erro-e0039-mogi-das-cruzes-sil-tecnologia-padr%C3%A3o-nacional/,
  https://nfe.io/docs/prefeituras-integradas/sao-paulo/mogi-das-cruzes-sp-3530607/
- NFS-e Nacional deadlines: https://contaazul.com/blog/nfse-padrao-nacional/
- Focus NFe pricing: https://focusnfe.com.br/precos/

## 13. Risks and open questions

1. Inter now reviews new API integrations manually; if refused, C6 becomes the PJ
   default and tax guides stay assisted.
2. Mercado Pago Payouts eligibility for PF accounts is unconfirmed.
3. Notaas is a young vendor and its Mogi das Cruzes coverage is unconfirmed; the
   port keeps FocusNfe and SefinNacional ready.
4. Meu Pluggy terms limit use to personal; a hosted Cashdeck needs a paid plan.
5. Pro-labore and payroll inputs are needed for the Fator R; first version takes
   them as monthly manual entries.
6. Life Deck merge: shared auth and entity model must be agreed before Phase 3.
