import { describe, expect, it } from 'vitest'
import { AsaasRail, ASAAS_URLS } from '@/rails/asaas-rail'
import { ManualTopUpFunder, TOP_UP_REASON } from '@/rails/manual-top-up-funder'
import { credentials, ENTITY, TENANT } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

describe('ManualTopUpFunder', () => {
  it('reads the Asaas balance and asks for a top-up instead of moving money', async () => {
    const scripted = new ScriptedTransport().on(
      'GET',
      `${ASAAS_URLS.production}/finance/balance`,
      { json: { balance: 12.5 } },
    )
    const resolver = credentials({ ASAAS_API_KEY: 'key' })
    const reserve = new ManualTopUpFunder({
      balance: new AsaasRail({
        credentials: resolver,
        transport: scripted.transport,
      }),
    })

    expect(
      await reserve.availableCents({ tenantId: TENANT, entityId: ENTITY }),
    ).toBe(1250)
    expect(
      await reserve.fund({
        tenantId: TENANT,
        entityId: ENTITY,
        amountCents: 7000,
        idempotencyKey: 'reserve:entity-1:2026-10-08:1',
        description: 'Cashdeck bills 2026-10-08',
      }),
    ).toEqual({ outcome: 'FAILED', externalId: null, reason: TOP_UP_REASON })
  })
})
