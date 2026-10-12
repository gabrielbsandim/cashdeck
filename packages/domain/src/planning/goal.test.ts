import { describe, expect, it } from 'vitest'
import { Money } from '@/money/money'
import {
  contributedTotal,
  createContribution,
  createGoal,
  goalProgress,
  goalSource,
  monthlyPace,
  paceWindowDays,
} from '@/planning/goal'
import { ValidationError } from '@/shared/domain-error'

const NOW = new Date('2026-10-11T12:00:00Z')

const base = {
  id: 'g1',
  tenantId: 't1',
  entityId: 'pf',
  name: '  Trip  ',
  target: Money.of(1_000_00),
  createdAt: NOW,
}

describe('createGoal', () => {
  it('trims the name and fills the optional fields', () => {
    expect(createGoal(base)).toEqual({
      ...base,
      name: 'Trip',
      deadline: null,
      accountId: null,
      investmentId: null,
      icon: null,
      color: null,
      archivedAt: null,
    })
    expect(
      createGoal({ ...base, icon: ' flight ', color: 'teal' }),
    ).toMatchObject({ icon: 'flight', color: 'teal' })
  })

  it('refuses a blank or long name, a target that is not positive and two sources', () => {
    expect(() => createGoal({ ...base, name: ' ' })).toThrow(ValidationError)
    expect(() => createGoal({ ...base, name: 'x'.repeat(61) })).toThrow(
      'at most 60',
    )
    expect(() => createGoal({ ...base, target: Money.zero() })).toThrow(
      'positive target',
    )
    expect(() =>
      createGoal({ ...base, accountId: 'a1', investmentId: 'i1' }),
    ).toThrow('not both')
    expect(() => createGoal({ ...base, icon: 'x'.repeat(41) })).toThrow(
      'at most 40',
    )
  })

  it('names where the saved amount comes from', () => {
    expect(goalSource(createGoal(base))).toBe('MANUAL')
    expect(goalSource(createGoal({ ...base, accountId: 'a1' }))).toBe('ACCOUNT')
    expect(goalSource(createGoal({ ...base, investmentId: 'i1' }))).toBe(
      'INVESTMENT',
    )
  })
})

describe('contributions', () => {
  const contribution = {
    id: 'c1',
    tenantId: 't1',
    goalId: 'g1',
    amount: Money.of(100_00),
    on: '2026-10-01',
    createdAt: NOW,
  }

  it('keeps a note and refuses a zero amount', () => {
    expect(createContribution(contribution).note).toBeNull()
    expect(createContribution({ ...contribution, note: ' bonus ' }).note).toBe(
      'bonus',
    )
    expect(() =>
      createContribution({ ...contribution, amount: Money.zero() }),
    ).toThrow('needs an amount')
  })

  it('adds deposits and withdrawals', () => {
    expect(
      contributedTotal([
        createContribution(contribution),
        createContribution({
          ...contribution,
          id: 'c2',
          amount: Money.of(-30_00),
        }),
      ]),
    ).toEqual(Money.of(70_00))
    expect(contributedTotal([])).toEqual(Money.zero())
  })
})

describe('pace', () => {
  it('averages over the goal age, between a month and ninety days', () => {
    expect(paceWindowDays('2026-10-10', '2026-10-11')).toBe(30)
    expect(paceWindowDays('2026-08-27', '2026-10-11')).toBe(45)
    expect(paceWindowDays('2025-01-01', '2026-10-11')).toBe(90)
  })

  it('turns what was saved in the window into a monthly amount', () => {
    expect(monthlyPace(Money.of(300_00), 90)).toEqual(Money.of(10_146))
    expect(monthlyPace(Money.of(-60_00), 30)).toEqual(Money.of(-6_087))
  })
})

describe('goalProgress', () => {
  const target = Money.of(1_200_00)
  const today = '2026-10-11'

  it('is done once the target is met', () => {
    expect(
      goalProgress({
        target,
        saved: Money.of(1_300_00),
        deadline: '2026-12-31',
        today,
        pace: Money.zero(),
      }),
    ).toEqual({
      saved: Money.of(1_300_00),
      remaining: Money.zero(),
      percent: 100,
      status: 'DONE',
      requiredMonthly: Money.zero(),
      monthlyPace: Money.zero(),
      projectedOn: null,
    })
  })

  it('is on track without a deadline and projects from the pace', () => {
    const progress = goalProgress({
      target,
      saved: Money.of(600_00),
      deadline: null,
      today,
      pace: Money.of(200_00),
    })
    expect(progress).toMatchObject({
      remaining: Money.of(600_00),
      percent: 50,
      status: 'ON_TRACK',
      requiredMonthly: null,
      projectedOn: '2027-01-11',
    })
  })

  it('splits what is left over the months to the deadline', () => {
    const progress = goalProgress({
      target,
      saved: Money.of(600_00),
      deadline: '2027-04-11',
      today,
      pace: Money.of(200_00),
    })
    expect(progress.requiredMonthly).toEqual(Money.of(100_00))
    expect(progress.status).toBe('ON_TRACK')
  })

  it('is behind when the pace misses the deadline, stops or the deadline passed', () => {
    const behind = (deadline: string, pace: number, saved = 600_00) =>
      goalProgress({
        target,
        saved: Money.of(saved),
        deadline,
        today,
        pace: Money.of(pace),
      }).status
    expect(behind('2026-11-11', 100_00)).toBe('BEHIND')
    expect(behind('2027-11-11', 0)).toBe('BEHIND')
    expect(behind('2027-11-11', -50_00)).toBe('BEHIND')
    expect(behind('2026-10-01', 900_00)).toBe('BEHIND')
  })

  it('asks for everything this month once the deadline is here or gone', () => {
    const progress = goalProgress({
      target,
      saved: Money.of(-100_00),
      deadline: '2026-09-01',
      today,
      pace: Money.of(1),
    })
    expect(progress.percent).toBe(0)
    expect(progress.requiredMonthly).toEqual(Money.of(1_300_00))
    expect(progress.projectedOn).toBeNull()
  })

  it('waits for a pace before calling a goal behind', () => {
    const progress = goalProgress({
      target,
      saved: Money.of(100_00),
      deadline: '2026-11-11',
      today,
      pace: null,
    })
    expect(progress).toMatchObject({
      status: 'ON_TRACK',
      monthlyPace: null,
      projectedOn: null,
    })
    expect(
      goalProgress({
        target,
        saved: Money.of(100_00),
        deadline: '2026-10-01',
        today,
        pace: null,
      }).status,
    ).toBe('BEHIND')
  })

  it('rounds the percent down so a goal shows 100 only when met', () => {
    expect(
      goalProgress({
        target,
        saved: Money.of(1_199_99),
        deadline: null,
        today,
        pace: Money.zero(),
      }).percent,
    ).toBe(99)
  })
})
