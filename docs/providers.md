# Provider adapters

Every external system sits behind a port from `packages/application`. The
adapters live in `packages/infrastructure` and are built by
`createProviders({ env, tenantId, secrets, vault, fetch, llm, deviceTokens })`.

## How credentials are found

Each adapter reads its credentials on every call through `CredentialResolver`,
in this order:

1. A sealed secret named `NAME@<entityId>` (for example `ASAAS_API_KEY@pj`).
2. A sealed secret named `NAME` for the whole tenant.
3. The environment variable `NAME`.

Secrets are stored with `SecretStore.put(tenantId, name, sealed)` and sealed
with `SecretVault.seal(value, name)`, so the vault context is the secret name.
A credential uploaded in the app therefore takes effect on the next call,
without a restart. When a required credential is missing the adapter throws
`ProviderNotConfiguredError` (the ladder records `NOT_CONFIGURED` and moves one
step down) and `check()` answers `{ ok: false, message: "<Provider> is not configured." }`.

Certificates and private keys are PEM text in the same store.

## Pix first

Most boletos now print a Pix BR Code too (bolepix). A rail pays by Pix when the
bill is `PIX_QR` or carries the optional `pixCode`; only then does it fall back
to the barcode. Before paying, the payload is parsed locally (`decodePix`): the
CRC must match, and a static code with a printed amount must equal the bill
amount, otherwise the attempt fails with `PIX_AMOUNT_MISMATCH`. A dynamic code
(with a location URL) is sent as the copy and paste string; none of the rails
asks the client to fetch the JWS behind the location, the provider resolves it.

Capture returns both codes: `CapturedBill.pixCode` is set next to
`paymentCode` when a boleto PDF or e-mail body has both. Gmail also pairs the
barcode read from an attached PDF with a Pix code printed in the body.

Codes are found in text without the model wherever there is text: e-mail
bodies and the text layer of PDFs (`PdfTextReader`, `unpdf`, one text item per
line). A BR Code candidate runs from `000201` to any `6304` plus four
characters, since that pattern can also appear inside the payload; every
candidate is checked with the CRC16 and the longest valid one wins. The model
fills only what the text did not give.

### Dynamic Pix codes (`JwsPixLocationResolver`)

A dynamic BR Code carries a location (field 26, sub-field 25) instead of the
amount. At capture the server GETs `https://<location>` (`accept:
application/jose`), with a 5 second timeout, and base64url-decodes the payload
of the compact JWS it answers. It reads `valor.final` (cobv, amount due today)
or `valor.original`, `calendario.dataDeVencimento` (cobv), `chave`,
`recebedor.nome` and `txid`. The JWS signature is **not verified**: the
charge only fills the amount, due date and payee of the bill, and the paying
rail resolves the same location again. Only a public host name is fetched (no
IP literal, port, credentials or single label host); a failure or an
unreadable answer never blocks the capture, which then needs `amountCents`
from the client (`AMOUNT_REQUIRED`). When the charge amount differs from the
barcode amount of a bolepix, the Pix half is dropped.

### Pix code uniqueness

Migration `20261011120000_bill_pix_code_unique` adds a partial unique index
on `(tenant_id, entity_id, pix_code)` for bills that are not cancelled. It
fails when open duplicates already exist; check before deploying with:

```sql
SELECT tenant_id, entity_id, pix_code, count(*) FROM bills
WHERE pix_code IS NOT NULL AND status <> 'CANCELLED'
GROUP BY 1, 2, 3 HAVING count(*) > 1;
```

## Reconciliation

Every rail also implements `RailStatusReader.status(externalId, scope)`
(`packages/application/src/ports/rail-status.ts`), which returns the outcome
plus `endToEndId` and `settledAt` when the provider reports them. The external
id is the one `pay` returned, prefixed by the resource where the provider has
several (`pix:`, `transfer:`, `bill:`, `pagamento:`, `darf:`).

## Adapters

### Pluggy (`PluggyProvider`, OpenFinanceProvider)

| Credential | Use |
|---|---|
| `PLUGGY_CLIENT_ID`, `PLUGGY_CLIENT_SECRET` | `POST /auth` returns an API key sent as `X-API-KEY`, cached for two hours |

- `getItem`: `GET /items/{id}`; `connector.name`, `status`, `lastUpdatedAt`.
- `listAccounts`: `GET /accounts?itemId=` with `page`; a credit card balance is
  returned negative, since it is owed.
- `listTransactions`: `GET /v2/transactions` with `accountId`, `dateFrom`,
  `dateTo`, `pageSize`, following `next` (a URL whose `after` parameter is the
  cursor). The sign comes from `type` (`DEBIT` negative, `CREDIT` positive).
- Docs: https://docs.pluggy.ai/reference/auth-create,
  https://docs.pluggy.ai/reference/items-retrieve,
  https://docs.pluggy.ai/reference/accounts-list,
  https://docs.pluggy.ai/docs/item-lifecycle,
  https://unpkg.com/pluggy-sdk@0.90.0/README.md (cursor pagination).
- **Unconfirmed:** the `/v2/transactions` parameter names `dateFrom`, `dateTo`
  and `pageSize` (taken from the SDK README, not the reference); the `page`
  parameter on `/accounts`; the unit of `balance` (assumed reais).

### Asaas (`AsaasRail`, PF and PJ)

| Credential | Use |
|---|---|
| `ASAAS_API_KEY` | `access_token` header |
| `ASAAS_ENVIRONMENT` | `sandbox` or `production` (default) |
| `ASAAS_PIX_KEY` | Pix key of this Asaas account, the destination of the reserve funding payout (per entity: `ASAAS_PIX_KEY@<entityId>`) |

- BR Code: `POST /v3/pix/qrCodes/decode` first (refuses when `canBePaid` is
  false or `totalValue` is above the bill), then `POST /v3/pix/qrCodes/pay` with
  `qrCode.payload`, `value` and `externalReference` set to the idempotency
  key. Status: `GET /v3/pix/transactions/{id}`
  (`DONE` is paid, `REFUSED` and `CANCELLED` failed).
- Pix key: `POST /v3/transfers` with `operationType: PIX`, `pixAddressKey`,
  `pixAddressKeyType` and `externalReference` set to the idempotency key.
  Status: `GET /v3/transfers/{id}` with `endToEndIdentifier`.
- Boleto: `POST /v3/bill` with `identificationField` and `externalReference`
  set to the idempotency key. Status: `GET /v3/bill/{id}`.
- Every payment call also sends the idempotency key as an `Idempotency-Key`
  header.
- Lost answers: `findByReference` lists `GET /v3/pix/transactions`,
  `GET /v3/transfers` (Pix) or `GET /v3/bill` (barcode) with
  `?externalReference=<key>` and keeps only an item whose `externalReference`
  equals the key, so an ignored filter cannot match a different payment.
- Check and balance: `GET /v3/finance/balance` (`balance` in reais).
- Docs: https://docs.asaas.com/reference/pay-a-qrcode,
  https://docs.asaas.com/reference/decode-a-qrcode-for-payment,
  https://docs.asaas.com/reference/transfer-to-another-institution-account-or-pix-key,
  https://docs.asaas.com/reference/retrieve-a-single-transfer,
  https://docs.asaas.com/docs/bill.
- **Unconfirmed:** the response fields of `GET /v3/bill/{id}` (`status`,
  `paymentDate`), the `GET /v3/pix/transactions/{id}` path, and
  `/v3/finance/balance` as the check. Asaas documents no idempotency header for
  QR and bill payments, nor `externalReference` on `/pix/qrCodes/pay` and
  `/bill`, nor the `externalReference` filter on the three list endpoints. If
  Asaas ignores them, a lost answer is never resolved by the rail: the ladder
  still never resends it (it writes an `IN_FLIGHT` attempt before the call) and
  the bill falls to assisted with `IN_FLIGHT_UNRESOLVED`.

### Mercado Pago Payouts (`MercadoPagoPayoutsRail`, PF)

| Credential | Use |
|---|---|
| `MERCADO_PAGO_ACCESS_TOKEN` | `Authorization: Bearer` |
| `MERCADO_PAGO_SIGNING_KEY` | PEM private key for `X-signature`, required in production |
| `MERCADO_PAGO_ENVIRONMENT` | `sandbox` sends `X-test-token: true` and `X-enforce-signature: false` |

- `POST /v1/payouts` with `X-Idempotency-Key`, one `transactions[]` item of
  `type: pix` with `pix.type` and `pix.chave`. Status:
  `GET /v1/payouts/{payout}/transactions/{transaction}` (`success` is paid,
  `error` and `canceled` failed).
- **Pix BR Code is not supported.** Payouts accept a Pix key or bank account
  data only, so this rail serves `PIX_KEY` bills; a bolepix for the personal
  entity is paid by Asaas from the reserve-funded account, or falls to assisted.

### Reserve funding (`PixReserveFunder`, PF)

Implements the `ReserveFunder` port by composing the two rails above: it reads
the Asaas balance (`AsaasRail.balanceCents`) and sends the shortfall from the
Mercado Pago reserve with `MercadoPagoPayoutsRail.payout` to the Pix key in
`ASAAS_PIX_KEY`, with the round's idempotency key
(`reserve:<entityId>:<day>:<round>`) as `X-Idempotency-Key`. A round left in
flight by a crash is resent with the same key, so it relies on Mercado Pago
answering a repeated key with the first payout (**unconfirmed** for payouts).
Without `ASAAS_PIX_KEY` the funder reports not configured, the round fails and
the Asaas bills fall to assisted with `RESERVE_FUNDING_FAILED`, unless the
Asaas balance already covers them.
- Docs: https://www.mercadopago.com.br/developers/en/docs/money-out/integration-configuration.
- **Unconfirmed:** the `X-signature` algorithm (implemented as the base64
  RSA-SHA256 signature of the body; injectable through `signer`), the Pix key
  type names beyond `CPF`, the format limits of `external_reference`, and an
  end-to-end id field on the transaction status.

### Inter Empresas (`InterEmpresasRail`, PJ)

| Credential | Use |
|---|---|
| `INTER_CLIENT_ID`, `INTER_CLIENT_SECRET` | OAuth client credentials at `/oauth/v2/token` |
| `INTER_CERT`, `INTER_KEY` | mTLS client certificate and key (PEM) |
| `INTER_ACCOUNT` | optional `x-conta-corrente` |
| `INTER_ENVIRONMENT` | `sandbox` or `production` (default) |

- BR Code: `POST /banking/v2/pix` with `destinatario.tipo: PIX_COPIA_E_COLA`
  and `x-id-idempotente`. `tipoRetorno` `APROVACAO` means the account requires
  approval in the bank. Status: `GET /banking/v2/pix/{codigoSolicitacao}`
  (`transacaoPix.status` `PAGO`, `endToEnd`).
- Pix key: same endpoint with `destinatario.tipo: CHAVE`.
- Boleto, DAS and DARF with barcode: `POST /banking/v2/pagamento` with
  `codBarraLinhaDigitavel`, `valorPagar`, `dataVencimento`. Status:
  `GET /banking/v2/pagamento?codigoTransacao=`.
- DARF without barcode: `POST /banking/v2/pagamento/darf`; the guide fields
  (`cnpjCpf`, `codigoReceita`, `periodoApuracao`, `referencia`, `nomeEmpresa`)
  come from the injected `darfDetails(bill)`. Status:
  `GET /banking/v2/pagamento/darf?codigoSolicitacao=`.
- Check: `GET /banking/v2/saldo`.
- Docs: https://developers.inter.co/references/banking,
  https://developers.inter.co/references/token. Request and response shapes
  were taken from the types generated from Inter's `banking.json` spec in
  https://github.com/unfoldingcx/inter.js.
- **Unconfirmed:** the error body shape (`title`, `detail`, `violacoes[].razao`)
  and whether `x-id-idempotente` is honoured on boleto and DARF payments.

### C6 Empresas (`C6EmpresasRail`, PJ step 2, and `C6DdaBillSource`)

| Credential | Use |
|---|---|
| `C6_CLIENT_ID`, `C6_CLIENT_SECRET`, `C6_CERT`, `C6_KEY` | OAuth client credentials over mTLS |
| `C6_TOKEN_URL` | token endpoint, default `<host>/v1/auth/` |
| `C6_UPLOADER_NAME` | `uploader_name` on submit, default `Cashdeck` |
| `C6_ENVIRONMENT` | `sandbox` or `production` (default) |

- `POST /v1/schedule_payments/decode` with one item (`content` is the BR Code,
  the Pix key or the barcode), `GET /{group_id}/items` to catch decode errors,
  then `POST /submit`. The outcome is `PENDING_APPROVAL` until someone approves
  the batch in C6 web banking. Tax guides are never sent.
- DDA: `GET /v1/schedule_payments/query` lists open bills for the company.
  `content` is the barcode; the Pix code of a bolepix is read from the first
  of `pix_qr_code`, `pix_copy_paste`, `pix_code`, `qr_code` or `emv` that
  holds a valid BR Code.
- Docs: https://developers.c6bank.com.br/yamls/schedule-payments.yaml.
- **Unconfirmed:** the token endpoint, the grant type and whether mTLS is
  required (the spec names only a bearer JWT), and the meaning of each item
  status (`SCHEDULED` is read as approved, `READ_DATA`, `PROCESSED` and
  `PROCESSING` as waiting for approval). No status reports a settled payment,
  so the final PAID comes from the bank statement. Whether the DDA query
  returns the Pix code of a bolepix at all, and under which field name, is
  also unconfirmed: the spec could not be read (it sits behind a bot check).

### Gmail (`GmailBillSource`)

| Credential | Use |
|---|---|
| `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN` | OAuth refresh at `https://oauth2.googleapis.com/token`, per entity |

- `GET /gmail/v1/users/me/messages?q=after:<since> {boleto fatura ...}`, then
  `messages/{id}?format=full` and `messages/{id}/attachments/{id}`.
- PDF and image attachments go through `BillExtractor`: the PDF text layer is
  scanned for both codes first, then an LLM call with a response schema asks
  for the digitable line, the Pix copy and paste code, payee, amount and due
  date. The body text is scanned for both codes with regular expressions and
  completes the first attachment bill it does not contradict.
  Every code is validated with the domain decoders (check digits, BR Code CRC)
  and dropped when it does not validate.
- Docs: https://developers.google.com/gmail/api/reference/rest/v1/users.messages/list,
  https://developers.google.com/identity/protocols/oauth2/web-server#offline.

### Notaas (`NotaasIssuer`, InvoiceIssuer)

| Credential | Use |
|---|---|
| `NOTAAS_API_KEY` | `x-api-key` header |
| `NOTAAS_ALIQUOTA_ISS` | ISS rate for domestic invoices (required for them) |
| `NOTAAS_LOCAL_PRESTACAO` | optional IBGE code of the place of service |
| `NOTAAS_EXPORT_COUNTRY` | ISO2 country of export clients, default `US` |
| `NOTAAS_WEBHOOK_SECRET` | HMAC secret of the webhook (see [Webhooks](#webhooks)) |

- `POST /api/v1/emitir` (`tomador`, `servico.codigo`, `valores.total`,
  `valores.aliquotaIss`, `competencia`, `referencia` = idempotency key), answers
  202 with `invoiceId`. `GET /invoices/{id}/status` maps `queued` and
  `processing` to PROCESSING, `issued` to ISSUED (with `numeroNfe`, `pdfUrl`,
  `xmlUrl`), `error` to REJECTED, `cancelled` to CANCELLED.
  `POST /cancelar` with `invoiceId` and `motivo` (15 to 255 characters).
- `download(url)` fetches the PDF and XML URLs from the status answer; the
  `x-api-key` header is sent only when the URL is on the Notaas origin.
- Exports: `valores.exportacao.codigoMoeda` (BACEN code: USD 220, EUR 978) and
  `valorServicoMoeda`; `valores.total` is the BRL amount from
  `InvoiceDraft.brlAmountCents`.
- Webhook: `X-Notaas-Signature: sha256=<hex HMAC-SHA256 of the raw body>`;
  dedupe deliveries by `X-Notaas-Delivery`.
- Check: `GET /api/v1/webhooks/endpoints`.
- Docs: https://docs.notaas.com.br/docs/endpoints,
  https://docs.notaas.com.br/docs/webhooks.
- **Unconfirmed:** whether `referencia` deduplicates a retried emission; the
  required export fields `modoPrestacao` and `vinculoPartes`; coverage of the
  reference municipality; whether the document URLs need the API key or are
  public links.

### Firebase Cloud Messaging (`FcmNotifier`, Notifier)

| Credential | Use |
|---|---|
| `FCM_SERVICE_ACCOUNT_JSON` | service account JSON (`project_id`, `client_email`, `private_key`) |

- An RS256 JWT is exchanged at `https://oauth2.googleapis.com/token` for a token
  with the `firebase.messaging` scope, then
  `POST /v1/projects/{project}/messages:send` once per device token. Device
  tokens come from the injected `deviceTokens(tenantId)`; a token answered with
  404 or `UNREGISTERED` is passed to `onInvalidToken` for removal.
- Docs: https://firebase.google.com/docs/cloud-messaging/send/v1-api,
  https://developers.google.com/identity/protocols/oauth2/service-account.

## Webhooks

`POST https://<api domain>/api/webhooks/<provider>`. The routes skip the bearer
token and authenticate each call with the provider's own proof, compared in
constant time. A failed check, or a secret that is not configured, answers 401.
Event ids go into `webhook_events` (unique per tenant, provider and event id),
so a replay answers 200 and does nothing. The reader in
`packages/infrastructure/src/webhooks` only turns the body into a signal; the
work re-reads the provider API (rail status, Pluggy item, Notaas invoice), so
an authentic body can trigger a refresh but never settle a payment by itself.
The crons stay the backstop.

### Secrets

Each secret goes through `CredentialResolver` like any other credential. The
payloads carry no entity hint, so the default is one secret per provider for
the tenant (`NAME`, sealed in the app or in the environment). When the
personal and company entities use separate provider accounts, register each
URL with `?entity=<entityId>` and store `NAME@<entityId>`: the entity named in
the URL picks its own secret first and falls back to `NAME`. The query only
selects which secret to check against, so it grants nothing by itself.

| Provider | URL to register | Secret | Proof |
|---|---|---|---|
| Asaas | `/api/webhooks/asaas` | `ASAAS_WEBHOOK_TOKEN` | the `authToken` set on the webhook, sent back in `asaas-access-token` |
| Mercado Pago | `/api/webhooks/mercado-pago` | `MERCADO_PAGO_WEBHOOK_SECRET` | `x-signature: ts=<ts>,v1=<hex>`, HMAC-SHA256 of `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` |
| Inter Empresas | `/api/webhooks/inter?token=<secret>` | `INTER_WEBHOOK_TOKEN` | the token in the registered URL (or the `x-cashdeck-webhook-token` header) |
| Pluggy | `/api/webhooks/pluggy?token=<secret>` (event `all`) | `PLUGGY_WEBHOOK_SECRET` | the token in the registered URL (or the `x-cashdeck-webhook-token` header); the dashboard form has no header field |
| Notaas | `/api/webhooks/notaas` | `NOTAAS_WEBHOOK_SECRET` | `X-Notaas-Signature: sha256=<hex HMAC of the raw body>` |

### What each event does

- **Asaas:** the event `id` is the event id (a SHA-256 of the body when
  absent). A body with `transfer.id`, `bill.id` or `pixTransaction.id`
  reconciles the `ASAAS` attempt whose external id ends in that id
  (`transfer:<id>`, `bill:<id>`, `pix:<id>`); anything else is ignored. Asaas
  pauses the queue after 15 consecutive failed deliveries, which is why the
  route answers before the work. Docs:
  https://docs.asaas.com/docs/receba-eventos-do-asaas-no-seu-endpoint-de-webhook.
- **Mercado Pago:** `data.id` (query or body) is matched against the payout id
  of the stored `payout/transaction` pair. The event id is the body `id`, then
  `x-request-id`. Docs:
  https://www.mercadopago.com.br/developers/en/docs/your-integrations/notifications/webhooks.
- **Inter Empresas:** the body is an array (or one object) of payment items;
  `codigoSolicitacao` or `codigoTransacao` reconciles the `INTER_EMPRESAS`
  attempt (`pix:`, `pagamento:`, `darf:`). Each item's event id is the SHA-256
  of the item, so a new status of the same payment is processed again.
- **Pluggy:** `item/updated`, `transactions/created`, `transactions/updated`
  and `transactions/deleted` sync the connection with that `itemId`; other
  events are stored and ignored. The event id is `eventId`. Docs:
  https://docs.pluggy.ai/docs/webhooks.
- **Notaas:** `data.invoiceId` (or `invoiceId`) refreshes that invoice with
  `GET /invoices/{id}/status` and stores the PDF and XML once issued. The event
  id is `X-Notaas-Delivery`.

### Unconfirmed

- Asaas: that a Pix QR code payment is reported through transfer events, and
  the name of the bill payment object (`bill`).
- Mercado Pago: the manifest template and `ts` units come from the published
  algorithm, not checked against a live delivery; which topic money-out
  (payouts) notifications use; whether `data.id` is the payout id.
- Inter: the payload fields. Registration was confirmed live:
  `PUT /banking/v2/webhooks/{tipoWebhook}` for `pix-pagamento` and
  `boleto-pagamento` answers 204 under the `webhook-banking.write` scope, and
  `GET` returns the URL with its query string intact. Inter calls over
  mTLS presenting its own certificate, which a Vercel function cannot verify,
  so the URL token is the only proof.
- Pluggy: signs nothing; the documented alternative is allowlisting its source
  IP, which the route does not do.
- Notaas: the event names and the `data.invoiceId` field.
