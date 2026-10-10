Status: final

# Cashdeck API contract (v1)

Every path below is under `/api/v1`. The OpenAPI document at
`/api/v1/openapi` is generated from the same Zod schemas and is the
machine-readable version of this file.

## Conventions

- **Envelope.** Success is `{ "data": ... }`. A paginated list is
  `{ "data": [...], "nextCursor": string | null }`. Failure is
  `{ "error": { "code": string, "message": string, "details"?: unknown } }`.
- **Error codes.** `UNAUTHORIZED` 401, `NOT_FOUND` 404, `CONFLICT` 409,
  `INVALID_TRANSITION` 409, `VALIDATION_ERROR` 422, `AMOUNT_REQUIRED` 422
  (see Bills), `INVALID_JSON` 400,
  `RATE_LIMITED` 429 (the daily AI chat quota),
  `NOT_CONFIGURED` 503 (a provider or the server token is missing),
  `PROVIDER_ERROR` 502, `INTERNAL_ERROR` 500.
- **Money** is always an object `{ "cents": int, "currency": "BRL" }`. Cents are
  integers; negative means money leaving.
- **Dates** are `YYYY-MM-DD` (São Paulo calendar day). **Timestamps** are ISO
  8601 UTC strings (`2026-10-08T12:00:00.000Z`). A month is `YYYY-MM`.
- **Entity.** One tenant has one personal entity (`PF`) and at most one company
  (`PJ`). Endpoints that act on one of them take `entity=PF|PJ` (query or body).
  Records carry `entityKind: "PF" | "PJ"`.
- **Binary uploads** are JSON with a base64 payload:
  `{ "fileName": string, "mimeType": string, "base64": string }`, at most 5 MB
  decoded.
- **Pagination.** `cursor` (opaque string) and `limit` (1 to 100, default 50).

## Auth

Self-hosted and single-household: the server has one access token, set in the
`CASHDECK_API_TOKEN` environment variable. Every request sends
`Authorization: Bearer <token>`. The only routes that skip it are
`GET /health`, `GET /openapi` and the mailbox OAuth callback (which checks a
signed `state` instead). Crons and provider webhooks live outside `/api/v1`
and have their own checks (see [Crons](#crons) and [Webhooks](#webhooks)). If the server has no token configured, every guarded
route answers 503 `NOT_CONFIGURED`. Biometric unlock is local to the app.

### GET /auth/check

Validates the token; the app calls it when the user signs in with server URL
plus token, and on every cold start.

```json
{
  "data": {
    "server": { "name": "Cashdeck", "version": "v1", "tenantId": "local" },
    "entities": [
      { "id": "personal", "kind": "PF", "name": "Personal" },
      { "id": "company", "kind": "PJ", "name": "Company" }
    ]
  }
}
```

A wrong or missing token returns 401 `UNAUTHORIZED`.

## Entities

### GET /entities

`data`: array of `{ id, kind: "PF"|"PJ", name, taxId: string, taxRegime: string | null }`.

### PATCH /entities/{id}

Body: `{ name?, taxId?, taxRegime?: "SIMPLES_NACIONAL"|"MEI"|"LUCRO_PRESUMIDO"|"LUCRO_REAL" | null }`.
The tax id may be formatted; it must be a valid CPF for `PF` and CNPJ for
`PJ`, and a `PJ` keeps a regime. Answers the updated entity and writes an
`entity.update` audit event. 404 for an unknown id, 422 for an invalid tax id.

## Home

### GET /home/personal

```json
{
  "data": {
    "balance": Money,
    "sync": { "accountCount": int, "syncedAt": timestamp | null },
    "reserve": {
      "accountId": string,
      "institution": string,
      "product": string,
      "balance": Money,
      "monthYield": Money,
      "coverDays": int,
      "cdiPercent": int | null
    } | null,
    "forecast": { "from": date, "balances": [Money], "floor": Money },
    "budgets": [{ "category": string, "spent": Money, "limit": Money }],
    "alerts": [
      { "type": "ASSISTED_PAYMENT", "at": timestamp, "billId": string, "payee": string, "reason": string },
      { "type": "BUDGET_EXCEEDED", "at": timestamp, "budget": { "category": string, "spent": Money, "limit": Money } }
    ]
  }
}
```

- `balance` sums the entity's checking, savings and wallet accounts, the reserve
  excluded.
- `forecast.balances` has 31 entries: today and the next 30 days, starting
  from `balance` plus the reserve, applying the
  average daily spend of the last 30 days and every open bill on its due date.
  `floor` is zero.
- `coverDays` is how many days of open bills, in due date order, the reserve
  pays for (capped at 90).
- `budgets[].category` is the category name in lower case (`transport`,
  `groceries`, `restaurants`, or any other the user created).
- `alerts[].reason` for an assisted payment is the failure code of the last
  failed attempt (`NOT_CONFIGURED`, `DAILY_CAP_EXCEEDED`,
  `ENTITY_DAILY_CAP_EXCEEDED`, `PAYMENT_CAP_EXCEEDED`, `RESERVE_FUNDING_FAILED`,
  `APPROVAL_EXPIRED`, `IN_FLIGHT_UNRESOLVED`, `RAIL_UNAVAILABLE`,
  `CONFIRMATION_DECLINED`, or the rail's message).

### GET /home/personal/funding

```json
{
  "data": {
    "balance": Money | null,
    "monthlyAverage": Money,
    "months": [{ "month": "2026-10", "total": Money }],
    "upcoming": Money,
    "topUp": Money
  }
}
```

What the Asaas balance pays for the person, to size a recurring top-up.

- `months` runs from the month of the first personal bill, at most six back,
  to the current one. Each `total` sums the bills due that month however they
  were paid; cancelled bills and payees on bank auto-debit are left out.
- `monthlyAverage` is the mean of `months`.
- `upcoming` sums the open bills and those awaiting confirmation due in the
  next 30 days, and `topUp` is what of it `balance` does not cover.
- `balance` is null when the Asaas balance cannot be read; `topUp` then equals
  `upcoming`.

### GET /home/company

```json
{
  "data": {
    "cash": Money,
    "sync": { "accountCount": int, "syncedAt": timestamp | null },
    "billed": Money,
    "invoiceCount": int,
    "dasEstimate": Money,
    "dasDue": date,
    "annex": "III" | "V",
    "drafts": [{ "id": string, "customer": string, "amount": Money, "recurring": bool, "issueOn": date }],
    "unbilled": [{ "id": string, "payer": string, "amount": Money, "receivedOn": date }]
  }
}
```

- `billed` and `invoiceCount` cover invoices issued in the current month.
- `dasEstimate` applies the Simples Nacional effective rate (Annex III or V by
  Fator R) to this month's revenue, with export revenue free of ISS, PIS and
  COFINS. `dasDue` is the 20th of next month, moved back to a business day.
- `unbilled` lists company income of the last 60 days with no invoice linked.

### POST /home/company/drafts/{invoiceId}/approve

Issues the draft through the configured invoice issuer. Returns the company
summary (same shape as `GET /home/company`).

### POST /home/company/unbilled/{transactionId}/invoice

Creates and issues an invoice for that receipt, linking the two. Returns the
company summary.

### GET /home/consolidated

```json
{
  "data": {
    "personal": Money,
    "company": Money,
    "externalIn": Money,
    "externalOut": Money,
    "transfers": [{ "id": string, "kind": "PROFIT_DISTRIBUTION" | "PRO_LABORE", "amount": Money, "on": date }]
  }
}
```

`externalIn` and `externalOut` (negative) cover the current month and leave out
every transaction linked to an internal transfer, so nothing counts twice.

## Accounts

### GET /accounts?entity=PF|PJ

`data`: array of

```json
{
  "id": string, "entityKind": "PF"|"PJ", "institution": string, "name": string,
  "type": "CHECKING"|"SAVINGS"|"CREDIT_CARD"|"INVESTMENT"|"WALLET",
  "origin": "CONNECTED"|"MANUAL", "isReserve": bool, "balance": Money,
  "cdiPercent": int | null, "connectionId": string | null,
  "numberSuffix": string | null,
  "logo": { "imageUrl": string, "color": string | null } | null,
  "credit": { "limit": Money, "available": Money, "usedPercent": int | null,
              "closesOn": date | null, "dueOn": date | null, "brand": string | null } | null,
  "openBill": Money | null,
  "sync": { "status": string, "lastSyncAt": timestamp | null } | null
}
```

`entity` is optional; without it both entities are listed.

A card's `balance` is everything owed on it, future installments included,
so it is the limit in use and not money. `openBill` is what a card owes on its
current bill: the charges the issuer has not billed yet when it marks them,
else the whole amount owed. It is null on every other account type.

`logo.imageUrl` is the Open Finance connector's icon and may be PNG or SVG. An
account mirrored by an aggregator connector takes the bank its name carries;
one whose name carries no bank, such as a card named after its product, takes
the single bank its siblings on the same item resolved to.

### POST /accounts

Manual account (an institution with no Open Finance).
Body: `{ entity, institution: string, name: string, type, currency?: "BRL", isReserve?: bool, balanceCents?: int }`.
Returns the account, 201.

### PATCH /accounts/{id}

Body: `{ name?: string, isReserve?: bool, cdiPercent?: int | null, balanceCents?: int }`
(`balanceCents` only for manual accounts). Returns the account.

`name` renames any account, connected ones included; an Open Finance sync
never overwrites it.

### GET /accounts/{id}/bills

The bills of one credit card, oldest first, for a view that moves through them
month by month. 422 for any other account type, 404 for an unknown id.

```
{
  "accountId": string, "name": string, "suffix": string | null,
  "entityKind": "PF"|"PJ",
  "current": int | null,
  "bills": [{
    "closesOn": date | null, "dueOn": date, "total": Money, "minimum": Money | null,
    "state": "PAST"|"CLOSED"|"OPEN"|"FORECAST",
    "payment": "PAID"|"DUE"|"UNCONFIRMED" | null,
    "range": { "from": date, "to": date },
    "installments": [{ "key": string, "name": string, "categoryId": string | null,
                       "number": int, "count": int, "amount": Money }]
  }]
}
```

`current` is the index of the open bill; it is null only when the card has no
bills at all. The bills before it are the ones the issuer reported, up to a
year back; the open one carries the issuer's own total.

A `FORECAST` bill is a cycle the issuer has not billed yet, dated on the same
closing and due days as the open one. Its `total` is what is already posted to
it plus `installments`, the plans still running whose next charges fall on it:
each plan charges once per bill, from the cycle after the one holding its
latest charge. Forecasts end at the last cycle that holds anything, up to 12
ahead. Subscriptions and new purchases are not projected.

`range` is the booking days a bill holds; `GET /transactions?accountId=&from=&to=`
with it lists the bill's charges. `payment` is set on closed bills: `PAID` when
the credits posted to the card from 5 days before closing to 10 days after the
due date cover the total, `DUE` while the due date is ahead, `UNCONFIRMED`
after it, which can mean a payment the bank did not report.

## Investments

### GET /investments?entity=PF|PJ

The positions every Open Finance item reports, refreshed on each sync of its
connection. Sold positions are left out. `data`:

```json
{
  "total": Money, "invested": Money, "profit": Money,
  "syncedAt": timestamp | null,
  "institutions": [{ "institutionId": string, "institution": string,
                     "logo": { "imageUrl": string, "color": string | null } | null,
                     "total": Money, "count": int }],
  "kinds": [{ "kind": Kind, "total": Money, "count": int }],
  "positions": [{
    "id": string, "entityKind": "PF"|"PJ", "institutionId": string,
    "institution": string, "logo": { ... } | null, "name": string,
    "kind": Kind, "subtype": string | null, "issuer": string | null,
    "status": "ACTIVE"|"PENDING", "balance": Money, "invested": Money | null,
    "profit": Money | null, "profitPercent": number | null,
    "quantity": number | null,
    "rate": { "percent": number | null, "index": string | null,
              "fixedAnnual": number | null } | null,
    "lastMonthRate": number | null, "lastTwelveMonthsRate": number | null,
    "dueOn": date | null, "valuedOn": date | null
  }]
}
```

`Kind` is `FIXED_INCOME`, `FUND`, `EQUITY`, `ETF`, `PENSION`, `STRUCTURED` or
`OTHER`; `subtype` is the provider's own label (`CDB`, `LCI`, `TREASURY`,
`STOCK`, `REAL_ESTATE_FUND`, `MULTIMARKET_FUND` and so on). `balance` is net
of taxes and fees. `profit` is what the provider reports, else `balance` minus
`invested`; `profitPercent` is that profit over `invested`. A rate reads as
`percent` of `index` (102 of CDI) plus `fixedAnnual` points a year (IPCA plus
6.5). The fund rates are the provider's own returns for the period.

Totals and both groupings add up the positions in BRL only, largest first.
Positions of an aggregator item are filed under the bank its accounts resolved
to, as on `GET /accounts`. A position the provider reports no `invested` for
takes what its movements put in, net (buys minus sells), when that is above
zero.

### GET /investments/performance?period=WEEK|MONTH|YEAR&entity=PF|PJ

How the positions held did over the last 7, 30 or 365 days, ending today
(`period` defaults to `MONTH`). `data`:

```json
{
  "period": "MONTH", "from": date, "to": date,
  "start": Money, "end": Money,
  "contributions": Money, "withdrawals": Money, "yield": Money,
  "yieldPercent": number | null, "cdiPercent": number | null,
  "estimated": boolean,
  "series": [{ "day": date, "value": Money }],
  "positions": [{ "id": string, "start": Money, "end": Money,
                  "yield": Money, "yieldPercent": number | null }]
}
```

`start` is what the positions were worth on `from` (each one's last daily
snapshot on or before it, 0 when it has none) and `end` is the current total,
the same as `GET /investments`. `contributions` and `withdrawals` add up the
buys and sells after `from` up to `to`; `yield` is `end - start -
contributions + withdrawals`. `yieldPercent` is the Modified Dietz return:
`yield` over `start` plus each buy (positive) or sell (negative) weighted by
the share of the period left after it, null when that is not above zero.
`cdiPercent` compounds the daily CDI after `from`, null before any rate is
stored. Both are rounded to two decimals. `estimated` is true when a value
behind `start` was rebuilt from market prices rather than synced. `series` has
one point a day (one a week for `YEAR`, always ending on `to`), each the sum of
the positions' last snapshot on or before that day; the last one equals
`end`. `positions` follows the same rules per position, largest yield first.
Only held positions in BRL count, as on `GET /investments`.

### GET /investments/{id}?period=WEEK|MONTH|YEAR

One position of the tenant, 404 otherwise. `data`:

```json
{
  "position": { ...one item of GET /investments positions },
  "performance": { ...GET /investments/performance without positions },
  "movements": [{ "id": string,
                  "kind": "BUY"|"SELL"|"INCOME"|"TAX"|"TRANSFER"|"OTHER",
                  "occurredOn": date, "amount": Money,
                  "quantity": number | null, "unitPrice": number | null }]
}
```

The performance is in the position's own currency. Movements come newest
first; `amount` is always positive and `kind` says which way it went.

### History

Each sync stores the movements the provider lists for every held position
and a snapshot of its balance for the day. The first time a position has no
snapshot older than 7 days, the 366 days before are estimated: units held each
day (the current quantity less the buys and sells after it) times that day's
price, the last Yahoo Finance close for B3 tickers and, for the rest, a
geometric interpolation between the unit prices of its movements and today's.
A position without units or prices keeps its current balance flat. A synced
snapshot replaces an estimated one, never the other way round. The daily CDI
(Banco Central SGS series 12) is fetched from the day after the last one
stored, or 400 days back. None of this fails a sync.

## Transactions

### GET /transactions?entity=&accountId=&categoryId=&uncategorized=&search=&from=&to=&cursor=&limit=

Newest first. `categoryId` keeps one category, `uncategorized=true` keeps the
ones without (it wins over `categoryId`), `search` matches the description or
the note, case-insensitive. `from` and `to` are booking days (`YYYY-MM-DD`),
both included, so the same day twice keeps that day. `data`: array of

```json
{
  "id": string, "accountId": string, "entityKind": "PF"|"PJ", "amount": Money,
  "bookedOn": date, "description": string, "categoryId": string | null,
  "kind": "INCOME"|"EXPENSE"|"TRANSFER", "transferId": string | null,
  "invoiceId": string | null, "note": string | null,
  "categorizedBy": "RULE"|"AI"|"USER" | null,
  "categoryConfidence": number | null
}
```

`categoryConfidence` goes from 0 to 1: 1 for a rule or the user, the model's
own score for `AI` (guesses below 0.5 are not stored).

### PATCH /transactions/{id}

Body `{ categoryId?: string | null, note?: string | null, applyToSimilar?: bool }`
(note at most 500 characters; a blank note clears it). Setting a category marks
it `USER` and learns a rule for the account's entity from the description's
merchant words (bank noise such as `PIX`, `COMPRA` and digits is dropped). When
nothing is left, as on a bare Pix, it learns the rule from the CPF or CNPJ the
bank reports for the other side instead, so every payment to that person
matches. With `applyToSimilar: true` the rule also relabels existing transactions of that
entity that the user did not set. `data`:
`{ transaction: Transaction, similarUpdated: int }`.

### GET /categories

`data`: `[{ id, key: string | null, name, icon: string | null, parentId: string | null }]`,
by name. A tenant with no categories gets the built-in list on the first call;
`key` is the stable slug of a built-in one (`groceries`, `restaurants`,
`transport`, `fuel`, `housing`, `utilities`, `health`, `education`, `leisure`,
`shopping`, `subscriptions`, `travel`, `taxes`, `fees`, `salary`, `income`,
`investments`, `transfers`, `services`, `other`), so the app can translate it.

### POST /categories/rules

Body `{ pattern: string, categoryId: string, entity?: "PF" | "PJ" | null }`.
Learns a rule from the merchant words of `pattern` (bank noise dropped, the same
way `PATCH /transactions/{id}` does) for one entity, or for both when `entity`
is null or left out, and relabels every matching transaction the user did not
set, transfers aside. A pattern of only noise is a 422. `data`:
`{ pattern, categoryId, updated: int }`, 201.

### Automatic categorization

After every Open Finance sync (manual or cron) the server categorizes the
uncategorized transactions of the last 90 days, at most 200 per run: rules
first (`RULE`), then the `LlmProvider` in batches of 40 (`AI`). A failed model
call never fails the sync; the rest waits for the next one.

### Internal transfers

Money between the person and the company. A profit distribution is neutral on
both sides; a pro-labore is the company's expense and the person's income.

`TransferDetail`:

```json
{
  "id": string, "kind": "PROFIT_DISTRIBUTION" | "PRO_LABORE", "amount": Money,
  "at": timestamp, "rail": string,
  "from": { "owner": "PF"|"PJ", "holder": string, "account": string, "accountId": string },
  "to": { "owner": "PF"|"PJ", "holder": string, "account": string, "accountId": string },
  "document": string | null, "neutral": bool
}
```

- `GET /transfers?month=YYYY-MM`: `data` is `[TransferDetail]`, newest first.
- `GET /transfers/{id}`: `data` is `TransferDetail`.
- `POST /transfers`: body `{ kind, amountCents: int, fromAccountId, toAccountId, at?: timestamp, rail?: string, document?: string }`.
  The accounts must belong to different entities. Unlinked transactions of the
  same amount within two days on each account are linked to it. Returns the
  `TransferDetail`, 201.
- `GET /transfers/{id}/document`: the transfer statement as a one page PDF
  (`application/pdf`): kind, amount, date, rail, both parties and `document`
  as the reference.

## Subscriptions

### GET /subscriptions?entity=PF|PJ

Confirmed subscriptions (`items`) and detected ones the user has not decided on
(`suggestions`, `id: null`), each list by charge day. A suggestion is a plain
expense seen in three or more of the last 200 days' months, about once a month,
still running and at a steady price. A metered bill (the last three charges all
differ and spread more than 5%, like power or water) is a recurring bill, not a
subscription, and is never suggested. `data`:

```json
{
  "monthly": Money, "yearly": Money, "previousMonth": Money,
  "changePercent": int | null,
  "items": [Subscription], "suggestions": [Subscription]
}
```

`Subscription`:

```json
{
  "id": string | null, "key": string, "entityKind": "PF"|"PJ", "name": string,
  "amount": Money, "previousAmount": Money | null, "priceChanged": bool,
  "dayOfMonth": int, "lastChargeOn": date | null, "nextChargeOn": date,
  "thisMonth": "PAID"|"UPCOMING"|"LATE",
  "accountId": string | null, "categoryId": string | null,
  "transactionIds": [string],
  "charges": [{ "transactionId": string, "bookedOn": date, "amount": Money }]
}
```

`charges` is newest first, positive amounts. `nextChargeOn` is next month's
charge day once this month is paid, otherwise this month's (also when `LATE`),
clamped to the month's last day. A confirmed subscription whose charges left
the history keeps its stored amount and day with `charges: []`.

- `POST /subscriptions`: body `{ transactionId }`, confirms the recurrence the
  transaction belongs to. `data`: `{ id }`, 201.
- `POST /subscriptions/dismiss`: body `{ transactionId }`, the suggestion is not
  a subscription and is not suggested again. `data`: `{ id }`.
- `DELETE /subscriptions/{id}`: stops tracking a confirmed subscription; it is
  stored as dismissed, so it is not suggested again. `data`: `{ id }`.

## Bills

Unchanged from the first cut, with one difference: the payment plan is built
when a bill is captured, so `plan` is never null.

- `GET /bills?entityId=&status=&cursor=&limit=`: `[BillView]`, by due date.
- `POST /bills`: capture. Body `{ entityId, source?, paymentCode?, pixCode?, pixKey?, darfWithoutBarcode?, amountCents?, dueDate?, payee? }`.
  Send one of: a `paymentCode` (barcode, digitable line or BR Code), a
  `paymentCode` barcode plus its `pixCode` (a "boleto com Pix"), a `pixCode`
  alone (kept as `PIX_QR`), a `pixKey`, or `darfWithoutBarcode: true`. The BR
  Code checksum is verified. A `pixCode` next to a barcode that does not
  validate, or whose amount (printed, or read from the charge of a dynamic
  code) differs from the barcode amount, is dropped and the bill is kept with
  the barcode alone; the reason is written to the audit log
  (`bill.pix_code_dropped`). 201 new, 200 duplicate. Returns `BillView`.
  - **Amount and due date.** The amount comes from the code, then from the
    charge behind a dynamic Pix code (its location is read on the server),
    then from `amountCents`. When none has it the answer is 422
    `AMOUNT_REQUIRED` with `details: { field: "amountCents", kind, payee }`;
    the app asks for the amount and sends the same body again with
    `amountCents` (and `dueDate` if the user gave one). The due date comes
    from the barcode, then the charge (`cobv`), then `dueDate`, then today: a
    Pix code without a due date is an immediate charge, so there is no
    `DUE_DATE_REQUIRED`.
  - **Duplicates and bolepix halves.** A capture is a duplicate (200) when a
    bill that is not cancelled has the same barcode or the same `pixCode`, or
    is a dynamic Pix code with the same location. When one half of a bolepix
    arrives after the other (a barcode bill and then its Pix code, or a Pix QR
    bill and then its barcode) with the same amount and the same due date or
    payee, the missing half is attached to the stored bill (a Pix QR bill
    becomes `BOLETO` or `TAX_BARCODE` with its `pixCode`), its plan is rebuilt
    Pix first, and the answer is 200 with the updated `BillView`. A bill that
    is no longer `OPEN` or has payment attempts is returned unchanged.
- `GET /bills/{id}`: `BillDetailView` (`BillView` plus `plan`, `attempts` and
  `confirmationReason`: the first of `NEW_PAYEE`, `ABOVE_THRESHOLD`,
  `AMOUNT_DEVIATION` that holds a `NEEDS_CONFIRMATION` bill, otherwise null).
- `POST /bills/{id}/pay`: body `{ confirmed?: bool }`. Runs the ladder. Returns
  `BillDetailView` plus `instructions: { kind, copyCode, pixCode, amountCents, dueDate } | null`;
  at the assisted step the app shows `pixCode` first and `copyCode` (the
  barcode) second. A bill stops at `NEEDS_CONFIRMATION` when any of its
  recipients is new (the Pix key of its BR Code, or for a dynamic code the
  merchant name and city; the bank and payee of a boleto; both for a
  bolepix), when it is above `confirmAboveCents`, or when it strays from the
  paid history by more than `maxDeviationPercent`; `confirmed: true` pays it
  and remembers every recipient. The audit log records the call as actor
  `USER` with the API token's hash prefix and the `x-request-id` (or
  `x-vercel-id`) header.
- `POST /bills/{id}/mark-paid`: body `{ attachmentId?: string, proof?: string }`.
  For a bill already paid outside Cashdeck (another account, the bank app).
  `attachmentId` points at a file already attached; `proof` is free text (an
  end-to-end id, or a note on who paid), kept in the audit log. Only this bill
  becomes `PAID` with `paidBy: "USER"`; the ladder and the due-payments cron
  skip it, and the next bills from the same payee are paid as usual. Its
  due-soon and confirmation alerts are marked read. Returns `BillView`.
- `POST /bills/{id}/mark-unpaid`: no body. Undoes `mark-paid`: the bill goes
  back to `OPEN` with `paidAt` and `paidBy` null, so the next ladder run may
  pay it (asking for confirmation again when it needs one). Only a bill with
  `paidBy: "USER"` can be undone; one paid by a rail or settled from the
  statement answers `409 INVALID_TRANSITION`. A bill that is not `PAID` comes
  back unchanged. Returns `BillView`.
- `PUT /bills/{id}/auto-debit`: body `{ enabled: bool }`. Marks every
  recipient of the bill, for its entity, as debited by the bank by itself, so
  this bill and the next ones from that payee carry `autoDebit: true`. The
  ladder never pays an auto-debit bill nor asks to confirm it (a
  `NEEDS_CONFIRMATION` one goes back to `OPEN`), the reserve does not fund it,
  the due-soon alert skips it, and the statement match waits up to 15 days
  after the due date for the debit. Returns `BillDetailView`.

`BillView`:

```json
{
  "id": string, "entityId": string, "entityKind": "PF"|"PJ",
  "kind": "BOLETO"|"PIX_KEY"|"PIX_QR"|"TAX_BARCODE"|"DARF_NO_BARCODE",
  "status": "OPEN"|"NEEDS_CONFIRMATION"|"PROCESSING"|"AWAITING_BANK_APPROVAL"|"ASSISTED"|"PAID"|"CANCELLED",
  "source": "GMAIL"|"SHARE"|"CAMERA"|"CHAT"|"DDA"|"MANUAL",
  "payee": string | null, "amount": Money, "dueDate": date, "code": string | null,
  "pixCode": string | null,
  "createdAt": timestamp, "paidAt": timestamp | null, "paidBy": "RAIL"|"USER"|"STATEMENT" | null,
  "autoDebit": bool
}
```

`BillDetailView` adds
`plan: { steps: [{ mode: "AUTOMATIC"|"BANK_APPROVAL"|"ASSISTED", rail: RailId, method: "PIX"|"BOLETO" }], currentStep: int }`
and `attempts: [{ id, stepIndex, rail, mode, method: "PIX"|"BOLETO", amount, outcome: "PAID"|"SUBMITTED"|"PENDING_APPROVAL"|"ASSISTED"|"FAILED"|"IN_FLIGHT", reason, externalId, at }]`.

`IN_FLIGHT` is a rail call whose answer was lost (a crash, a timeout, a 5xx).
The bill shows as `PROCESSING` and is never sent again: the ladder and the
reconcile cron ask the rail for the payment by its idempotency key, and after
15 minutes without an answer the bill moves to assisted with
`IN_FLIGHT_UNRESOLVED`. Check the bank before paying such a bill by hand.

`method` is how a step pays: `PIX` uses the BR Code (or the Pix key),
`BOLETO` the barcode, tax guides included. A bill with a `pixCode` lists its
Pix steps first. One mode can appear twice (Pix, then barcode, on the same
rail); the app collapses steps per mode for the three-step ladder.

### Receipts and attachments

- `GET /bills/{id}/receipt`:

  ```json
  {
    "data": {
      "billId": string,
      "proof": {
        "rail": string, "amount": Money, "paidAt": timestamp, "payer": string,
        "receiver": string, "transactionId": string | null, "authentication": string | null
      } | null,
      "attachments": [{ "id": string, "fileName": string, "mimeType": string, "bytes": int }]
    }
  }
  ```

  `proof` is present when a rail paid the bill.
- `GET /bills/{id}/receipt/pdf`: a one page PDF receipt (`application/pdf`)
  rendered from the rail proof, or from the bill itself when it was marked
  paid by hand. 422 while the bill is not paid.
- `POST /bills/{id}/attachments`: upload body. Returns the attachment, 201.
- `GET /bills/{id}/attachments/{attachmentId}`: the file itself (raw bytes with
  its `Content-Type` and `Content-Disposition`), not JSON.

## Open Finance

The aggregator's free tier has no connect widget: the user pastes the item id
copied from the aggregator dashboard.

### POST /open-finance/lookup

Body `{ itemId: string }` (a UUID). `data` is one of:

```json
{ "status": "FOUND", "institution": string, "consentUntil": date | null, "accounts": [{ "id": string, "name": string, "balance": Money }] }
{ "status": "NOT_FOUND" }
{ "status": "ALREADY_CONNECTED", "owner": "PF"|"PJ" }
```

Card balances are negative (what is owed).

### POST /open-finance/connections

Body `{ itemId, entity, accountIds: [string] }` (at least one). Imports those
accounts. `data`: `{ connectionId: string, imported: int }`, 201.

### GET /open-finance/connections

`data`: `[{ id, itemId, institution, entityKind, status, lastSyncAt: timestamp | null, accountCount: int }]`.

### POST /open-finance/connections/{id}/sync

Refreshes balances and transactions: a year on the first sync (or `?days=`
when given), then from a week before the last one, since the provider collects
again a few days back; a transaction already stored under its provider id is
not added twice. It then marks paid the open bills of that entity that an
outgoing transaction of the same amount paid, booked from 10 days before to 7
days after the due date (15 for an auto-debit bill). It also refreshes the
item's investment positions, their movements and the day's balance (see
`GET /investments` and its History); a provider that fails to list them leaves
the last ones in place. `data`:
`{ accounts: int, transactions: int, settledBills: int, syncedAt: timestamp }`.

### DELETE /open-finance/connections/{id}

Detaches the connection; its accounts stay, now manual, and its investment
positions are dropped with their movements and snapshots. `data`: `{ id }`.

## Payment rails

A rail id reads `<ENTITY>.<RAIL_ID>.<KIND>`, for example `PJ.INTER_EMPRESAS.TAX_API`.
Rails that share a `RAIL_ID` on an entity share credentials.

`PaymentRail`:

```json
{
  "id": string, "railId": "MERCADO_PAGO_PAYOUTS"|"ASAAS"|"INTER_EMPRESAS"|"C6_EMPRESAS"|"ASSISTED" | null,
  "kind": "PIX_API"|"BOLETO_API"|"TAX_API"|"RESERVE_FUNDING"|"BANK_APPROVAL"|"ASSISTED",
  "owner": "PF"|"PJ", "step": 1|2|3, "institution": string,
  "status": "ACTIVE"|"NEEDS_AUTHORIZATION"|"UNAVAILABLE"|"ALWAYS",
  "configurable": bool
}
```

- `GET /rails?entity=PF|PJ`: `[PaymentRail]` in ladder order. The personal
  entity always lists a `BANK_APPROVAL` rail with status `UNAVAILABLE` and
  `railId: null` (`PF.NONE.BANK_APPROVAL`).
- `POST /rails/{id}/authorize`: enables the rail for the ladder. Needs stored
  credentials first (422 otherwise). Returns `PaymentRail`.
- `GET /rails/{id}/credentials`: `{ certificateName: string | null, certificateValidUntil: date | null, apiKeyHint: string | null, lastTestAt: timestamp | null }`.
  404 when nothing is stored or the rail is not configurable.
- `PUT /rails/{id}/credentials`: body
  `{ certificate?: Upload, privateKey?: Upload, certificateValidUntil?: date, apiKey?: string, clientId?: string, clientSecret?: string }`.
  Each rail takes only its own fields (422 `This rail does not use <field>`
  otherwise): Mercado Pago `apiKey` (access token) and `privateKey` (signing
  key); Asaas `apiKey`; Inter and C6 `clientId`, `clientSecret`,
  `certificate` and `privateKey`, both PEM.
  Secrets are sealed in the server vault and never returned; only the file
  name, expiry and the last four characters of the API key come back. A PEM
  certificate's expiry is read from the file; a `.pfx` needs
  `certificateValidUntil`. Returns the credentials view.
- `POST /rails/{id}/test`: `{ checks: [{ kind: "CERTIFICATE"|"API_KEY"|"SCOPE"|"PAYER_ACCOUNT", passed: bool, millis: int | null }], testedAt: timestamp }`.
- `DELETE /rails/{id}`: deletes the credentials and disables the rail. `data`: `{ id }`.

## Automation

- `GET /automation`: `{ pausedSince: timestamp | null, entities: [{ entity: "PF"|"PJ", confirmAboveCents: int | null, dailyCapCents: { [railId]: int }, entityDailyCapCents: int | null, paymentCapCents: int | null, maxDeviationPercent: int | null, approvalCutoff: "HH:MM" }] }`.
  - `dailyCapCents` caps each rail per entity per Sao Paulo day.
  - `entityDailyCapCents` (default 1000000) caps every automatic payment of
    the entity in a day; `paymentCapCents` (default 500000) caps one automatic
    payment. Both skip bank approval steps, which a person approves anyway.
    `null` means no limit. A capped step fails and the ladder moves down.
  - `maxDeviationPercent` (default 30): a bill whose amount differs from the
    median of the last three paid bills to the same recipient by more than
    this asks for confirmation. `null` turns the check off.
  - `approvalCutoff` (default `16:00`): a bank approval batch still pending at
    this Sao Paulo time on the due date moves to assisted with
    `APPROVAL_EXPIRED`.
- `POST /automation/pause` and `POST /automation/resume`: the kill switch for
  every entity. Same response as `GET /automation`.
- `PATCH /automation/settings`: body `{ entity, confirmAboveCents?: int | null, dailyCapCents?: { [railId]: int }, entityDailyCapCents?: int | null, paymentCapCents?: int | null, maxDeviationPercent?: int (1..1000) | null, approvalCutoff?: "HH:MM" }`.
  An omitted field keeps its value; `null` clears a limit. Same response as
  `GET /automation`.

## Capture sources

`CaptureSources`:

```json
{
  "mailboxes": [{ "id": string, "address": string, "owner": "PF"|"PJ", "lastReadAt": timestamp | null, "billsFound": int, "emailsScanned": int }],
  "dda": [{ "owner": "PF"|"PJ", "bank": string, "lastBatchAt": timestamp | null, "boletos": int, "enabled": bool }]
}
```

- `GET /capture/sources`: `CaptureSources`. `dda` always lists the company
  entry when there is a company.
- `POST /capture/mailboxes/oauth/start`: body `{ entity }`. `data`: `{ url }`,
  the provider consent page (read-only mail scope). Open it in the browser.
- `GET /capture/mailboxes/oauth/callback?code=&state=`: the provider redirects
  here; the server stores the mailbox and redirects to
  `cashdeck://capture?connected=1` (or `?error=<code>`).
- `POST /capture/mailboxes/{id}/read`: reads it now. Returns `CaptureSources`.
  A bill that prints another entity's CPF or CNPJ and not the mailbox
  owner's is filed under that entity, so a company DAS or DARF sent to the
  personal mailbox lands in the company. A password protected PDF is opened
  with the owner's tax id digits (the first 4, 5 or 6, or all of them), and
  an untyped attachment named `.pdf` is read as a PDF.
- `DELETE /capture/mailboxes/{id}`: disconnects. Returns `CaptureSources`.
- `PUT /capture/dda/{entity}`: body `{ enabled: bool }`. Returns `CaptureSources`.
- `POST /capture/files`: body `Upload` plus `entity`, `amountCents?` and
  `dueDate?` (a PDF or photo the user shared). The codes are first read from
  the PDF text layer on the server; the AI reads the payee, the amount, the
  due date and any code only drawn as an image. Codes that do not validate
  are dropped (a mistyped Pix code leaves the barcode bill). The bill is
  captured with `source: "SHARE"` under the same rules as `POST /bills` and
  the file attached to it. Returns `BillView`, 201, or 200 when the same code
  was already captured. 422 `VALIDATION_ERROR` when no code can be read, 422
  `AMOUNT_REQUIRED` when no amount is known: send the same upload again with
  `amountCents`.

The callback is
`/api/v1/capture/mailboxes/oauth/callback`; set it as `GMAIL_REDIRECT_URI` and
as an authorized redirect URI of the Google OAuth client.

## Invoices (NFS-e)

`IssuerSetup`:

```json
{
  "kind": "NATIONAL" | "MUNICIPAL", "city": string,
  "certificateName": string | null, "certificateExpiresOn": date | null,
  "certificateState": "VALID" | "EXPIRING_SOON" | "EXPIRED" | null,
  "municipalRegistration": string,
  "serviceCode": { "code": string, "description": string }
}
```

`certificateState` is `EXPIRING_SOON` within 45 days of expiry.

- `GET /invoices/issuer`: `IssuerSetup | null` (null before the first save).
- `PUT /invoices/issuer`: body `{ kind, city, municipalRegistration, serviceCode: string }`. Returns `IssuerSetup`.
- `PUT /invoices/issuer/certificate`: body `Upload & { password: string, expiresOn: date }`. Returns `IssuerSetup`.
- `GET /invoices/service-codes`: `[{ code, description }]`.
- `POST /invoices/issuer/test`: `{ protocol: string, elapsedMs: int }`, or 502
  `PROVIDER_ERROR` with the issuer's message.
- `GET /invoices?status=&month=&cursor=&limit=`: `[{ id, client: string, amount: Money, status: "DRAFT"|"PROCESSING"|"ISSUED"|"REJECTED"|"CANCELLED", number: string | null, competence: month, issueOn: date, recurring: bool, isExport: bool, pdfUrl: string | null }]`.
- `POST /invoices/{id}/cancel`: body `{ reason: string }` (15 to 255
  characters). A `DRAFT` is cancelled locally; an `ISSUED` invoice is cancelled
  at the issuer and takes the status it reports. Any other status answers 422.
  Writes an `invoice.cancel` audit event. Returns the invoice view.
- `GET /invoices/{id}/pdf`, `GET /invoices/{id}/xml`: the stored document
  (`application/pdf`, `application/xml`). Both are downloaded from the issuer
  when the invoice becomes `ISSUED`; a missing one is fetched on demand. 404
  while the invoice has no document.

Status lifecycle: issuing moves a draft to what the issuer answers (usually
`PROCESSING`). The Notaas webhook and the `/api/cron/invoices` poll call the
issuer for every `PROCESSING` invoice and record `ISSUED` (number, PDF and XML),
`REJECTED` or `CANCELLED`, each change audited as `invoice.status`.

### Recurring invoice templates

`InvoiceTemplate`:

```json
{
  "id": string,
  "client": { "id": string, "name": string, "taxId": string | null, "country": string },
  "description": string, "serviceCode": string,
  "amount": Money, "billing": "FIXED" | "HOURLY", "hours": number | null,
  "cycleAmount": Money, "dayOfMonth": int, "active": bool
}
```

`HOURLY` treats `amount` as the rate per hour and bills the rate times `hours`;
`cycleAmount` is what each draft carries.

- `GET /invoices/templates`: `[InvoiceTemplate]`, by day of month.
- `POST /invoices/templates`: body `{ client: { name, taxId?, country? }, description, serviceCode, amountCents, currency? = "BRL", billing? = "FIXED", hours? = null, dayOfMonth: 1..31, active? = true }`.
  The client is matched by name or created. Returns `InvoiceTemplate`, 201.
- `GET /invoices/templates/{id}`: `InvoiceTemplate`.
- `PATCH /invoices/templates/{id}`: any subset of the create body. 422 when an
  `HOURLY` template has no hours.
- `DELETE /invoices/templates/{id}`: `{ id }`. Drafts already created stay.

Create, update and delete write `invoice-template.*` audit events. The
`/api/cron/invoices` job creates one `DRAFT` per active template and month
once the template's day has come (a day the month lacks means its last day,
and a run after a weekend catches up), audited as `invoice.draft`. The draft
shows in `GET /home/company` under `drafts` with `recurring: true` and is
issued with `POST /home/company/drafts/{id}/approve`; cancelling the draft
keeps the month from being drafted again.

## Payroll (Fator R)

`PayrollMonth`: `{ month: date (first day), proLabore: Money, salaries: Money, fgts: Money }`.

- `GET /payroll`: `{ current: PayrollMonth, history: [PayrollMonth], revenue12: Money, declaredAnnex: 'III' | 'V' | null }`.
  `current` is this month (zeros until saved); `history` the eleven earlier
  months that have entries, most recent first; `revenue12` the company's
  invoiced revenue of the last twelve months, in BRL; `declaredAnnex` the
  annex the accountant reported, or null.
- `PUT /payroll/{YYYY-MM}`: body `{ proLaboreCents, salariesCents, fgtsCents }`.
  Returns the sheet.
- `PUT /payroll/annex`: body `{ annex: 'III' | 'V' | null }`. The declared
  annex picks the ISS rate and the DAS estimate, even over a full year of
  payroll, since the accountant files the DAS; without it a full year computes
  Fator R. Null clears it. Returns the sheet.

## Manual card bill import

For a card without Open Finance, usually in a foreign currency.

`CardStatement`:

```json
{
  "id": string, "entityKind": "PF"|"PJ", "card": string, "issuer": string,
  "closing": date, "due": date, "rate": int, "iofBps": int,
  "paymentCode": string | null,
  "lines": [{ "id": string, "merchant": string, "date": date, "amount": Money, "needsReview": bool }],
  "billId": string | null
}
```

`rate` is BRL per unit of the card currency with four decimals (`54210` is
5.4210); `iofBps` is IOF in basis points.

- `POST /card-statements`: body `Upload & { entity }` (PDF or image). The
  configured AI reads it into a draft. Returns `CardStatement`, 201.
- `GET /card-statements/latest`: the latest draft without a bill, or `null`.
- `GET /card-statements/{id}`: `CardStatement`.
- `POST /card-statements/{id}/bill`: body `{ lineIds: [string], paymentCode?: string, pixKey?: string }`.
  Totals are computed on the server: BRL subtotal of the selected lines at
  `rate`, IOF on top. Needs a payment code (from the statement or the body).
  `data`: `{ billId, foreign: Money, subtotal: Money, iof: Money, total: Money }`, 201.

## Accountant export

- `GET /accountant-export/plan?period=LAST_MONTH|LAST_QUARTER|CUSTOM&from=&to=`
  (`from` and `to` dates only for `CUSTOM`):

  ```json
  {
    "data": {
      "from": date, "to": date,
      "items": [{ "kind": "STATEMENTS"|"INVOICES"|"TAX_GUIDES"|"EXPENSES"|"PAYROLL"|"RECONCILIATION", "count": int, "unit": "ACCOUNTS"|"DOCUMENTS"|"MONTHS", "files": int, "bytes": int, "selectedByDefault": bool }]
    }
  }
  ```

- `POST /accountant-export`: body `{ period, from?, to?, items: [kind], sentTo?: string }`.
  `data`: `{ id, month: date, sentOn: date, to: string | null, downloadPath: string }`, 201.
- `GET /accountant-export/history`: `[{ id, month, sentOn, to, downloadPath }]`, newest first.
- `GET /accountant-export/{id}/download`: the ZIP itself (`application/zip`),
  rebuilt from the stored period and items. Contains one CSV per item.

## Alerts

Alerts land in an inbox and go out as push notifications through FCM. The
server writes `title` and `body` in pt-BR; `data` carries the raw values
(`payee`, `amount`, `dueDate`, and per type `rail`, `reason`, `method`,
`hasPixCode`, `shortfall`, `invoice`, `client`, `card`, `closing`, `source`). A push
carries the same `data` plus `alertId`, `entityId`, `billId` and `invoiceId`
when set, so a tap opens the bill.

| Type | Raised when |
|---|---|
| `BILL_CAPTURED` | a new bill is captured (not a duplicate) |
| `BILL_NEEDS_AMOUNT` | Gmail or DDA found a bill with no amount and skipped it (`AMOUNT_REQUIRED`); no `billId` |
| `BILL_DUE_SOON` | daily cron: an unpaid bill is due tomorrow |
| `PAYMENT_NEEDS_CONFIRMATION` | the ladder stops for a new payee or an amount above the threshold |
| `PAYMENT_PAID` | a rail pays the bill, at once or on reconciliation |
| `PAYMENT_MOVED_DOWN` | a rail failed and the ladder moved to the next step |
| `PAYMENT_ASSISTED` | the bill fell to assisted, from the ladder or from reconciliation (`reason` such as `IN_FLIGHT_UNRESOLVED`, `APPROVAL_EXPIRED` or `RESERVE_FUNDING_FAILED`); `method` is `PIX`, `BARCODE` or `NONE` and `hasPixCode` says whether a Pix copy-and-paste is available |
| `APPROVAL_PENDING` | the payment waits for approval in the bank |
| `LOW_BALANCE` | daily cron: the reserve does not cover tomorrow's automatic payments |
| `INVOICE_ISSUED`, `INVOICE_FAILED` | the issuer answers `ISSUED` or `REJECTED`, on issue, polling or webhook |
| `CARD_BILL_CLOSED` | a card statement is read |

Each alert has a dedupe key, so a retried job or a second cron run on the
same day never repeats it.

- `GET /alerts?unread=true|false&cursor=&limit=`: newest first, cursor
  pagination.

  ```json
  {
    "data": [{ "id": string, "type": AlertType, "entityId": string | null, "billId": string | null, "invoiceId": string | null, "title": string, "body": string, "data": { [key]: string }, "createdAt": datetime, "readAt": datetime | null }],
    "nextCursor": string | null
  }
  ```

- `GET /alerts/unread-count`: `{ unread: int }`.
- `POST /alerts/{id}/read`: the alert, with `readAt` set (kept if it was read before).
- `POST /alerts/read-all`: `{ updated: int }`.
- `GET /alerts/settings`: `{ types: [{ type, muted: bool }] }`, every type.
- `PATCH /alerts/settings`: body `{ muted: { [AlertType]: bool } }`, only the
  types to change. A muted type still lands in the inbox; it only skips the push.
- `POST /devices`: body `{ token, platform: "ANDROID"|"IOS"|"WEB" }`. Registers
  or refreshes the FCM token of this device. `data`: `{ token, platform, createdAt, lastSeenAt }`, 201.
- `DELETE /devices/{token}`: the token percent-encoded. `{ removed: bool }`.
  Tokens FCM reports as unregistered are removed on the next push.

## AI chat

The assistant answers over the tenant's own data with tools. The server fixes
the tenant and the entity scope of each thread; the model can narrow a query
but never widen it. Side effects are never run by the model: it proposes a
pending action and the app confirms it.

`ChatThread`: `{ id, scope: "PF"|"PJ"|"ALL", title: string | null, createdAt: timestamp, updatedAt: timestamp }`.

`ChatMessage`:

```json
{
  "id": string, "threadId": string, "role": "user"|"assistant", "text": string,
  "notice": null | "ROUND_LIMIT" | "TIME_BUDGET" | "EMPTY" | "ERROR",
  "attachments": [{ "id": string, "fileName": string, "mimeType": string, "size": int }],
  "actions": [ChatAction],
  "createdAt": timestamp
}
```

`notice` explains an assistant message with no text: the turn hit the round
limit or the time budget, the model answered nothing twice, or the model call
failed.

`ChatAction`:

```json
{
  "id": string, "threadId": string,
  "tool": "CREATE_BILL_FROM_ATTACHMENT"|"PAY_BILL"|"CREATE_CATEGORY_RULE"|"DRAFT_INVOICE",
  "status": "PENDING"|"CONFIRMED"|"CANCELLED"|"FAILED"|"EXPIRED",
  "entity": "PF"|"PJ" | null, "needsEntity": bool,
  "details": { "payee": string|null, "amount": Money|null, "dueDate": date|null,
               "fileName": string|null, "pattern": string|null,
               "category": string|null, "payer": string|null },
  "result": null | { "billId": string|null, "invoiceId": string|null,
                     "ruleId": string|null, "updated": int|null },
  "error": string | null, "createdAt": timestamp
}
```

A pending action expires after 24 hours.

- `POST /chat/threads`: body `{ scope?: "PF"|"PJ"|"ALL" }` (default `ALL`).
  `data`: `ChatThread`, 201.
- `GET /chat/threads?cursor=&limit=`: page of `ChatThread`, most recent
  activity first.
- `GET /chat/threads/{id}/messages?cursor=&limit=`: page of `ChatMessage`,
  oldest first.
- `POST /chat/threads/{id}/messages`: body
  `{ text?: string, attachments?: [{ fileName, mimeType, base64 }] }`. Text up
  to 4000 characters, up to 3 files (JPEG, PNG, HEIC, WebP, PDF, MP3, M4A, AAC,
  OGG, WAV, WebM audio), 4 MB of base64 in total so the request stays under
  the Vercel body limit; text or a file is required. `data`:
  `{ messages: [ChatMessage] }` with the stored user message and the reply,
  201. 429 `RATE_LIMITED` once the daily quota is used, 409 `CONFLICT` while
  another reply on the same thread is being written, 503 `NOT_CONFIGURED`
  when `CHAT_ENABLED=false`.
- `POST /chat/actions/{id}/confirm`: body `{ entity?: "PF"|"PJ" }`, required
  when `needsEntity` is true (a bill read from a file in an `ALL` thread).
  Runs the existing use case (bill capture, the payment ladder with
  `confirmed: true`, the rule, or the invoice for that income), records an
  audit event with the request actor and returns the `ChatAction` with `result`, or `FAILED` with
  `error`. Confirming a settled action returns it unchanged.
- `POST /chat/actions/{id}/cancel`: a pending action becomes `CANCELLED`.

Tools the model can call: `query_transactions`, `summarize_period`,
`compare_categories`, `list_bills`, `net_worth_snapshot`, `explain_charge`
(read), and `create_bill_from_attachment`, `pay_bill`,
`create_categorization_rule`, `draft_invoice` (propose only). A turn is bounded
by `CHAT_MAX_ROUNDS` model calls and `CHAT_TURN_BUDGET_MS`, and retries once
after an empty answer. User text is normalized, stripped of control and
invisible characters and wrapped in a `<user_message>` block; attachments,
transaction descriptions and tool results are declared data, and phrases that
try to override the instructions are flagged and recorded on the reply.

## Crons

Vercel calls each with `Authorization: Bearer $CRON_SECRET` (see
[deploy.md](deploy.md)). Each returns `{ data: <counts> }`.

| Path | When (UTC) | What |
|---|---|---|
| `/api/cron/open-finance-sync` | daily 15:00 | syncs every connection, after Pluggy's daily collection (around 14:00) |
| `/api/cron/capture` | daily 09:30 | reads mailboxes and DDA |
| `/api/cron/payment-ladder` | weekdays 11:00 | funds the personal reserve transfer for the Asaas bills it is about to pay, then runs the ladder for bills due; answers `{ checked, byStatus, funding: { rounds, fundedCents } }` |
| `/api/cron/alerts` | daily 12:00 | bills due tomorrow and a short reserve; returns `{ dueSoon, lowBalance }` |
| `/api/cron/reconcile-payments` | weekdays 21:00 | asks each rail for the status of submitted Pix and boleto attempts and of in-flight calls; marks the bill `PAID`, or records the failure and moves it to the assisted step; moves unapproved batches past the cutoff to assisted; answers `{ checked, paid, failed, expired, failures }` |
| `/api/cron/invoices` | weekdays 12:00 | drafts the recurring invoices that are due, then refreshes every `PROCESSING` invoice from the issuer |

## Webhooks

`POST /api/webhooks/{provider}` for `asaas`, `inter`, `mercado-pago`, `pluggy`
and `notaas`. They do not take the bearer token: each provider proves the call
with its signature or shared secret (see [providers.md](providers.md#webhooks)),
and a call that fails the check, or arrives while the secret is not configured,
answers 401 `UNAUTHORIZED`. A body that is not JSON answers 400.

An authentic delivery answers 200 at once with
`{ "data": { "received": int, "duplicates": int } }`; the work runs after the
answer. Event ids are stored per provider, so a replay is counted as a
duplicate and does nothing. The body is only a trigger: payment events
reconcile the named payment by asking the rail, Pluggy item events sync that
item, Notaas events refresh that invoice from the issuer. The crons above stay
the backstop for an event that is lost or fails.

Each row of `webhook_events` keeps the event `type`, the `subject_id` it names
(the Pluggy item id, the payment reference or the invoice id) and, once
handled, the `outcome` (`DONE`, `IGNORED`, `UNKNOWN` when nothing matches the
subject, or `FAILED`), the failure `reason` and `processed_at`.
