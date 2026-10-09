import { describe, expect, it } from 'vitest'
import { AsaasRail, ASAAS_URLS } from '@/rails/asaas-rail'
import { MercadoPagoPayoutsRail } from '@/rails/mercado-pago-rail'
import { PixReserveFunder } from '@/rails/reserve-funder'
import { credentials, ENTITY, TENANT } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

const MP = 'https://api.mercadopago.com'
const request = {
  tenantId: TENANT,
  entityId: ENTITY,
  amountCents: 7000,
  idempotencyKey: 'reserve:entity-1:2026-10-08:1',
  description: 'Cashdeck bills 2026-10-08',
}

function funder(scripted: ScriptedTransport, env: Record<string, string>) {
  const resolver = credentials({
    ASAAS_API_KEY: 'key',
    MERCADO_PAGO_ACCESS_TOKEN: 'token',
    MERCADO_PAGO_ENVIRONMENT: 'sandbox',
    ...env,
  })
  const transport = scripted.transport
  return new PixReserveFunder({
    credentials: resolver,
    balance: new AsaasRail({ credentials: resolver, transport }),
    payouts: new MercadoPagoPayoutsRail({ credentials: resolver, transport }),
  })
}

describe('PixReserveFunder', () => {
  it('reads the Asaas balance and pays the shortfall to its Pix key', async () => {
    const scripted = new ScriptedTransport()
      .on('GET', `${ASAAS_URLS.production}/finance/balance`, {
        json: { balance: 12.5 },
      })
      .on(
        'POST',
        `${MP}/v1/payouts`,
        {
          status: 202,
          json: { id: 'P1', transactions: [{ id: 'T1', status: 'success' }] },
        },
        { status: 202, json: { id: 'P2', transactions: [{ id: 'T2' }] } },
        { status: 400, json: { message: 'Insufficient balance' } },
      )
    const reserve = funder(scripted, { ASAAS_PIX_KEY: 'asaas@example.com' })
    expect(
      await reserve.availableCents({ tenantId: TENANT, entityId: ENTITY }),
    ).toBe(1250)
    expect(await reserve.fund(request)).toEqual({
      outcome: 'PAID',
      externalId: 'P1/T1',
      reason: null,
    })
    const sent = scripted.last('POST', `${MP}/v1/payouts`)
    expect(sent.headers).toMatchObject({
      'x-idempotency-key': 'reserve:entity-1:2026-10-08:1',
    })
    expect(JSON.parse(sent.body ?? '{}').transactions[0]).toMatchObject({
      pix: { type: 'EMAIL', chave: 'asaas@example.com' },
      amount: { currency: 'BRL', value: 70 },
    })
    expect((await reserve.fund(request)).outcome).toBe('SUBMITTED')
    expect(await reserve.fund(request)).toEqual({
      outcome: 'FAILED',
      externalId: null,
      reason: 'Insufficient balance',
    })
  })

  it('refuses to fund without the Asaas Pix key', async () => {
    const reserve = funder(new ScriptedTransport(), {})
    await expect(reserve.fund(request)).rejects.toThrow(
      'Reserve funding is not configured.',
    )
  })
})
