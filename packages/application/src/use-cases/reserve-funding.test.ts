import { describe, expect, it } from 'vitest'
import { type Bill, Money } from '@cashdeck/domain'
import { ProviderNotConfiguredError } from '@/errors/errors'
import { SYSTEM_ACTOR } from '@/ports/repositories'
import { bill } from '@/testing/deps.test-helpers'
import { FakeReserveFunder } from '@/testing/providers'
import { scenario, TENANT } from '@/testing/scenario.test-helpers'
import { makeReserveFunding } from '@/use-cases/reserve-funding'

const personal = (id: string, cents: number): Bill =>
  bill({ id, amount: Money.of(cents) })

function setup(funder: FakeReserveFunder) {
  const deps = { ...scenario(), funder }
  return { deps, funding: makeReserveFunding(deps) }
}

describe('reserve funding', () => {
  it('skips the transfer when the paying account already holds enough', async () => {
    const { deps, funding } = setup(new FakeReserveFunder(10_000))
    const summary = await funding.fundDue(TENANT, [personal('a', 4000)])
    expect(summary).toEqual({ rounds: 1, fundedCents: 0 })
    expect(deps.fundings.rows[0]).toMatchObject({
      status: 'NOT_NEEDED',
      amount: Money.of(0),
    })
    expect(deps.funder.requests).toEqual([])
    expect(deps.audit.events[0]).toMatchObject({
      action: 'reserve.funding',
      result: 'NOT_NEEDED',
      actor: 'SYSTEM',
    })
  })

  it('fails the round when the balance cannot be read', async () => {
    const { deps, funding } = setup(
      new FakeReserveFunder(new ProviderNotConfiguredError('Asaas')),
    )
    const reason = await funding.ensureFunded(
      TENANT,
      personal('a', 4000),
      SYSTEM_ACTOR,
    )
    expect(reason).toBe('RESERVE_FUNDING_FAILED')
    expect(deps.fundings.rows[0]).toMatchObject({
      status: 'FAILED',
      reason: 'NOT_CONFIGURED',
      available: null,
    })
  })

  it('records a thrown transfer as failed and never retries it that day', async () => {
    const funder = new FakeReserveFunder(0).willReturn(new Error('down'))
    const { deps, funding } = setup(funder)
    const first = await funding.ensureFunded(
      TENANT,
      personal('a', 4000),
      SYSTEM_ACTOR,
    )
    expect(first).toBe('RESERVE_FUNDING_FAILED')
    expect(deps.fundings.rows[0]?.reason).toBe('down')
    const again = await funding.ensureFunded(
      TENANT,
      personal('a', 4000),
      SYSTEM_ACTOR,
    )
    expect(again).toBe('RESERVE_FUNDING_FAILED')
    expect(funder.requests).toHaveLength(1)
  })

  it('opens a later round for late bills and resends a stuck one with its key', async () => {
    const funder = new FakeReserveFunder(0).willReturn({
      outcome: 'SUBMITTED',
      externalId: 'payout-2',
      reason: null,
    })
    const { deps, funding } = setup(funder)
    await deps.fundings.create({
      id: 'stuck',
      tenantId: TENANT,
      entityId: 'pf',
      day: '2026-10-08',
      round: 1,
      billIds: ['a'],
      billsTotal: Money.of(4000),
      available: Money.of(0),
      amount: Money.of(4000),
      status: 'IN_FLIGHT',
      reason: null,
      externalId: null,
      idempotencyKey: 'reserve:pf:2026-10-08:1',
      at: new Date(0),
    })
    const summary = await funding.fundDue(TENANT, [
      personal('a', 4000),
      personal('b', 3000),
    ])
    expect(summary).toEqual({ rounds: 2, fundedCents: 7000 })
    expect(funder.requests.map(r => [r.idempotencyKey, r.amountCents])).toEqual(
      [
        ['reserve:pf:2026-10-08:1', 4000],
        ['reserve:pf:2026-10-08:2', 3000],
      ],
    )
    expect(deps.fundings.rows.map(r => r.status)).toEqual(['SUBMITTED', 'PAID'])
  })

  it('resends a stuck round before the ladder pays from it', async () => {
    const { deps, funding } = setup(new FakeReserveFunder(0))
    await deps.fundings.create({
      id: 'stuck',
      tenantId: TENANT,
      entityId: 'pf',
      day: '2026-10-08',
      round: 1,
      billIds: ['a'],
      billsTotal: Money.of(4000),
      available: Money.of(0),
      amount: Money.of(4000),
      status: 'IN_FLIGHT',
      reason: null,
      externalId: null,
      idempotencyKey: 'reserve:pf:2026-10-08:1',
      at: new Date(0),
    })
    expect(
      await funding.ensureFunded(TENANT, personal('a', 4000), SYSTEM_ACTOR),
    ).toBeNull()
    expect(deps.fundings.rows[0]?.status).toBe('PAID')
  })

  it('counts only funded rounds and funds a bill once a day', async () => {
    const funder = new FakeReserveFunder(0).willReturn({
      outcome: 'FAILED',
      externalId: null,
      reason: 'LIMIT',
    })
    const { funding } = setup(funder)
    const bills = [personal('a', 4000)]
    expect(await funding.fundDue(TENANT, bills)).toEqual({
      rounds: 1,
      fundedCents: 0,
    })
    expect(await funding.fundDue(TENANT, bills)).toEqual({
      rounds: 0,
      fundedCents: 0,
    })
    expect(funder.requests).toHaveLength(1)
  })

  it('reads a broken funding store as unfunded', async () => {
    const { deps, funding } = setup(new FakeReserveFunder(0))
    deps.fundings.listByDay = async () => {
      throw new Error('db down')
    }
    expect(
      await funding.ensureFunded(TENANT, personal('a', 1), SYSTEM_ACTOR),
    ).toBe('RESERVE_FUNDING_FAILED')
  })
})
