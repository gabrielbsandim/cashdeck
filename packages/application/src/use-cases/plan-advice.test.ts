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
      'g3|PURCHASE|Phone|5000|5000|2.5|Million +6|50||2027-03|',
    )
    expect(prompt).toContain(
      'g2|PURCHASE|Car|40000|40000|20.0|Million +19|0|keeps value|',
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
    expect(prompt).toContain('g3|PURCHASE|Phone|5000|5000||')
    expect(prompt).toContain(
      'g1|YEARLY|Trips|12000|1000||Million +out of reach|',
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
