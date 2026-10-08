import { createVerify, generateKeyPairSync } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  MercadoPagoPayoutsRail,
  rsaSha256Signer,
} from '@/rails/mercado-pago-rail'
import {
  credentials,
  ENTITY,
  payment,
  TENANT,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const API = 'https://api.mercadopago.com'
const scope = { tenantId: TENANT, entityId: ENTITY }
const pixKey = { kind: 'PIX_KEY' as const, code: 'a@b.co' }

function rail(
  scripted: ScriptedTransport,
  env: Record<string, string> = { MERCADO_PAGO_ENVIRONMENT: 'sandbox' },
) {
  return new MercadoPagoPayoutsRail({
    credentials: credentials({ MERCADO_PAGO_ACCESS_TOKEN: 'token', ...env }),
    transport: scripted.transport,
    signer: () => 'signed',
  })
}

describe('MercadoPagoPayoutsRail', () => {
  it('serves personal pix keys only', async () => {
    const mp = rail(new ScriptedTransport())
    expect(mp.id).toBe('MERCADO_PAGO_PAYOUTS')
    expect(mp.supports('PIX_KEY', 'PF')).toBe(true)
    expect(mp.supports('PIX_QR', 'PF')).toBe(false)
    expect(mp.supports('PIX_KEY', 'PJ')).toBe(false)
    expect(await mp.pay(payment())).toEqual({
      outcome: 'FAILED',
      reason: 'UNSUPPORTED_KIND',
    })
    expect(await mp.pay(payment({ kind: 'PIX_KEY', code: null }))).toEqual({
      outcome: 'FAILED',
      reason: 'UNSUPPORTED_KIND',
    })
  })

  it('creates a sandbox payout with the idempotency key', async () => {
    const scripted = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 202,
      json: { id: 'POP1', status: 'created', transactions: [{ id: 'TOP1' }] },
    })
    const result = await rail(scripted).pay(payment(pixKey))
    expect(result).toEqual({
      outcome: 'SUBMITTED',
      externalId: 'POP1/TOP1',
      reason: null,
    })
    const sent = scripted.last('POST', `${API}/v1/payouts`)
    expect(sent.headers).toMatchObject({
      authorization: 'Bearer token',
      'x-idempotency-key': 'bill-1:0',
      'x-test-token': 'true',
      'x-enforce-signature': 'false',
    })
    expect(JSON.parse(sent.body ?? '')).toEqual({
      external_reference: 'bill10',
      description: 'Energia Exemplo',
      transactions: [
        {
          type: 'pix',
          pix: { type: 'EMAIL', chave: 'a@b.co' },
          amount: { currency: 'BRL', value: 123.45 },
          external_reference: 'bill10',
        },
      ],
    })
  })

  it('signs production payouts and needs the signing key', async () => {
    const scripted = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 202,
      json: { id: 'POP2' },
    })
    const production = rail(scripted, { MERCADO_PAGO_SIGNING_KEY: 'pem' })
    expect((await production.pay(payment(pixKey))).externalId).toBe('POP2/')
    expect(scripted.last('POST', `${API}/v1/payouts`).headers).toMatchObject({
      'x-signature': 'signed',
    })
    const unsigned = rail(new ScriptedTransport(), {})
    await expect(unsigned.pay(payment(pixKey))).rejects.toThrow(
      'is not configured',
    )
  })

  it('signs with RSA-SHA256 by default', async () => {
    const { privateKey, publicKey } = generateKeyPairSync('rsa', {
      modulusLength: 2048,
    })
    const pem = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
    const signature = rsaSha256Signer('{"a":1}', pem)
    const verified = createVerify('RSA-SHA256')
      .update('{"a":1}')
      .verify(publicKey, signature, 'base64')
    expect(verified).toBe(true)
    const scripted = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      json: { id: 'P' },
    })
    const defaults = new MercadoPagoPayoutsRail({
      credentials: credentials({
        MERCADO_PAGO_ACCESS_TOKEN: 't',
        MERCADO_PAGO_SIGNING_KEY: pem,
      }),
      transport: scripted.transport,
    })
    expect((await defaults.pay(payment(pixKey))).outcome).toBe('SUBMITTED')
  })

  it('maps refusals, bad tokens and outages', async () => {
    const refused = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 400,
      json: { message: 'invalid pix key' },
    })
    expect((await rail(refused).pay(payment(pixKey))).reason).toBe(
      'invalid pix key',
    )
    const vague = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 400,
    })
    expect((await rail(vague).pay(payment(pixKey))).reason).toBe(
      'Mercado Pago refused the payout.',
    )
    const auth = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 401,
    })
    expect((await rail(auth).pay(payment(pixKey))).reason).toBe(
      'Mercado Pago rejected the access token.',
    )
    const down = new ScriptedTransport().on('POST', `${API}/v1/payouts`, {
      status: 500,
    })
    await expect(rail(down).pay(payment(pixKey))).rejects.toThrow(
      'answered 500',
    )
  })

  it('reads a payout transaction status', async () => {
    const url = `${API}/v1/payouts/POP1/transactions/TOP1`
    const scripted = new ScriptedTransport().on(
      'GET',
      url,
      {
        json: {
          id: 'TOP1',
          status: 'success',
          status_detail: 'accredited',
          last_update_date: '2026-10-08T12:00:00Z',
        },
      },
      { json: { id: 'TOP1', status: 'in_process' } },
      { json: { id: 'TOP1', status: 'success' } },
      { status: 404, json: { message: 'not found' } },
    )
    const mp = rail(scripted)
    expect(await mp.status('POP1/TOP1', scope)).toEqual({
      outcome: 'PAID',
      externalId: 'POP1/TOP1',
      reason: 'accredited',
      endToEndId: null,
      settledAt: '2026-10-08T12:00:00Z',
    })
    expect(await mp.status('POP1/TOP1', scope)).toMatchObject({
      outcome: 'SUBMITTED',
      settledAt: null,
    })
    expect(await mp.status('POP1/TOP1', scope)).toMatchObject({
      outcome: 'PAID',
      settledAt: null,
    })
    expect(await mp.status('POP1/TOP1', scope)).toMatchObject({
      outcome: 'FAILED',
      reason: 'not found',
    })
    await expect(mp.status('POP1', scope)).rejects.toThrow('does not know')
  })

  it('checks the token against the user endpoint', async () => {
    const ok = new ScriptedTransport().on('GET', `${API}/users/me`, {
      json: { id: 1 },
    })
    expect(await rail(ok).check()).toEqual({ ok: true, message: null })
    const bad = new ScriptedTransport().on('GET', `${API}/users/me`, {
      status: 401,
    })
    expect((await rail(bad).check()).ok).toBe(false)
  })
})
