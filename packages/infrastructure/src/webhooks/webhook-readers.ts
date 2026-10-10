import { createHmac } from 'node:crypto'
import {
  UnauthorizedError,
  type WebhookDelivery,
  type WebhookEvent,
  type WebhookProvider,
  type WebhookReader,
} from '@cashdeck/application'
import { type RailId } from '@cashdeck/domain'
import { type Credentials } from '@/credentials/credential-resolver'
import { verifyNotaasSignature } from '@/invoices/notaas-issuer'
import {
  bodyId,
  field,
  parseObject,
  requireSame,
  text,
  WEBHOOK_TOKEN_HEADER,
  webhookSecret,
} from '@/webhooks/webhook-support'

type ReaderDeps = { credentials: Credentials }

function payment(
  eventId: string,
  type: string,
  rail: RailId,
  reference: string | null,
): WebhookEvent {
  if (!reference) {
    return { eventId, type, kind: 'IGNORED' }
  }
  return { eventId, type, kind: 'PAYMENT', rail, reference }
}

// Asaas sends the authToken chosen on the webhook in `asaas-access-token`. A
// QR code payment is reported as a transfer.
const ASAAS_RESOURCES = ['transfer', 'bill', 'pixTransaction'] as const

export class AsaasWebhookReader implements WebhookReader {
  readonly provider: WebhookProvider = 'asaas'

  constructor(private readonly deps: ReaderDeps) {}

  async read(tenantId: string, delivery: WebhookDelivery) {
    const secret = await webhookSecret(
      this.deps.credentials,
      'ASAAS_WEBHOOK_TOKEN',
      tenantId,
      delivery,
    )
    requireSame(delivery.headers['asaas-access-token'], secret)
    const body = parseObject(delivery.rawBody)
    const reference = ASAAS_RESOURCES.map(key =>
      text(field(body[key], 'id')),
    ).find(Boolean)
    return [
      payment(
        text(body.id) ?? bodyId(delivery.rawBody),
        text(body.event) ?? 'UNKNOWN',
        'ASAAS',
        reference ?? null,
      ),
    ]
  }
}

function signatureParts(header: string | undefined): Record<string, string> {
  return Object.fromEntries(
    (header ?? '')
      .split(',')
      .map(part => part.trim().split('='))
      .filter(pair => pair.length === 2),
  )
}

// x-signature is `ts=<ts>,v1=<hex HMAC-SHA256>` of the manifest
// `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`, leaving out absent parts.
export function mercadoPagoManifest(
  dataId: string,
  requestId: string,
  ts: string,
): string {
  const parts: Array<[string, string]> = [
    ['id', dataId.toLowerCase()],
    ['request-id', requestId],
    ['ts', ts],
  ]
  return parts
    .filter(([, value]) => value.length > 0)
    .map(([name, value]) => `${name}:${value};`)
    .join('')
}

export class MercadoPagoWebhookReader implements WebhookReader {
  readonly provider: WebhookProvider = 'mercado-pago'

  constructor(private readonly deps: ReaderDeps) {}

  async read(tenantId: string, delivery: WebhookDelivery) {
    const secret = await webhookSecret(
      this.deps.credentials,
      'MERCADO_PAGO_WEBHOOK_SECRET',
      tenantId,
      delivery,
    )
    const { ts = '', v1 = '' } = signatureParts(delivery.headers['x-signature'])
    const requestId = delivery.headers['x-request-id'] ?? ''
    const dataId = delivery.query['data.id'] ?? ''
    if (!ts) {
      throw new UnauthorizedError('Missing webhook signature.')
    }
    const expected = createHmac('sha256', secret)
      .update(mercadoPagoManifest(dataId, requestId, ts))
      .digest('hex')
    requireSame(v1, expected)
    const body = parseObject(delivery.rawBody)
    return [
      payment(
        text(body.id) ?? (requestId || bodyId(delivery.rawBody)),
        text(body.action) ?? text(body.type) ?? 'UNKNOWN',
        'MERCADO_PAGO_PAYOUTS',
        text(field(body.data, 'id')) ?? (dataId || null),
      ),
    ]
  }
}

// Inter calls back over mTLS with no header of ours, so the shared token rides
// in the registered URL (`?token=`); the header is accepted too.
export class InterWebhookReader implements WebhookReader {
  readonly provider: WebhookProvider = 'inter'

  constructor(private readonly deps: ReaderDeps) {}

  async read(tenantId: string, delivery: WebhookDelivery) {
    const secret = await webhookSecret(
      this.deps.credentials,
      'INTER_WEBHOOK_TOKEN',
      tenantId,
      delivery,
    )
    requireSame(
      delivery.query.token ?? delivery.headers[WEBHOOK_TOKEN_HEADER],
      secret,
    )
    const parsed: unknown = JSON.parse(delivery.rawBody)
    const items: unknown[] = Array.isArray(parsed) ? parsed : [parsed]
    return items.map(item =>
      payment(
        bodyId(JSON.stringify(item)),
        text(field(item, 'status')) ?? 'UNKNOWN',
        'INTER_EMPRESAS',
        text(field(item, 'codigoSolicitacao')) ??
          text(field(item, 'codigoTransacao')),
      ),
    )
  }
}

const PLUGGY_SYNC_EVENTS = new Set([
  'item/updated',
  'transactions/created',
  'transactions/updated',
  'transactions/deleted',
])

// Pluggy signs nothing, and its dashboard form takes only a URL and an event,
// so the token rides in the URL (`?token=`); the header is accepted too.
export class PluggyWebhookReader implements WebhookReader {
  readonly provider: WebhookProvider = 'pluggy'

  constructor(private readonly deps: ReaderDeps) {}

  async read(
    tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WebhookEvent[]> {
    const secret = await webhookSecret(
      this.deps.credentials,
      'PLUGGY_WEBHOOK_SECRET',
      tenantId,
      delivery,
    )
    requireSame(
      delivery.query.token ?? delivery.headers[WEBHOOK_TOKEN_HEADER],
      secret,
    )
    const body = parseObject(delivery.rawBody)
    const eventId = text(body.eventId) ?? bodyId(delivery.rawBody)
    const type = text(body.event) ?? 'UNKNOWN'
    const itemId = text(body.itemId)
    if (!itemId) {
      return [{ eventId, type, kind: 'IGNORED' }]
    }
    if (!PLUGGY_SYNC_EVENTS.has(type)) {
      return [{ eventId, type, kind: 'IGNORED', subject: itemId }]
    }
    return [{ eventId, type, kind: 'OPEN_FINANCE_ITEM', itemId }]
  }
}

export class NotaasWebhookReader implements WebhookReader {
  readonly provider: WebhookProvider = 'notaas'

  constructor(private readonly deps: ReaderDeps) {}

  async read(
    tenantId: string,
    delivery: WebhookDelivery,
  ): Promise<WebhookEvent[]> {
    const secret = await webhookSecret(
      this.deps.credentials,
      'NOTAAS_WEBHOOK_SECRET',
      tenantId,
      delivery,
    )
    const signature = delivery.headers['x-notaas-signature'] ?? null
    if (!verifyNotaasSignature(delivery.rawBody, signature, secret)) {
      throw new UnauthorizedError('Invalid webhook signature.')
    }
    const body = parseObject(delivery.rawBody)
    const eventId =
      delivery.headers['x-notaas-delivery'] ?? bodyId(delivery.rawBody)
    const type = text(body.event) ?? 'UNKNOWN'
    const externalId =
      text(field(body.data, 'invoiceId')) ?? text(body.invoiceId)
    if (!externalId) {
      return [{ eventId, type, kind: 'IGNORED' }]
    }
    return [{ eventId, type, kind: 'INVOICE', externalId }]
  }
}

export function createWebhookReaders(deps: ReaderDeps): WebhookReader[] {
  return [
    new AsaasWebhookReader(deps),
    new MercadoPagoWebhookReader(deps),
    new InterWebhookReader(deps),
    new PluggyWebhookReader(deps),
    new NotaasWebhookReader(deps),
  ]
}
