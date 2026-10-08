import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { AsaasRail, ASAAS_URLS } from '@/rails/asaas-rail'
import {
  credentials,
  DYNAMIC_PIX,
  ENTITY,
  payment,
  STATIC_PIX,
  TENANT,
} from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const API = ASAAS_URLS.production
const scope = { tenantId: TENANT, entityId: ENTITY }

function rail(scripted: ScriptedTransport, env: Record<string, string> = {}) {
  return new AsaasRail({
    credentials: credentials({ ASAAS_API_KEY: 'key', ...env }),
    transport: scripted.transport,
  })
}

describe('AsaasRail', () => {
  it('covers boleto and pix for both entity kinds', () => {
    const asaas = rail(new ScriptedTransport())
    expect(asaas.id).toBe('ASAAS')
    expect(asaas.supports('PIX_QR', 'PF')).toBe(true)
    expect(asaas.supports('BOLETO', 'PJ')).toBe(true)
    expect(asaas.supports('TAX_BARCODE', 'PJ')).toBe(false)
  })

  it('decodes a bolepix code and pays it by QR before the boleto', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', `${API}/pix/qrCodes/decode`, {
        json: {
          type: 'DYNAMIC',
          value: 123.45,
          totalValue: 123.45,
          canBePaid: true,
        },
      })
      .on('POST', `${API}/pix/qrCodes/pay`, {
        json: { id: 'pix-1', status: 'AWAITING_REQUEST', refusalReason: null },
      })
    const result = await rail(scripted).pay(payment({ pixCode: DYNAMIC_PIX }))
    expect(result).toEqual({
      outcome: 'SUBMITTED',
      externalId: 'pix:pix-1',
      reason: null,
    })
    expect(scripted.body('POST', `${API}/pix/qrCodes/decode`)).toEqual({
      payload: DYNAMIC_PIX,
      expectedPaymentDate: '2026-10-08',
    })
    expect(scripted.body('POST', `${API}/pix/qrCodes/pay`)).toEqual({
      qrCode: { payload: DYNAMIC_PIX },
      value: 123.45,
      description: 'Energia Exemplo',
    })
    expect(
      scripted.last('POST', `${API}/pix/qrCodes/pay`).headers,
    ).toMatchObject({
      access_token: 'key',
    })
  })

  it('pays the bill amount when the code is open and reports instant success', async () => {
    const scripted = new ScriptedTransport()
      .on('POST', `${API}/pix/qrCodes/decode`, {
        json: { value: 0, canBePaid: true },
      })
      .on('POST', `${API}/pix/qrCodes/pay`, {
        json: { id: 'pix-2', status: 'DONE' },
      })
    const result = await rail(scripted).pay(
      payment({ kind: 'PIX_QR', code: STATIC_PIX }),
    )
    expect(result.outcome).toBe('PAID')
    expect(scripted.body('POST', `${API}/pix/qrCodes/pay`)).toMatchObject({
      value: 123.45,
    })
  })

  it('refuses a pix code it cannot pay or that costs more than the bill', async () => {
    const mismatch = await rail(new ScriptedTransport()).pay(
      payment({ pixCode: STATIC_PIX, amount: Money.of(100) }),
    )
    expect(mismatch).toEqual({
      outcome: 'FAILED',
      reason: 'PIX_AMOUNT_MISMATCH',
    })
    const blocked = new ScriptedTransport().on(
      'POST',
      `${API}/pix/qrCodes/decode`,
      {
        json: { canBePaid: false, cannotBePaidReason: 'Expired' },
      },
    )
    expect(await rail(blocked).pay(payment({ pixCode: DYNAMIC_PIX }))).toEqual({
      outcome: 'FAILED',
      reason: 'Expired',
    })
    const silent = new ScriptedTransport().on(
      'POST',
      `${API}/pix/qrCodes/decode`,
      {
        json: { canBePaid: false },
      },
    )
    expect(
      (await rail(silent).pay(payment({ pixCode: DYNAMIC_PIX }))).reason,
    ).toBe('PIX_CANNOT_BE_PAID')
    const fined = new ScriptedTransport().on(
      'POST',
      `${API}/pix/qrCodes/decode`,
      {
        json: { canBePaid: true, totalValue: 130 },
      },
    )
    expect(
      (await rail(fined).pay(payment({ pixCode: DYNAMIC_PIX }))).reason,
    ).toBe('PIX_AMOUNT_ABOVE_BILL')
    const refused = new ScriptedTransport().on(
      'POST',
      `${API}/pix/qrCodes/decode`,
      {
        status: 400,
        json: { errors: [{ code: 'invalid', description: 'QR inválido' }] },
      },
    )
    expect(
      (await rail(refused).pay(payment({ pixCode: DYNAMIC_PIX }))).reason,
    ).toBe('QR inválido')
  })

  it('transfers to a pix key with the idempotency key as reference', async () => {
    const scripted = new ScriptedTransport().on('POST', `${API}/transfers`, {
      json: { id: 'tr-1', status: 'PENDING' },
    })
    const result = await rail(scripted).pay(
      payment({ kind: 'PIX_KEY', code: '529.982.247-25' }),
    )
    expect(result).toEqual({
      outcome: 'SUBMITTED',
      externalId: 'transfer:tr-1',
      reason: null,
    })
    expect(scripted.body('POST', `${API}/transfers`)).toEqual({
      value: 123.45,
      operationType: 'PIX',
      pixAddressKey: '52998224725',
      pixAddressKeyType: 'CPF',
      description: 'Energia Exemplo',
      externalReference: 'bill-1:0',
    })
  })

  it('pays a boleto by its digitable line in the sandbox', async () => {
    const sandbox = ASAAS_URLS.sandbox
    const scripted = new ScriptedTransport().on('POST', `${sandbox}/bill`, {
      json: { id: 'b-1', status: 'PENDING' },
    })
    const result = await rail(scripted, { ASAAS_ENVIRONMENT: 'sandbox' }).pay(
      payment(),
    )
    expect(result.externalId).toBe('bill:b-1')
    expect(scripted.body('POST', `${sandbox}/bill`)).toMatchObject({
      identificationField: '00190000090280001234256789012178916050000012345',
    })
  })

  it('maps credential and server errors', async () => {
    const auth = new ScriptedTransport().on('POST', `${API}/bill`, {
      status: 401,
    })
    expect((await rail(auth).pay(payment())).reason).toBe(
      'Asaas rejected the API key.',
    )
    const vague = new ScriptedTransport().on('POST', `${API}/bill`, {
      status: 422,
      text: 'x',
    })
    expect((await rail(vague).pay(payment())).reason).toBe(
      'Asaas refused the payment.',
    )
    const empty = new ScriptedTransport().on('POST', `${API}/bill`, {
      status: 400,
      json: {},
    })
    expect((await rail(empty).pay(payment())).reason).toBe(
      'Asaas refused the payment.',
    )
    const down = new ScriptedTransport().on('POST', `${API}/bill`, {
      status: 503,
    })
    await expect(rail(down).pay(payment())).rejects.toThrow(
      'Asaas answered 503',
    )
    const unconfigured = new AsaasRail({
      credentials: credentials({}),
      transport: new ScriptedTransport().transport,
    })
    await expect(unconfigured.pay(payment())).rejects.toThrow(
      'Asaas is not configured.',
    )
  })

  it('reads the final status of each payment kind', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${API}/pix/transactions/p1`, {
        json: {
          id: 'p1',
          status: 'DONE',
          endToEndIdentifier: 'E1',
          effectiveDate: '2026-10-08',
        },
      })
      .on('GET', `${API}/transfers/t1`, {
        json: { id: 't1', status: 'FAILED', failReason: 'Key not found' },
      })
      .on('GET', `${API}/bill/b1`, {
        json: { id: 'b1', status: 'PAID', paymentDate: '2026-10-08' },
      })
      .on('GET', `${API}/bill/b2`, {
        json: { id: 'b2', status: 'BANK_PROCESSING' },
      })
      .on('GET', `${API}/bill/b3`, { status: 404, json: {} })
    const asaas = rail(scripted)
    expect(await asaas.status('pix:p1', scope)).toEqual({
      outcome: 'PAID',
      externalId: 'pix:p1',
      reason: null,
      endToEndId: 'E1',
      settledAt: '2026-10-08',
    })
    expect(await asaas.status('transfer:t1', scope)).toMatchObject({
      outcome: 'FAILED',
      reason: 'Key not found',
      settledAt: null,
    })
    expect(await asaas.status('bill:b1', scope)).toMatchObject({
      settledAt: '2026-10-08',
    })
    expect((await asaas.status('bill:b2', scope)).outcome).toBe('SUBMITTED')
    expect((await asaas.status('bill:b3', scope)).outcome).toBe('FAILED')
    await expect(asaas.status('nope', scope)).rejects.toThrow('does not know')
    await expect(asaas.status('card:1', scope)).rejects.toThrow('does not know')
  })

  it('checks the account balance', async () => {
    const ok = new ScriptedTransport().on('GET', `${API}/finance/balance`, {
      json: { balance: 1 },
    })
    expect(await rail(ok).check()).toEqual({ ok: true, message: null })
    const bad = new ScriptedTransport().on('GET', `${API}/finance/balance`, {
      status: 401,
    })
    expect(await rail(bad).check()).toEqual({
      ok: false,
      message: 'Asaas check failed: Asaas rejected the API key.',
    })
    const none = new AsaasRail({
      credentials: credentials({}),
      transport: new ScriptedTransport().transport,
    })
    expect(await none.check()).toEqual({
      ok: false,
      message: 'Asaas is not configured.',
    })
  })
})
