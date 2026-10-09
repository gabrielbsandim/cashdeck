import { createHmac } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  FakeSecretVault,
  InMemorySecretStore,
  UnauthorizedError,
  type WebhookDelivery,
  type WebhookProvider,
} from '@cashdeck/application'
import { CredentialResolver } from '@/credentials/credential-resolver'
import { credentials, TENANT } from '@/testing/provider-fixtures'
import {
  createWebhookReaders,
  mercadoPagoManifest,
} from '@/webhooks/webhook-readers'
import {
  bodyId,
  field,
  parseObject,
  sameSecret,
  text,
  WEBHOOK_TOKEN_HEADER,
} from '@/webhooks/webhook-support'

const SECRETS = {
  ASAAS_WEBHOOK_TOKEN: 'asaas-token',
  MERCADO_PAGO_WEBHOOK_SECRET: 'mp-secret',
  INTER_WEBHOOK_TOKEN: 'inter-token',
  PLUGGY_WEBHOOK_SECRET: 'pluggy-secret',
  NOTAAS_WEBHOOK_SECRET: 'notaas-secret',
}

function reader(
  provider: WebhookProvider,
  env: Record<string, string> = SECRETS,
) {
  const found = createWebhookReaders({ credentials: credentials(env) }).find(
    candidate => candidate.provider === provider,
  )
  return found as NonNullable<typeof found>
}

function delivery(
  provider: WebhookProvider,
  body: unknown,
  headers: Record<string, string> = {},
  query: Record<string, string> = {},
): WebhookDelivery {
  return {
    provider,
    headers,
    query,
    rawBody: typeof body === 'string' ? body : JSON.stringify(body),
  }
}

const refused = (promise: Promise<unknown>) =>
  expect(promise).rejects.toThrow(UnauthorizedError)

describe('Asaas webhooks', () => {
  const auth = { 'asaas-access-token': 'asaas-token' }

  it('maps transfer and bill events to payments', async () => {
    const asaas = reader('asaas')
    expect(
      await asaas.read(
        TENANT,
        delivery(
          'asaas',
          { id: 'evt_1', event: 'TRANSFER_DONE', transfer: { id: 'tr-1' } },
          auth,
        ),
      ),
    ).toEqual([
      {
        eventId: 'evt_1',
        type: 'TRANSFER_DONE',
        kind: 'PAYMENT',
        rail: 'ASAAS',
        reference: 'tr-1',
      },
    ])
    const bill = await asaas.read(
      TENANT,
      delivery(
        'asaas',
        { event: 'BILL_PAYMENT_DONE', bill: { id: 'b-1' } },
        auth,
      ),
    )
    expect(bill[0]).toMatchObject({ kind: 'PAYMENT', reference: 'b-1' })
    expect(bill[0]?.eventId).toHaveLength(64)
    const other = await asaas.read(TENANT, delivery('asaas', [], auth))
    expect(other[0]).toMatchObject({ kind: 'IGNORED', type: 'UNKNOWN' })
  })

  it('refuses a wrong or missing token and an unconfigured secret', async () => {
    const asaas = reader('asaas')
    await refused(
      asaas.read(TENANT, delivery('asaas', {}, { 'asaas-access-token': 'x' })),
    )
    await refused(asaas.read(TENANT, delivery('asaas', {})))
    await refused(reader('asaas', {}).read(TENANT, delivery('asaas', {}, auth)))
  })

  it('prefers the secret of the entity named in the URL', async () => {
    const secrets = new InMemorySecretStore()
    const vault = new FakeSecretVault()
    const name = 'ASAAS_WEBHOOK_TOKEN@pj'
    await secrets.put(TENANT, name, await vault.seal('company-token', name))
    const resolver = new CredentialResolver({
      env: SECRETS,
      tenantId: TENANT,
      secrets,
      vault,
    })
    const asaas = createWebhookReaders({ credentials: resolver })[0]
    const body = { id: 'e', transfer: { id: 't' } }
    const company = delivery(
      'asaas',
      body,
      { 'asaas-access-token': 'company-token' },
      { entity: 'pj' },
    )
    expect(await asaas?.read(TENANT, company)).toHaveLength(1)
    await refused(asaas!.read(TENANT, { ...company, headers: auth }))
    expect(
      await asaas?.read(TENANT, {
        ...company,
        query: { entity: 'pf' },
        headers: auth,
      }),
    ).toHaveLength(1)
  })
})

describe('Mercado Pago webhooks', () => {
  const sign = (dataId: string, requestId: string, ts: string) =>
    createHmac('sha256', 'mp-secret')
      .update(mercadoPagoManifest(dataId, requestId, ts))
      .digest('hex')

  it('builds the manifest and leaves out absent parts', () => {
    expect(mercadoPagoManifest('ABC123', 'req-1', '1704908010')).toBe(
      'id:abc123;request-id:req-1;ts:1704908010;',
    )
    expect(mercadoPagoManifest('', '', '1704908010')).toBe('ts:1704908010;')
  })

  it('verifies the signature and maps the resource id', async () => {
    const mp = reader('mercado-pago')
    const headers = {
      'x-signature': `ts=1704908010, v1=${sign('PAY-1', 'req-1', '1704908010')}`,
      'x-request-id': 'req-1',
    }
    const events = await mp.read(
      TENANT,
      delivery(
        'mercado-pago',
        { id: 12345, action: 'payout.updated', data: { id: 'PAY-1' } },
        headers,
        { 'data.id': 'PAY-1' },
      ),
    )
    expect(events).toEqual([
      {
        eventId: '12345',
        type: 'payout.updated',
        kind: 'PAYMENT',
        rail: 'MERCADO_PAGO_PAYOUTS',
        reference: 'PAY-1',
      },
    ])
    const bare = await mp.read(
      TENANT,
      delivery('mercado-pago', { type: 'payment' }, headers, {
        'data.id': 'PAY-1',
      }),
    )
    expect(bare[0]).toMatchObject({
      eventId: 'req-1',
      type: 'payment',
      reference: 'PAY-1',
    })
    const unsignedId = {
      'x-signature': `ts=1,v1=${sign('', '', '1')}`,
    }
    const empty = await mp.read(
      TENANT,
      delivery('mercado-pago', {}, unsignedId),
    )
    expect(empty[0]).toMatchObject({ kind: 'IGNORED', type: 'UNKNOWN' })
    expect(empty[0]?.eventId).toHaveLength(64)
  })

  it('refuses a forged or missing signature', async () => {
    const mp = reader('mercado-pago')
    const forged = {
      'x-signature': 'ts=1704908010,v1=deadbeef',
      'x-request-id': 'req-1',
    }
    await refused(mp.read(TENANT, delivery('mercado-pago', {}, forged)))
    await refused(
      mp.read(
        TENANT,
        delivery('mercado-pago', {}, { 'x-signature': 'v1=abc' }),
      ),
    )
    await refused(mp.read(TENANT, delivery('mercado-pago', {})))
  })
})

describe('Inter webhooks', () => {
  it('reads the token from the URL or the header and maps each item', async () => {
    const inter = reader('inter')
    const items = [
      { codigoSolicitacao: 'sol-1', status: 'PAGO' },
      { codigoTransacao: 'tx-1' },
      { status: 'OTHER' },
    ]
    const events = await inter.read(
      TENANT,
      delivery('inter', items, {}, { token: 'inter-token' }),
    )
    expect(events.map(event => [event.kind, event.type])).toEqual([
      ['PAYMENT', 'PAGO'],
      ['PAYMENT', 'UNKNOWN'],
      ['IGNORED', 'OTHER'],
    ])
    expect(events[1]).toMatchObject({
      rail: 'INTER_EMPRESAS',
      reference: 'tx-1',
    })
    expect(events[0]?.eventId).toBe(bodyId(JSON.stringify(items[0])))
    const single = await inter.read(
      TENANT,
      delivery('inter', items[0], { [WEBHOOK_TOKEN_HEADER]: 'inter-token' }),
    )
    expect(single).toHaveLength(1)
    await refused(
      inter.read(TENANT, delivery('inter', items, {}, { token: 'x' })),
    )
  })
})

describe('Pluggy webhooks', () => {
  const auth = { [WEBHOOK_TOKEN_HEADER]: 'pluggy-secret' }

  it('maps item and transaction events to a sync of the item', async () => {
    const pluggy = reader('pluggy')
    expect(
      await pluggy.read(
        TENANT,
        delivery(
          'pluggy',
          { event: 'transactions/created', eventId: 'ev-1', itemId: 'item-1' },
          auth,
        ),
      ),
    ).toEqual([
      {
        eventId: 'ev-1',
        type: 'transactions/created',
        kind: 'OPEN_FINANCE_ITEM',
        itemId: 'item-1',
      },
    ])
    const login = await pluggy.read(
      TENANT,
      delivery(
        'pluggy',
        { event: 'item/login_succeeded', itemId: 'item-1' },
        auth,
      ),
    )
    expect(login[0]).toMatchObject({ kind: 'IGNORED' })
    const bare = await pluggy.read(TENANT, delivery('pluggy', {}, auth))
    expect(bare[0]).toMatchObject({ kind: 'IGNORED', type: 'UNKNOWN' })
    await refused(pluggy.read(TENANT, delivery('pluggy', {})))
  })

  it('reads the token from the URL before the header', async () => {
    const pluggy = reader('pluggy')
    const body = { event: 'item/updated', eventId: 'ev-2', itemId: 'item-2' }
    const fromUrl = await pluggy.read(
      TENANT,
      delivery('pluggy', body, {}, { token: 'pluggy-secret' }),
    )
    expect(fromUrl[0]).toMatchObject({
      kind: 'OPEN_FINANCE_ITEM',
      itemId: 'item-2',
    })
    await refused(
      pluggy.read(TENANT, delivery('pluggy', body, auth, { token: 'wrong' })),
    )
  })
})

describe('Notaas webhooks', () => {
  const signed = (body: string, extra: Record<string, string> = {}) => ({
    'x-notaas-signature': `sha256=${createHmac('sha256', 'notaas-secret').update(body).digest('hex')}`,
    ...extra,
  })

  it('verifies the HMAC and maps the invoice id', async () => {
    const notaas = reader('notaas')
    const body = JSON.stringify({
      event: 'nfse.issued',
      data: { invoiceId: 'inv-1' },
    })
    expect(
      await notaas.read(
        TENANT,
        delivery(
          'notaas',
          body,
          signed(body, { 'x-notaas-delivery': 'dlv-1' }),
        ),
      ),
    ).toEqual([
      {
        eventId: 'dlv-1',
        type: 'nfse.issued',
        kind: 'INVOICE',
        externalId: 'inv-1',
      },
    ])
    const flat = JSON.stringify({ invoiceId: 'inv-2' })
    const events = await notaas.read(
      TENANT,
      delivery('notaas', flat, signed(flat)),
    )
    expect(events[0]).toMatchObject({
      externalId: 'inv-2',
      type: 'UNKNOWN',
      eventId: bodyId(flat),
    })
    const none = JSON.stringify({ event: 'ping' })
    expect(
      (await notaas.read(TENANT, delivery('notaas', none, signed(none))))[0],
    ).toMatchObject({
      kind: 'IGNORED',
    })
    await refused(notaas.read(TENANT, delivery('notaas', body, signed(none))))
    await refused(notaas.read(TENANT, delivery('notaas', body)))
  })
})

describe('webhook support', () => {
  it('compares secrets and reads loose JSON', () => {
    expect(sameSecret('a', 'a')).toBe(true)
    expect(sameSecret('a', 'ab')).toBe(false)
    expect(text(7)).toBe('7')
    expect(text('')).toBeNull()
    expect(text(null)).toBeNull()
    expect(field('x', 'id')).toBeUndefined()
    expect(field({ id: 1 }, 'id')).toBe(1)
    expect(parseObject('null')).toEqual({})
  })
})
