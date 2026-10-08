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
`paymentCode` when a boleto PDF or e-mail body has both.

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

- BR Code: `POST /v3/pix/qrCodes/decode` first (refuses when `canBePaid` is
  false or `totalValue` is above the bill), then `POST /v3/pix/qrCodes/pay` with
  `qrCode.payload` and `value`. Status: `GET /v3/pix/transactions/{id}`
  (`DONE` is paid, `REFUSED` and `CANCELLED` failed).
- Pix key: `POST /v3/transfers` with `operationType: PIX`, `pixAddressKey`,
  `pixAddressKeyType` and `externalReference` set to the idempotency key.
  Status: `GET /v3/transfers/{id}` with `endToEndIdentifier`.
- Boleto: `POST /v3/bill` with `identificationField`. Status: `GET /v3/bill/{id}`.
- Check: `GET /v3/finance/balance`.
- Docs: https://docs.asaas.com/reference/pay-a-qrcode,
  https://docs.asaas.com/reference/decode-a-qrcode-for-payment,
  https://docs.asaas.com/reference/transfer-to-another-institution-account-or-pix-key,
  https://docs.asaas.com/reference/retrieve-a-single-transfer,
  https://docs.asaas.com/docs/bill.
- **Unconfirmed:** the response fields of `GET /v3/bill/{id}` (`status`,
  `paymentDate`), the `GET /v3/pix/transactions/{id}` path, and
  `/v3/finance/balance` as the check. Asaas documents no idempotency header for
  QR and bill payments; retries rely on the ladder's idempotency store.

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
- Docs: https://developers.c6bank.com.br/yamls/schedule-payments.yaml.
- **Unconfirmed:** the token endpoint, the grant type and whether mTLS is
  required (the spec names only a bearer JWT), and the meaning of each item
  status (`SCHEDULED` is read as approved, `READ_DATA`, `PROCESSED` and
  `PROCESSING` as waiting for approval). No status reports a settled payment,
  so the final PAID comes from the bank statement.

### Gmail (`GmailBillSource`)

| Credential | Use |
|---|---|
| `GMAIL_CLIENT_ID`, `GMAIL_CLIENT_SECRET`, `GMAIL_REFRESH_TOKEN` | OAuth refresh at `https://oauth2.googleapis.com/token`, per entity |

- `GET /gmail/v1/users/me/messages?q=after:<since> {boleto fatura ...}`, then
  `messages/{id}?format=full` and `messages/{id}/attachments/{id}`.
- PDF and image attachments go through `BillExtractor` (an LLM call with a
  response schema asking for the digitable line and the Pix copy and paste
  code). The body text is scanned for both codes with regular expressions.
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
| `NOTAAS_WEBHOOK_SECRET` | secret for `verifyNotaasSignature` |

- `POST /api/v1/emitir` (`tomador`, `servico.codigo`, `valores.total`,
  `valores.aliquotaIss`, `competencia`, `referencia` = idempotency key), answers
  202 with `invoiceId`. `GET /invoices/{id}/status` maps `queued` and
  `processing` to PROCESSING, `issued` to ISSUED (with `numeroNfe`, `pdfUrl`,
  `xmlUrl`), `error` to REJECTED, `cancelled` to CANCELLED.
  `POST /cancelar` with `invoiceId` and `motivo` (15 to 255 characters).
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
  reference municipality.

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
