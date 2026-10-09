import { type CreditLine, type LocalDate, Money } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { account, fullDeps } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { cardDues, dueAfter, nextDue } from '@/use-cases/card-cycle'

const credit = (dueOn: LocalDate | null): CreditLine => ({
  limit: Money.of(500_000),
  available: Money.of(400_000),
  closesOn: null,
  dueOn,
  brand: null,
})

const card = (id: string, line: CreditLine | null = null) =>
  account({ id, entityId: 'pf', type: 'CREDIT_CARD', credit: line })

const stored = (accountId: string, dueOn: LocalDate) => ({
  id: `${accountId}-${dueOn}`,
  tenantId: TENANT,
  accountId,
  externalId: null,
  closesOn: null,
  dueOn,
  total: Money.of(1_000),
  minimum: null,
})

describe('card cycle', () => {
  it('keeps the due day and clamps it to short months', () => {
    expect(dueAfter('2026-09-15', '2026-10-09')).toBe('2026-10-15')
    expect(dueAfter('2026-09-15', '2026-10-16')).toBe('2026-11-15')
    expect(dueAfter('2026-01-31', '2026-02-01')).toBe('2026-02-28')
  })

  it('prefers the issuer, then an unpaid bill, then the projection', () => {
    const day = '2026-10-09'
    const bills = [stored('a', '2026-08-15'), stored('a', '2026-09-15')]
    expect(nextDue(card('a', credit('2026-10-20')), bills, day)).toBe(
      '2026-10-20',
    )
    expect(nextDue(card('a', credit(null)), bills, day)).toBe('2026-10-15')
    expect(nextDue(card('a'), [...bills, stored('a', '2026-10-15')], day)).toBe(
      '2026-10-15',
    )
    expect(nextDue(card('a'), [], day)).toBeNull()
    expect(nextDue(card('a', credit('2026-09-15')), [], day)).toBe('2026-10-15')
    expect(
      nextDue(
        card('a', credit('2026-09-15')),
        [stored('a', '2026-08-15')],
        day,
      ),
    ).toBe('2026-10-15')
  })

  it('reads the stored bills of each card only', async () => {
    const deps = fullDeps()
    await deps.cardBills.saveAll([
      stored('a', '2026-09-15'),
      stored('b', '2026-09-03'),
    ])
    const dues = await cardDues(
      deps,
      TENANT,
      [card('a'), card('b'), account({ id: 'checking', entityId: 'pf' })],
      '2026-10-09',
    )
    expect([...dues]).toEqual([
      ['a', '2026-10-15'],
      ['b', '2026-11-03'],
    ])
    expect(await cardDues(deps, TENANT, [], '2026-10-09')).toEqual(new Map())
  })
})
