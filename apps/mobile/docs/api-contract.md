# API contract

What the app expects from the Cashdeck API (`apps/api`). The full v1 contract
is `docs/api.md` in the API repository and its OpenAPI document at
`/api/v1/openapi`; when the app and the contract disagree, align the DTOs in
the same change.

## Auth

The server has one access token (`CASHDECK_API_TOKEN`). The app stores the
server URL and the token in secure storage, sends `Authorization: Bearer
<token>` on every request and checks them with `GET /api/v1/auth/check` at
sign in. A 401 anywhere signs the user out.

## Repositories

Every feature has an `Api*Repository` in its `data/` folder, selected by
`Backend.api`, and a fake selected by `Backend.fake`. Uploads are JSON with a
base64 payload (`core/network/file_transfer.dart`); downloads read the raw
body and the `Content-Disposition` file name.

Where the contract has no route yet, a repository answers
`UnsupportedFailure` instead of guessing. No repository does today.

Certificate uploads (rails and invoice issuer) ask for the expiry date, since
a .pfx does not let the server read it.

The profiles screen lists both entities with `GET /entities` and saves one
with `PATCH /entities/{id}`: `name`, the unmasked `taxId` (checked locally
first) and, for `PJ` only, `taxRegime`.

## Capture

- `POST /api/v1/capture/files` takes the upload body plus `entity` (`PF` or
  `PJ`). A PDF goes as is; a photo above 900 KB is re-encoded as JPEG
  (longest side 2000 px) first. Anything still above 3.3 MB decoded is refused
  before sending, since base64 must fit the 4.5 MB Vercel body. 201 is a new
  bill, 200 a known one (a duplicate, or the other half of a bolepix merged
  into it), 413 too large (Vercel's own limit), 422 `AMOUNT_REQUIRED` asks
  the amount and any other 422 means no code was read. After the sheet the
  same file goes again with `amountCents` and `dueDate`.
- `POST /api/v1/bills` carries what the camera, the share sheet or the paste
  screen read: `entityId` (from `GET /entities`), `source` (`CAMERA`,
  `SHARE` or `MANUAL`), one of `paymentCode`, `pixCode` or `pixKey` (a
  bolepix sends both codes), and the optional `amountCents`, `dueDate` and
  `payee`. 201 is new, 200 a duplicate.
  A 422 with `error.code` `AMOUNT_REQUIRED` (a Pix key or an open QR;
  `details` names the field, kind and payee) opens a sheet that asks the
  amount and the due date, starting at today, and the same body goes again
  with the answer. The server has no `DUE_DATE_REQUIRED`: a Pix without a due
  date is due today.
- Shared text is searched for a Pix copy-and-paste with a valid CRC or a 44,
  47 or 48 digit line, and opens the paste screen with it.

## Downloads

- `GET /api/v1/bills/{id}/receipt/pdf` is the bank proof a paid bill shares.
- `GET /api/v1/transfers/{id}/document` is the transfer's document.

## Envelope

- Success: `{ "data": <payload> }`.
- Error: `{ "error": { "code": "...", "message": "...", "details": ... } }`.
  `message` is shown to the user as is for 400, 409 and 422.
- Money is `{ "cents": 12345, "currency": "BRL" }`. Dates without time are
  `YYYY-MM-DD`; moments are ISO 8601 in UTC.

## Alerts and push

`GET /api/v1/alerts` pages the inbox newest first (`unread=true` filters),
`GET /alerts/unread-count` feeds the bell badge, `POST /alerts/{id}/read` and
`POST /alerts/read-all` mark reads, and `GET`/`PATCH /alerts/settings` mute a
type. An unknown alert type maps to `AlertKind.other`. After sign-in the app
sends its FCM token to `POST /api/v1/devices` with `ANDROID`, `IOS` or `WEB`
and a `locale` of `pt` or `en`, the language the server writes its push in.
The inbox rebuilds each alert text from its type and `data` in the app
language, keeping the server text when a field is missing.
Signing out first calls `DELETE /api/v1/devices/{token}` (percent-encoded),
while the credentials still authenticate it; a failed call never blocks it.
A push carries `billId` in its data; tapping it opens `/bills/{billId}`. Push
needs the Firebase config files (see `docs/deploy.md` at the repository root);
without them `FirebasePushMessaging.start` returns false and the app runs as is.

## Bills

The shapes below mirror `packages/client/openapi.json`, generated from the
server schemas with `pnpm -C apps/api openapi:export`.

`GET /api/v1/bills` returns `{ "data": [Bill], "nextCursor": "..." | null }`,
where a list item carries no `plan` or `attempts`. `GET /api/v1/bills/{id}`
returns `{ "data": BillDetail }`.

The list sorts by `dueDate` and filters one `status` at a time, so the app
walks the statuses with open ones first (`NEEDS_CONFIRMATION`,
`AWAITING_BANK_APPROVAL`, `ASSISTED`, `OPEN`, then `PROCESSING`, `PAID`,
`CANCELLED`) and pages with its own cursor, `<status index>:<server cursor>`.
The list loads more as the user nears its end.

`POST /api/v1/bills/{id}/pay` sends `{ "confirmed": true }` only after the
user accepts the confirmation sheet. The server computes why a payment needs
confirming (`NEW_PAYEE`, `ABOVE_THRESHOLD`, `AMOUNT_DEVIATION`) but only
records it in the audit log, so the sheet shows a generic reason. The app
already reads an optional `confirmationReason` on the bill for when the view
exposes it.

```json
{
  "id": "bill-1",
  "entityId": "personal",
  "entityKind": "PF | PJ",
  "kind": "BOLETO | PIX_KEY | PIX_QR | TAX_BARCODE | DARF_NO_BARCODE",
  "status": "OPEN | NEEDS_CONFIRMATION | PROCESSING | AWAITING_BANK_APPROVAL | ASSISTED | PAID | CANCELLED",
  "source": "GMAIL | SHARE | CAMERA | CHAT | DDA | MANUAL",
  "payee": "Payee Example, or null",
  "amount": { "cents": 12345, "currency": "BRL" },
  "dueDate": "2026-10-08",
  "code": "boleto line or Pix payload, or null",
  "createdAt": "2026-10-08T15:00:00.000Z",
  "paidAt": "ISO 8601 or null",
  "paidBy": "RAIL | USER | null",
  "plan": {
    "steps": [
      { "mode": "AUTOMATIC | BANK_APPROVAL | ASSISTED", "rail": "ASAAS" }
    ],
    "currentStep": 0
  },
  "attempts": [
    {
      "id": "attempt-1",
      "stepIndex": 0,
      "mode": "AUTOMATIC | BANK_APPROVAL | ASSISTED",
      "rail": "MERCADO_PAGO_PAYOUTS | ASAAS | INTER_EMPRESAS | C6_EMPRESAS | ASSISTED",
      "amount": { "cents": 12345, "currency": "BRL" },
      "outcome": "PAID | SUBMITTED | PENDING_APPROVAL | ASSISTED | FAILED",
      "reason": "optional, a machine code such as NOT_CONFIGURED",
      "externalId": "optional",
      "at": "2026-10-08T15:00:00.000Z"
    }
  ]
}
```

`plan` is null until the payment ladder first runs for the bill.

How the app reads it (`lib/features/bills/data/bill_dtos.dart`):

- `entityKind` is the owner; the app filters by it locally.
- `OPEN`, `NEEDS_CONFIRMATION` and `ASSISTED` show as pending, `PROCESSING` as
  scheduled, `AWAITING_BANK_APPROVAL` as awaiting approval.
- Plan steps collapse to one per `mode`, in order. A missing plan is empty.
- Attempt outcomes: `PAID` succeeded, `FAILED` failed, the rest waiting.
  `IN_FLIGHT` (a rail call sent and not yet answered) is waiting, so the bill
  shows as processing.
- A null `payee` reads as blank, `code` is the payment code.

An unknown enum value is a format error (`UnexpectedFailure`), so a new value
on the server needs the app updated first.

## Transactions and categories

`GET /api/v1/transactions` takes `entity`, `accountId`, `categoryId`,
`uncategorized=true`, `search`, `cursor` and `limit` (the app sends 30) and
returns `{ "data": [Transaction], "nextCursor": "..." | null }`. A
`Transaction` carries `categorizedBy` (`RULE | AI | USER | null`) and an
optional `categoryConfidence` from 0 to 1. A `TRANSFER` row with a
`transferId` opens the transfer.

`PATCH /api/v1/transactions/{id}` takes `{ categoryId?, note?, applyToSimilar? }`
and returns `{ "data": { "transaction": Transaction, "similarUpdated": 2 } }`.
A blank note is sent as null. There is no read by id, so the detail screen
uses the row it was opened from or the loaded list.

`GET /api/v1/categories` returns `[{ id, key?, name, icon?, parentId? }]`. A
built-in `key` is shown with its localized label, a custom category by `name`.
Account filters read `id`, `name`, `entityKind` and `institution` from
`GET /api/v1/accounts`.

The balances screen also reads `openBill`: a card shows it as owed instead of
its `balance`, which counts every installment still ahead. Tapping an account
renames it with `PATCH /api/v1/accounts/{id}` and `{ name }`, answered with the
account; a bank sync keeps the name. `logo.imageUrl` may point at a PNG or an
SVG, and the logo widget picks the decoder by the extension.

## Chat

- `GET /api/v1/chat/threads` and `GET .../threads/{id}/messages` are paged;
  the app reads every page (limit 100), messages oldest first.
- `POST /api/v1/chat/threads` takes `{ scope: PF | PJ | ALL }` and returns 201.
- `POST .../threads/{id}/messages` takes `{ text, attachments? }`, each
  attachment `{ fileName, mimeType, base64 }`, at most 3 files and 3 MB in
  all, checked in the app first. It returns `{ "data": { "messages": [...] } }`.
  429, 409 and 503 show the server message.
- A message carries `notice` (`ROUND_LIMIT | TIME_BUDGET | EMPTY | ERROR`),
  `attachments` and `actions`. An action is a proposal the user confirms:
  `POST /api/v1/chat/actions/{id}/confirm` with `{ entity }` only when
  `needsEntity`, or `POST .../{id}/cancel`.
