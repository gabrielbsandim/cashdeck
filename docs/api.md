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
signed `state` instead). If the server has no token configured, every guarded
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
  failed attempt (`NOT_CONFIGURED`, `DAILY_CAP_EXCEEDED`, `RAIL_UNAVAILABLE`,
  `CONFIRMATION_DECLINED`, or the rail's message).

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
  "cdiPercent": int | null, "connectionId": string | null
}
```

`entity` is optional; without it both entities are listed.

### POST /accounts

Manual account (an institution with no Open Finance).
Body: `{ entity, institution: string, name: string, type, currency?: "BRL", isReserve?: bool, balanceCents?: int }`.
Returns the account, 201.

### PATCH /accounts/{id}

Body: `{ name?: string, isReserve?: bool, cdiPercent?: int | null, balanceCents?: int }`
(`balanceCents` only for manual accounts). Returns the account.

## Transactions

### GET /transactions?entity=&accountId=&from=&to=&cursor=&limit=

Newest first. `data`: array of

```json
{
  "id": string, "accountId": string, "entityKind": "PF"|"PJ", "amount": Money,
  "bookedOn": date, "description": string, "categoryId": string | null,
  "kind": "INCOME"|"EXPENSE"|"TRANSFER", "transferId": string | null,
  "invoiceId": string | null
}
```

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
- `GET /bills/{id}`: `BillDetailView` (`BillView` plus `plan` and `attempts`).
- `POST /bills/{id}/pay`: body `{ confirmed?: bool }`. Runs the ladder. Returns
  `BillDetailView` plus `instructions: { kind, copyCode, pixCode, amountCents, dueDate } | null`;
  at the assisted step the app shows `pixCode` first and `copyCode` (the
  barcode) second.
- `POST /bills/{id}/mark-paid`: body `{ attachmentId?: string, proof?: string }`.
  `attachmentId` points at a file already attached; `proof` is free text (an
  end-to-end id, say). Returns `BillView`.

`BillView`:

```json
{
  "id": string, "entityId": string, "entityKind": "PF"|"PJ",
  "kind": "BOLETO"|"PIX_KEY"|"PIX_QR"|"TAX_BARCODE"|"DARF_NO_BARCODE",
  "status": "OPEN"|"NEEDS_CONFIRMATION"|"PROCESSING"|"AWAITING_BANK_APPROVAL"|"ASSISTED"|"PAID"|"CANCELLED",
  "source": "GMAIL"|"SHARE"|"CAMERA"|"CHAT"|"DDA"|"MANUAL",
  "payee": string | null, "amount": Money, "dueDate": date, "code": string | null,
  "pixCode": string | null,
  "createdAt": timestamp, "paidAt": timestamp | null, "paidBy": "RAIL"|"USER" | null
}
```

`BillDetailView` adds
`plan: { steps: [{ mode: "AUTOMATIC"|"BANK_APPROVAL"|"ASSISTED", rail: RailId, method: "PIX"|"BOLETO" }], currentStep: int }`
and `attempts: [{ id, stepIndex, rail, mode, method: "PIX"|"BOLETO", amount, outcome: "PAID"|"SUBMITTED"|"PENDING_APPROVAL"|"ASSISTED"|"FAILED", reason, externalId, at }]`.

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

Refreshes balances and the last 30 days of transactions (since the last sync
when there is one). `data`: `{ accounts: int, transactions: int, syncedAt: timestamp }`.

### DELETE /open-finance/connections/{id}

Detaches the connection; its accounts stay, now manual. `data`: `{ id }`.

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

- `GET /automation`: `{ pausedSince: timestamp | null, entities: [{ entity: "PF"|"PJ", confirmAboveCents: int | null, dailyCapCents: { [railId]: int } }] }`.
- `POST /automation/pause` and `POST /automation/resume`: the kill switch for
  every entity. Same response as `GET /automation`.
- `PATCH /automation/settings`: body `{ entity, confirmAboveCents?: int | null, dailyCapCents?: { [railId]: int } }`.
  Same response as `GET /automation`.

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

## Payroll (Fator R)

`PayrollMonth`: `{ month: date (first day), proLabore: Money, salaries: Money, fgts: Money }`.

- `GET /payroll`: `{ current: PayrollMonth, history: [PayrollMonth], revenue12: Money }`.
  `current` is this month (zeros until saved); `history` the eleven earlier
  months that have entries, most recent first; `revenue12` the company's
  invoiced revenue of the last twelve months, in BRL.
- `PUT /payroll/{YYYY-MM}`: body `{ proLaboreCents, salariesCents, fgtsCents }`.
  Returns the sheet.

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

## Crons

Vercel calls each with `Authorization: Bearer $CRON_SECRET` (see
[deploy.md](deploy.md)). Each returns `{ data: <counts> }`.

| Path | When (UTC) | What |
|---|---|---|
| `/api/cron/open-finance-sync` | daily 09:00 | syncs every connection |
| `/api/cron/capture` | daily 09:30 | reads mailboxes and DDA |
| `/api/cron/payment-ladder` | weekdays 11:00 | runs the ladder for bills due |
| `/api/cron/reconcile-payments` | weekdays 21:00 | asks each rail for the status of submitted Pix and boleto attempts; marks the bill `PAID`, or records the failure and moves it to the assisted step |
