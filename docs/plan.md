# Cashdeck: product scope and roadmap

Cashdeck is an open-source, self-hosted finance app for households in Brazil
that manage a personal profile (PF) and, optionally, a company (PJ). It reads
accounts through Open Finance, captures bills from every channel, pays them
through an escalating payment ladder, issues service invoices (NFS-e), plans
the month and offers a multimodal AI chat over the whole picture.

This document covers the product principles, the scope, the payment ladder and
the roadmap. How the code is organized is in [architecture.md](architecture.md);
the HTTP contract is in [api.md](api.md).

## 1. Principles

1. **Generic.** No personal names, accounts or documents in code, seeds or docs.
   Every institution, provider and rule is configuration.
2. **Ports and adapters.** Every external system sits behind a port in the
   application layer. Adapters are swappable, and each one ships with a fake.
3. **Automatic first, human always available.** Every payment walks a ladder
   (automatic, approval in the bank, assisted). A failure moves one step down,
   never to silence.
4. **Self-hosted, multi-tenant ready.** One deployment serves one household,
   but every row carries `tenantId` and every query is scoped by it.
5. **PF and PJ from the start.** A `FinancialEntity` (person or company) owns
   accounts, bills, budgets and invoices. Transfers between entities are
   first-class.
6. **Quality gates are code.** Coverage, layering and lint rules fail the build.

## 2. Stack

| Topic        | Choice                                                                       |
| ------------ | ---------------------------------------------------------------------------- |
| Distribution | Self-hosted, single household per deployment                                 |
| Mobile       | Flutter, Riverpod, go_router; fake backend by default                        |
| Backend      | Next.js 16 route handlers under `/api/v1`, TypeScript, zod, OpenAPI          |
| Hosting      | Vercel (functions and crons)                                                 |
| Database     | Postgres on Neon through Prisma 7, pgvector for chat memory                  |
| AI           | Vercel AI Gateway or Gemini direct                                           |
| Open Finance | Pluggy (the free Meu Pluggy tier works), plus an optional preview feed      |
| PF payer     | Asaas (Pix key, Pix QR, boleto) from its own balance                         |
| PJ payer     | Inter Empresas, with C6 Empresas as the approval step                        |
| Invoices     | Notaas behind an `InvoiceIssuer` port                                        |

## 3. Scope

### 3.1 Core finance

- **Institutions and accounts.** Connected (Pluggy), manual, and the reserve
  the personal bills are paid from. Checking, savings, credit card, investment
  and wallet account types. An account can name which household member holds
  it.
- **Transactions.** Sync, dedupe, transfers between own accounts (including
  Pix between household members), notes and attachments. Categorization by
  user rules first, the model second, with a review queue.
- **Credit cards.** Bills (open, closed, paid), installments, per-card limits.
  Cards without Open Finance get a bill import (PDF read by the model) every
  time a bill closes.
- **Budgets by category**, monthly, with alerts.
- **Recurrences and subscriptions.** Detected from history, with price-change
  alerts.
- **Investments and net worth.** Holdings from Pluggy with history and
  performance, goods (real estate, vehicles priced by FIPE, other assets),
  loans, and a net worth timeline per entity and consolidated.
- **Planning.** Safe to spend for the month, goals, a life plan, a cash-flow
  outlook and a monthly recap.

### 3.2 Bills and payments

- **Bill capture (`BillSource` port).** Gmail (boletos, DARF, DAS and card
  bills as PDF or inline codes), the C6 Empresas DDA for the company, and, in
  the app, shared files, pasted codes, the camera and the chat.
- **Bill model.** Payee, amount, due date, barcode or Pix payload, kind
  (`BOLETO`, `PIX_KEY`, `PIX_QR`, `TAX_BARCODE` for DARF, DAS and GPS with a
  barcode, `DARF_NO_BARCODE`), owning entity, status, source, attachments.
- **Payment ladder** (section 4).

### 3.3 Company (PJ)

- Separate entity with its own accounts, bills, budgets and reports.
- Monthly tax calendar: DAS (Simples Nacional), DARF from DCTFWeb (pro-labore
  INSS and IRRF), and any other guide the accountant sends.
- Profit distribution to the PF modeled as an inter-entity transfer, so neither
  side reads it as income or expense twice.
- **Invoices (NFS-e)**, section 5.

### 3.4 AI

- Multimodal chat (text, image, audio, PDF) with tools over the user's data.
  Any tool with side effects (pay, schedule, issue an invoice, create a rule)
  asks for confirmation in a second step.
- The server fills the tenant and entity of every tool call; the model never
  chooses them. Turns are bounded in rounds and time, with a daily quota per
  tenant and a kill switch.
- Bill, card statement and receipt extraction from images and PDFs.

### 3.5 Alerts

Bill due soon, bill paid, payment failed and moved down the ladder, approval
pending in a bank, budget threshold, low reserve balance before a ladder run,
card bill closed, subscription price change, a failed background job, and the
monthly recap. Delivered as push notifications and in an in-app inbox; each
alert type can be muted.

## 4. Payment ladder

Each bill gets a `PaymentPlan`: the ordered list of rails able to pay it for
its owning entity. The orchestrator tries them in order and records every
attempt.

| Step | Mode             | What the user does                           | When it moves down                                             |
| ---- | ---------------- | -------------------------------------------- | -------------------------------------------------------------- |
| 1    | Automatic        | Nothing                                      | Rail error, unsupported kind, insufficient funds, cap exceeded |
| 2    | Approval in bank | Approves the batch in the bank's web banking | Not approved before the cutoff                                 |
| 3    | Assisted         | Pays with the copied code or Pix payload     | Never; it stays open until marked paid or cancelled            |

### 4.1 Pix first

Most boletos now carry a Pix BR Code next to the barcode, and DAS guides do
too. Whenever a bill carries a BR Code, the ladder pays it by Pix first, then
tries the barcode rails, then falls to assisted, which shows the Pix copy and
paste first and the barcode second. Once an attempt on either method is paid
or pending, no other step runs for that bill.

### 4.2 PF routing (default)

| Bill kind           | Step 1                                                    | Step 2 | Step 3                    |
| ------------------- | --------------------------------------------------------- | ------ | ------------------------- |
| Pix to a key        | Asaas                                                     | none   | Assisted                  |
| Pix QR, boleto      | Asaas (by Pix when the bill carries a BR Code, then code) | none   | Assisted (Pix code first) |
| Tax guide (PF DARF) | Asaas by Pix, only when the guide carries a BR Code       | none   | Assisted                  |

No provider moves money into Asaas by API, so the Asaas balance is the reserve
and is topped up by hand: a bill it cannot cover falls to assisted with
`RESERVE_FUNDING_FAILED`. The daily alerts raise `LOW_BALANCE` the day before
a ladder run that the balance does not cover, and `GET /home/personal/funding`
gives the monthly average those bills take, to size a recurring transfer.

### 4.3 PJ routing (default)

| Bill kind                   | Step 1                                                         | Step 2                                          | Step 3                    |
| --------------------------- | -------------------------------------------------------------- | ----------------------------------------------- | ------------------------- |
| Pix to a key                | Inter Empresas                                                 | C6 schedule-payments batch                      | Assisted                  |
| Boleto                      | Inter Empresas (Pix first when the bill carries a BR Code)     | C6 schedule-payments batch                      | Assisted (Pix code first) |
| DAS, DARF, GPS with barcode | Inter Empresas (Pix first when the guide carries a BR Code)    | none (the C6 batch takes only boleto and Pix)   | Assisted                  |
| DARF without barcode        | Inter Empresas `/banking/v2/pagamento/darf`                    | none                                            | Assisted                  |

### 4.4 Safety rules

- Per-rail and per-day caps, plus a daily cap per entity and a cap per
  payment, configurable per entity. The last two bound automatic steps only.
- The first payment to a new payee always requires an in-app confirmation. The
  payee is the real recipient: the Pix key of the BR Code (the merchant for a
  dynamic code), the bank and payee of a boleto. The daily alerts ask for it
  up to 3 days before the due date, with a push; a confirmation given before
  the payment day is kept and the ladder pays on schedule.
- An amount above a threshold, or differing by more than a set percentage (30%
  by default) from the median of the last paid bills to the same recipient,
  requires confirmation.
- Every rail call is written as an in-flight attempt first. A call whose answer
  is lost is never sent again: the rail is asked by idempotency key, and an
  unresolved one falls to assisted.
- A bank approval batch still pending at the cutoff (16:00 in São Paulo on the
  due date by default) falls to assisted.
- A global kill switch pauses all automatic steps; bills fall to assisted.
- A payee marked as bank auto-debit is never paid by the app: its bills wait,
  without alerts or funding, until the debit shows in the statement.
- Webhooks and polling reconcile the final status; a bill is `PAID` only when a
  rail confirms or the user marks it with proof.

## 5. Invoices (NFS-e)

- **Issue NFS-e** for domestic clients and service exports (no ISS, PIS or
  COFINS on exports; amount in foreign currency with the conversion rate
  stored).
- **Recurring invoices.** An `InvoiceTemplate` per client (description, service
  code, amount, currency, day of month). Each cycle creates a draft and asks
  for approval in the app before emission.
- **Taxes and reconciliation.**
  - Estimate the monthly DAS from issued invoices: RBT12, Annex III or V by
    Fator R, and export revenue excluded from ISS, PIS and COFINS. Each market
    takes its rate from its own RBT12 (LC 123/2006 art. 3, par. 15).
  - Price the ISS of each domestic invoice from the domestic RBT12 and the
    annex, capped at 5%. Months billed before the app are entered by hand
    (`PUT /api/v1/revenue/{month}`).
  - Match each invoice to its receipt in the bank feed, and flag an invoice not
    paid or a receipt without an invoice.
- PDF and XML stored per invoice; a monthly export for the accountant.

Simples Nacional companies must issue in the national standard from November
2026, and some cities keep their own issuer integrated with the National
Environment instead of joining the Emissor Nacional. That is why emission sits
behind the `InvoiceIssuer` port: Notaas today, a direct Sefin Nacional adapter
once a city joins.

The A1 certificate is stored encrypted through `SecretVault` and never leaves
the API.

## 6. Open Finance

- **Meu Pluggy** (free, personal use): 24h refresh, no categorization, item ids
  copied from the Pluggy dashboard into Cashdeck. A second Pluggy account can
  be configured, each item served by the account that owns it. A paid Pluggy
  plan works without code changes.
- **Preview feed.** Pluggy collects free items once a day, so an optional
  second feed (Pierre) brings provisional movements in between; the main feed
  confirms or drops them.
- Credit card bills, installments and up to 12 months of history come from the
  Pluggy bill and transaction endpoints.

## 7. Security and privacy

- Self-hosted; no telemetry by default (Sentry only when `SENTRY_DSN` is set).
- Provider tokens, bank API credentials, client certificates and the A1
  certificate are encrypted at rest with envelope encryption; the key lives
  only in the environment.
- mTLS client certificates (Inter, C6) are loaded from the vault at call time.
- Every payment and invoice action writes an audit event with actor, rail,
  request id and result.
- Webhooks are verified by signature or shared secret and replay-protected by
  event id.
- Backups are the operator's responsibility.

## 8. Roadmap

Not built yet, in no fixed order:

- Bill sources: a paid DDA aggregator for the personal entity.
- Statement imports: investment positions from B3 and generic OFX or CSV files
  (the `StatementImporter` port exists with a fake only).
- NFS-e: a direct Sefin Nacional adapter and a paid fallback issuer.
- Push notifications on iOS.
- A hosted, multi-tenant mode with more than one user per household.
- More banks as payment rails.

## 9. Provider matrix

| Provider       | Holder    | Pix via API           | Boleto and tax guides via API                      | Cost                    | Role                    |
| -------------- | --------- | --------------------- | -------------------------------------------------- | ----------------------- | ----------------------- |
| Asaas          | PF and PJ | Yes, key and QR       | Boleto yes; DARF no                                | Free (PF)               | PF payer                |
| Inter Empresas | PJ        | Yes                   | Boleto, DAS, DARF (with or without barcode)        | Free                    | PJ payer                |
| C6 Empresas    | PJ        | Batch, needs approval | Boleto batch, needs approval; no tax guides        | Free after homologation | PJ step 2 and DDA       |
| Pluggy         | PF and PJ | Paid plan only        | No                                                 | Meu Pluggy free         | Read                    |
| Notaas         | PJ        | n/a                   | n/a                                                | Free up to 50 a month   | NFS-e issuer            |

Evaluated and not used: Mercado Pago (Payouts only with a commercial
agreement), 99Pay, RecargaPay and InfinitePay (no payment API for personal
use), Efí Pro (Pix limit too low for personal accounts), Cora (each payment
approved in its app), Transfeera (commercial onboarding for established
companies), and B2B payment infrastructure vendors.

### Sources

- Pluggy: https://docs.pluggy.ai/en/reference, https://www.pluggy.ai/pricing
- C6 schedule-payments: https://developers.c6bank.com.br/yamls/schedule-payments.yaml
- Inter Empresas: https://developers.inter.co/references/banking
- Notaas: https://www.notaas.com.br/
- NFS-e national standard deadlines: https://contaazul.com/blog/nfse-padrao-nacional/

## 10. Risks

1. Inter reviews new API integrations manually; if refused, C6 becomes the PJ
   default and tax guides stay assisted.
2. No PF provider moves money into Asaas by API, so its balance is topped up by
   hand; `LOW_BALANCE` warns the day before a short ladder run.
3. Notaas is a young vendor; the `InvoiceIssuer` port keeps other issuers
   possible.
4. Meu Pluggy terms limit use to personal; a hosted Cashdeck needs a paid plan.
5. Pro-labore and payroll inputs for the Fator R are monthly manual entries.
