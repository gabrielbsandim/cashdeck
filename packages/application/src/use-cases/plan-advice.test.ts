import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { planGoalInputSchema } from '@/dtos/life-plan'
import { NotFoundError, ProviderError } from '@/errors/errors'
import { LlmProviderError, type LlmProvider } from '@/ports/llm-provider'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { FakeLlmProvider } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeLifePlan } from '@/use-cases/life-plan'
import { makePlanAdvice } from '@/use-cases/plan-advice'
import { makeSetSpendingPlan } from '@/use-cases/spending-plan'

async function seed(llm: LlmProvider = new FakeLlmProvider()) {
  const deps = { ...fullDeps(), llm }
  await deps.accounts.save(
    account({ id: 'chk', entityId: 'pf', balance: Money.of(5_000_000) }),
  )
  for (const [id, bookedOn] of [
    ['s1', '2026-08-25'],
    ['s2', '2026-09-25'],
  ] as const) {
    await deps.transactions.save(
      transaction({
        id,
        bookedOn,
        accountId: 'chk',
        amount: Money.of(800_000),
        description: 'Salary',
        counterparty: '12345678000195',
      }),
    )
  }
  await makeSetSpendingPlan(deps)(TENANT, {
    savings: { cents: 300_000, currency: 'BRL' },
  })
  const plan = makeLifePlan(deps)
  for (const input of [
    { kind: 'YEARLY', name: 'Trips', yearly: 1_200_000 },
    { kind: 'PURCHASE', name: 'Car', price: 4_000_000, keepsValue: true },
    {
      kind: 'PURCHASE',
      name: 'Phone',
      price: 500_000,
      monthlyCost: 5_000,
      notBefore: '2027-03',
    },
    { kind: 'MILESTONE', name: 'Million', metric: 'INVESTED', target: 10 ** 8 },
  ]) {
    await plan.create(TENANT, planGoalInputSchema.parse(input))
  }
  const ids = (await plan.view(TENANT)).goals.map(goal => goal.id) as [
    string,
    string,
    string,
    string,
  ]
  return { deps, plan, advice: makePlanAdvice(deps), ids }
}

const names = (goals: readonly { name: string }[]) =>
  goals.map(goal => goal.name)

describe('plan advice', () => {
  it('arranges the whole plan as the model proposes, without writing', async () => {
    const llm = new FakeLlmProvider().enqueueObject({
      summary: 'Celular depois do carro.',
      goals: [
        { ref: 'g2', notBefore: '', reason: 'O carro rende mais.' },
        { ref: 'g9', notBefore: '', reason: 'Inventado' },
        { ref: 'g3', notBefore: '2028-02', reason: 'Celular dura mais.' },
        { ref: 'g2', notBefore: '', reason: 'Repetido' },
        { ref: 'g1', notBefore: '2027-01', reason: 'Viagens todo ano.' },
      ],
    })
    const { plan, advice } = await seed(llm)

    const answer = await advice.advise(TENANT, { goalId: null })

    expect(answer.goalId).toBeNull()
    expect(answer.summary).toBe('Celular depois do carro.')
    expect(names(answer.goals)).toEqual(['Car', 'Phone', 'Trips', 'Million'])
    expect(answer.goals.map(goal => [goal.notBefore, goal.reason])).toEqual([
      [null, 'O carro rende mais.'],
      ['2028-02', 'Celular dura mais.'],
      [null, 'Viagens todo ano.'],
      [null, null],
    ])
    expect(answer.goals[1]).toMatchObject({
      kind: 'PURCHASE',
      month: '2027-10',
      status: 'PLANNED',
      proposedMonth: '2028-02',
      proposedStatus: 'PLANNED',
    })
    const prompt = llm.calls[0]?.messages[0]?.content
    expect(prompt).toContain('Today: 2026-10')
    expect(prompt).toContain(
      'g3|PURCHASE|Phone|5000|5000|cash|2.5||Million +6|50||2027-03|',
    )
    expect(prompt).toContain(
      'g2|PURCHASE|Car|40000|40000|cash|20.0||Million +19|0|keeps value|',
    )
    expect(prompt).toContain('Arrange the whole plan.')
    expect(names((await plan.view(TENANT)).goals)).toEqual([
      'Trips',
      'Car',
      'Phone',
      'Million',
    ])
  })

  it('places one goal among the others and keeps the rest as it was', async () => {
    const llm = new FakeLlmProvider().enqueueObject({
      summary: 'O marco vem antes.',
      goals: [
        { ref: 'g4', notBefore: '', reason: 'Primeiro o milhão.' },
        { ref: 'g1', notBefore: '', reason: 'Fica.' },
        { ref: 'g2', notBefore: '2030-01', reason: 'Fica.' },
        { ref: 'g3', notBefore: '', reason: 'Fica.' },
      ],
    })
    const { advice, ids } = await seed(llm)

    const answer = await advice.advise(TENANT, { goalId: ids[3] })

    expect(answer.goalId).toBe(ids[3])
    expect(names(answer.goals)).toEqual(['Million', 'Trips', 'Car', 'Phone'])
    expect(answer.goals.map(goal => [goal.notBefore, goal.reason])).toEqual([
      [null, 'Primeiro o milhão.'],
      [null, null],
      [null, null],
      ['2027-03', null],
    ])
    expect(llm.calls[0]?.messages[0]?.content).toContain('Place only g4')
  })

  it('keeps the goal in place and its wait when the model gets it wrong', async () => {
    const llm = new FakeLlmProvider()
      .enqueueObject({
        summary: 'Nada muda.',
        goals: [{ ref: 'g3', notBefore: 'soon', reason: 'Espera.' }],
      })
      .enqueueObject({ summary: 'Nada.', goals: [] })
      .enqueueObject({
        summary: 'Já pode.',
        goals: [{ ref: 'g3', notBefore: '2020-01', reason: 'Agora.' }],
      })
    const { advice, ids } = await seed(llm)

    const unclear = await advice.advise(TENANT, { goalId: ids[2] })
    expect(names(unclear.goals)).toEqual(['Phone', 'Trips', 'Car', 'Million'])
    expect(unclear.goals[0]?.notBefore).toBe('2027-03')

    const silent = await advice.advise(TENANT, { goalId: ids[2] })
    expect(names(silent.goals)).toEqual(['Trips', 'Car', 'Phone', 'Million'])
    expect(silent.goals[2]).toMatchObject({
      notBefore: '2027-03',
      reason: null,
    })

    const past = await advice.advise(TENANT, { goalId: ids[2] })
    expect(past.goals[0]).toMatchObject({ name: 'Phone', notBefore: null })
  })

  it('gives no weight when nothing is left to save', async () => {
    const llm = new FakeLlmProvider().enqueueObject({ summary: '', goals: [] })
    const { deps, advice } = await seed(llm)
    await makeSetSpendingPlan(deps)(TENANT, {
      savings: { cents: 100_000, currency: 'BRL' },
    })

    await advice.advise(TENANT, { goalId: null })

    const prompt = llm.calls[0]?.messages[0]?.content
    expect(prompt).toContain('g3|PURCHASE|Phone|5000|5000|cash|||')
    expect(prompt).toContain(
      'g1|YEARLY|Trips|12000|1000||||Million +out of reach|',
    )
  })

  async function withCards(llm: LlmProvider, count: number) {
    const seeded = await seed(llm)
    const { deps } = seeded
    await deps.accounts.save(
      account({ id: 'card', entityId: 'pf', type: 'CREDIT_CARD' }),
    )
    await deps.cardBills.saveAll([
      bill('2026-08-15', 400_000),
      bill('2026-09-15', 600_000),
      bill('2026-04-15', 900_000),
    ])
    if (count > 0) {
      await deps.transactions.save(
        transaction({
          id: 'tv',
          accountId: 'card',
          bookedOn: '2026-10-05',
          amount: Money.of(-300_000),
          description: 'LOJA TV',
          merchant: 'TV Exemplo',
          installment: { number: 1, count, purchaseOn: '2026-10-01' },
        }),
      )
    }
    return seeded
  }

  const bill = (dueOn: string, total: number) => ({
    id: `card-${dueOn}`,
    tenantId: TENANT,
    accountId: 'card',
    externalId: null,
    closesOn: null,
    dueOn,
    total: Money.of(total),
    minimum: null,
  })

  it('weighs the savings, the card bills and paying at once', async () => {
    const llm = new FakeLlmProvider().enqueueObject({
      summary: 'O tablet (g5) espera as parcelas.',
      goals: [],
    })
    const { deps, plan, advice } = await withCards(llm, 3)
    for (const month of ['04', '05', '06', '07']) {
      await deps.transactions.save(
        transaction({
          id: `salary-${month}`,
          bookedOn: `2026-${month}-25`,
          accountId: 'chk',
          amount: Money.of(800_000),
          description: 'Salary',
          counterparty: '12345678000195',
        }),
      )
    }
    await deps.indexRates.save('CDI', [{ day: '2026-10-01', value: 0.0551 }])
    for (const input of [
      {
        kind: 'PURCHASE',
        name: 'Tablet',
        price: 2_000_000,
        payment: 'CARD',
        installments: 10,
        cashDiscount: 5,
      },
      { kind: 'PURCHASE', name: 'Lamp', price: 10_000, payment: 'CARD' },
      { kind: 'PURCHASE', name: 'Desk', price: 100_000, installments: 2 },
      {
        kind: 'PURCHASE',
        name: 'Sofa',
        price: 300_000,
        payment: 'CARD',
        installments: 3,
      },
    ]) {
      await plan.create(TENANT, planGoalInputSchema.parse(input))
    }

    const answer = await advice.advise(TENANT, { goalId: null })

    const prompt = llm.calls[0]?.messages[0]?.content
    expect(prompt).toContain(
      'Savings of the last closed months: 2026-04 8000, 2026-05 8000, ' +
        '2026-06 8000, 2026-07 8000, 2026-08 8000, 2026-09 8000 (median ' +
        '8000, worst 8000)',
    )
    expect(prompt).toContain(
      'Card bills by due month: 2026-08 4000, 2026-09 6000 (average 5000)',
    )
    expect(prompt).toContain(
      'Installments already on the cards: 2026-11 3000, 2026-12 3000. They ' +
        'fall to 500 or less from 2027-01: a purchase on the card from ' +
        '2026-12 does not stack on them.',
    )
    expect(prompt).toContain(
      'g5|PURCHASE|Tablet|20000|20000|card 10x|10.0|2.5|',
    )
    expect(answer.summary).toBe('O tablet espera as parcelas.')
    expect(prompt).toContain(
      'Paying at once against the installments, CDI 14.9% a year:\n' +
        'g5: 10 bills of 2000 from the month after are worth 19013 today at ' +
        'the CDI after tax; at once with 5% off costs 19000, so paying at ' +
        'once is better by 13. At once wins from 4.9% off.',
    )
    expect(prompt).not.toContain('g6:')
    expect(prompt).toContain(
      'Bought now, its bills come on top of up to 3000 already on the ' +
        'cards; bought in 2026-12, on top of up to 0.',
    )
    expect(prompt).toContain('g7|PURCHASE|Desk|1000|1000|cash, 2x offered|')
    expect(prompt).toContain('g7: 2 bills of 500')
    expect(prompt).toContain('so paying in installments is better by 53.')
    expect(answer.goals.find(goal => goal.name === 'Tablet')?.payment).toEqual({
      installments: 10,
      cash: { cents: 1_900_000, currency: 'BRL' },
      cardToday: { cents: 1_901_312, currency: 'BRL' },
      better: 'CASH',
      gain: { cents: 1_312, currency: 'BRL' },
      breakEvenPercent: 4.9,
    })
    expect(answer.goals.find(goal => goal.name === 'Lamp')?.payment).toBeNull()
  })

  it('says how the bills move and when the installments weigh or stay', async () => {
    const low = new FakeLlmProvider().enqueueObject({ summary: '', goals: [] })
    const quiet = await withCards(low, 0)
    await quiet.deps.cardBills.saveAll([bill('2026-07-15', 800_000)])
    await quiet.advice.advise(TENANT, { goalId: null })
    const calm = low.calls[0]?.messages[0]?.content
    expect(calm).toContain(
      'The last two bills average 5000, against 8000 in the months before: ' +
        'they did not rise.',
    )
    expect(calm).toContain(
      'Installments already on the cards: none. They are already low: ' +
        'nothing to wait for.',
    )

    const long = new FakeLlmProvider().enqueueObject({ summary: '', goals: [] })
    const busy = await withCards(long, 24)
    await busy.deps.cardBills.saveAll([bill('2026-07-15', 100_000)])
    await busy.deps.indexRates.save('CDI', [
      { day: '2026-10-01', value: 0.0551 },
    ])
    await busy.plan.create(
      TENANT,
      planGoalInputSchema.parse({
        kind: 'PURCHASE',
        name: 'Desk',
        price: 100_000,
        installments: 2,
      }),
    )
    await busy.advice.advise(TENANT, { goalId: null })
    const heavy = long.calls[0]?.messages[0]?.content
    expect(heavy).toContain('they rose.')
    expect(heavy).toContain('They stay above 367 a month all year.')
    expect(heavy).toContain(
      'Bought now, its bills come on top of up to 3000 already on the cards.',
    )
  })

  it('applies an arrangement', async () => {
    const { advice, ids } = await seed()
    const applied = await advice.apply(TENANT, {
      goals: [{ id: ids[2], notBefore: null }],
    })
    expect(applied.goals[0]).toMatchObject({ name: 'Phone', notBefore: null })
  })

  it('says why there is no advice', async () => {
    const { advice } = await seed()
    await expect(
      advice.advise(TENANT, { goalId: 'missing' }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(
      advice.advise(TENANT, { goalId: null }),
    ).rejects.toBeInstanceOf(ProviderError)

    const failing = (error: Error): LlmProvider => ({
      name: 'failing',
      modelId: 'failing',
      chat: async () => {
        throw error
      },
    })
    const down = await seed(failing(new LlmProviderError('down', 'HTTP')))
    await expect(down.advice.advise(TENANT, { goalId: null })).rejects.toThrow(
      new ProviderError('AI', 'down'),
    )
    const broken = await seed(failing(new TypeError('bug')))
    await expect(
      broken.advice.advise(TENANT, { goalId: null }),
    ).rejects.toBeInstanceOf(TypeError)
  })
})
