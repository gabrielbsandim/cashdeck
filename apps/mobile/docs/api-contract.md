# API contract

What the app expects from the Cashdeck API (`apps/api`). The full v1 contract
is `docs/api.md` in the API repository and its OpenAPI document at
`/api/v1/openapi`; when the app and the contract disagree, align the DTOs in
the same change.

## Auth

The server has one static token (`CASHDECK_API_TOKEN`). At sign in the app
sends it once to `POST /api/v1/sessions` with a device name and platform and
keeps only the session token it gets back, with the server URL, in secure
storage. A static token stored by an older version is exchanged the same way
at launch and then deleted. Every request sends `Authorization: Bearer
<session token>`; a 401 anywhere signs the user out. The device name is the
model the phone reports through `device_info_plus` (`Google Pixel 8`,
`iPhone 15 Pro`), else `Android` or `iPhone`; a session keeps the name it was
created with. Ajustes > Segurança lists
the sessions (`GET /api/v1/sessions`) and revokes them
(`DELETE /api/v1/sessions/{id}`); signing out calls
`DELETE /api/v1/sessions/current`.

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
Tapping an alert or a push opens what it is about: `UNUSUAL_PURCHASE` its
`transactionId`, `SUBSCRIPTION_CHANGED` the subscription `key`,
`CARD_BILL_ABOVE_AVERAGE` the card `accountId`, `BANK_SYNC_STALE` the
connections and `INVOICE_NOT_ISSUED` the company settings, `MONTHLY_RECAP` the recap of its
`month` for its `entity` (`PF` or `PJ`, personal when absent); any other type opens
its `billId`. A push names its type in `alertType`; without a target it opens
the inbox. Push
needs the Firebase config files (see `docs/deploy.md` at the repository root);
without them `FirebasePushMessaging.start` returns false and the app runs as is.

## Monthly recap

`/recap/:month?entity=PF|PJ` plays
`GET /api/v1/recaps/{month}?entity=PF|PJ&locale=pt|en` as a story (`PF` when
the query has no entity): tap right to go on, left to go back, swipe down or
the close button to leave. Each page advances by itself after 6.5 seconds while
its bar fills; holding a finger on the screen pauses it, and with reduced
motion nothing advances on its own. A page without its figure is skipped. Análises opens the last closed
month; an open or malformed month fails locally without a call. With amounts
hidden, every `R$` amount in the closing text is masked too.

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
      "rail": "ASAAS | INTER_EMPRESAS | C6_EMPRESAS | ASSISTED",
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
its `balance`, which counts every installment still ahead. Tapping a cash
account renames it with `PATCH /api/v1/accounts/{id}` and `{ name }`, answered
with the account; a bank sync keeps the name. Tapping a card opens its bills
instead, where the app bar renames it.

The card bills screen reads `GET /api/v1/accounts/{id}/bills`: the bills
oldest first and `current`, the open one it starts on. Each bill has a `state`
(`PAST | CLOSED | OPEN | FORECAST`), a `payment` on closed ones
(`PAID | DUE | UNCONFIRMED`), its `range` of booking days, which lists its
charges through `GET /api/v1/transactions`, and on a forecast the
`installments` still to be posted. `logo.imageUrl` may point at a PNG or an
SVG, and the logo widget picks the decoder by the extension.

The investments screen, opened from the balances screen, reads
`GET /api/v1/investments` with the scope's `entity`: the totals, the split by
institution and by kind, and each position with its yield, rate and due date.
It never sums positions itself; totals come from the server in BRL.

## Category review and rules

- `GET /api/v1/categories/review?entity=` returns `{ pending, groups,
  suggestions }`, read for the switcher's scope. A group carries the
  `transactionIds` it settles, `suggestedCategoryId` (preselected), `reasons`
  (`UNCATEGORIZED | LOW_CONFIDENCE | INCONSISTENT`; one the app does not know
  is skipped), `confidence` and `canCreateRule`. The transactions tab badge
  shows `pending` and hides at 0 or on a failure.
- `POST /api/v1/categories/review/groups` takes `{ transactionIds, categoryId,
  createRule }` and returns `{ updated, similarUpdated, rule | null }`; the app
  sends `createRule` only for a group with `canCreateRule`. A skipped group
  stays on the server and returns on the next load.
- `POST .../review/suggestions/accept` and `.../dismiss` take `{ id }`.
- `GET /api/v1/categories/rules` lists the rules; `PATCH /rules/{id}` takes
  `{ pattern?, categoryId? }` with only what changed and returns `{ rule,
  updated }`; `DELETE /rules/{id}` removes one. A blank pattern never leaves
  the app.

## Chat

- `GET /api/v1/chat/threads` and `GET .../threads/{id}/messages` are paged;
  the app reads every page (limit 100), messages oldest first.
- `POST /api/v1/chat/threads` takes `{ scope: PF | PJ | ALL }` and returns 201.
- A new conversation (`/chat/new`) has no thread until its first message;
  the app starts one over the switcher's scope right before sending.
- `POST .../threads/{id}/messages` takes `{ text, attachments?, clientId }`,
  each attachment `{ fileName, mimeType, base64 }`, at most 3 files and 3 MB
  in all, checked in the app first. `clientId` is 32 hex characters made per
  message and sent again on a retry, so the server answers it once. It returns
  201 `{ "data": { "messages": [user, assistant] } }`. 429, 409 and 503 show
  the server message.
- `POST .../threads/{id}/messages/{messageId}/regenerate` takes `{ text? }`
  and answers the user message again, with `text` in place of what it said
  when given; later messages go. Same 201 shape as a send; 409 while a reply
  is being written, 422 for a message that is not the user's.
- Send and regenerate wait up to 90 s for the answer (`receiveTimeout`).
- A message carries `notice` (`ROUND_LIMIT | TIME_BUDGET | EMPTY | ERROR`),
  `attachments` and `actions`. An action is a proposal the user confirms:
  `POST /api/v1/chat/actions/{id}/confirm` with `{ entity }` only when
  `needsEntity`, or `POST .../{id}/cancel`.
- `SEND_PIX` details add `pixKey`, `pixKeyType`
  (`CPF | CNPJ | EMAIL | PHONE | EVP`), `contactHandle` and `newContact`; a
  result adds `contactId`. An unknown or missing value reads as null. With
  `newContact` true the card says the contact will be saved under its handle.
- The server resolves `@handle` mentions; the app only inserts `@handle `.

## Pix contacts

- `GET /api/v1/pix-contacts?search=` returns `{ "data": [PixContactView] }`,
  each `{ id, name, handle, pixKey, pixKeyType, timesPaid, lastPaidAt | null,
  createdAt }`. The screen and the mention panel load the list once and filter
  it locally.
- `POST` takes `{ name, pixKey, pixKeyType?, handle? }` and returns 201;
  `PATCH /{id}` takes the same fields; `DELETE /{id}` returns `{ "data": { id } }`.
  The app sends the key normalized (CPF or CNPJ digits, `+55` phone, lowercase
  email or EVP) and checks a taken key or handle against the list first.
- 409 (key or handle taken) and 422 (invalid key) show the server message.
- A handle matches `^[a-z0-9][a-z0-9._]{1,29}$`.
