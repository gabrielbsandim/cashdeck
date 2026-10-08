# API contract

What the app expects from the Cashdeck API (`apps/api`). The server's OpenAPI
document is the source of truth; when the two disagree, align this file and the
DTOs in the same change.

## Envelope

- Success: `{ "data": <payload> }`.
- Error: `{ "error": { "code": "...", "message": "...", "details": ... } }`.
  `message` is shown to the user as is for 400, 409 and 422.
- Money is `{ "cents": 12345, "currency": "BRL" }`. Dates without time are
  `YYYY-MM-DD`; moments are ISO 8601 in UTC.

## Bills

The shapes below mirror `packages/client/openapi.json`, generated from the
server schemas with `pnpm -C apps/api openapi:export`.

`GET /api/v1/bills` returns `{ "data": [Bill], "nextCursor": "..." | null }`,
where a list item carries no `plan` or `attempts`. `GET /api/v1/bills/{id}`
returns `{ "data": BillDetail }`.

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
    "steps": [{ "mode": "AUTOMATIC | BANK_APPROVAL | ASSISTED", "rail": "ASAAS" }],
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
- A null `payee` reads as blank, `code` is the payment code.

An unknown enum value is a format error (`UnexpectedFailure`), so a new value
on the server needs the app updated first.
