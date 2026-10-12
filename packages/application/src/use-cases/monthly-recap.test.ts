import { Money, ValidationError } from '@cashdeck/domain'
import { describe, expect, it } from 'vitest'
import { type LlmChatResult, LlmProviderError } from '@/ports/llm-provider'
import { account, fullDeps, transaction } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import {
  MONTHLY_RECAP_COLLECTION,
  makeMonthlyRecap,
} from '@/use-cases/monthly-recap'
import { makeSubscriptions } from '@/use-cases/subscriptions'

const CATEGORIES = [
  ['food', 'groceries', 'Groceries'],
  ['fun', 'leisure', 'Leisure'],
  ['trip', 'travel', 'Travel'],
] as const

type Line = {
  id: string
  cents: number
  on: string
  categoryId?: string
  merchant?: string
}

const LINES: Line[] = [
  { id: 'salary-08', cents: 500_000, on: '2026-08-01' },
  { id: 'gym-08', cents: -8_000, on: '2026-08-03', merchant: 'Gym Club' },
  { id: 'food-08', cents: -100_000, on: '2026-08-05', categoryId: 'food' },
  { id: 'music-08', cents: -3_990, on: '2026-08-10', merchant: 'Music Plus' },
  { id: 'trip-08', cents: -90_000, on: '2026-08-15', categoryId: 'trip' },
  { id: 'salary-09', cents: 600_000, on: '2026-09-01' },
  { id: 'food-09', cents: -180_000, on: '2026-09-05', categoryId: 'food' },
  { id: 'music-09', cents: -3_990, on: '2026-09-10', merchant: 'Music Plus' },
  { id: 'fun-09', cents: -50_000, on: '2026-09-12', categoryId: 'fun' },
  { id: 'video-09', cents: -2_990, on: '2026-09-20', merchant: 'Video Max' },
  { id: 'food-10', cents: -10_000, on: '2026-10-02', categoryId: 'food' },
]

const reply = (text: string, overrides: Partial<LlmChatResult> = {}) => ({
  text,
  toolCalls: [],
  usage: { inputTokens: 1, outputTokens: 1, costMillicents: 1 },
  stopReason: 'end' as const,
  ...overrides,
})

const NBSP = String.fromCharCode(160)
// Intl writes a no-break space after the currency symbol.
const brl = (text: string) => text.replaceAll('R$ ', `R$${NBSP}`)

const AI_TEXT =
  'Setembro fechou com R$ 3.630,20 de sobra. Mercado pesou mais, com R$ 1.800,00.'

async function seeded(lines: readonly Line[] = LINES) {
  const deps = fullDeps()
  for (const [id, key, name] of CATEGORIES) {
    await deps.categories.save({
      id,
      tenantId: TENANT,
      key,
      name,
      icon: null,
      parentId: null,
    })
  }
  await deps.accounts.save(
    account({ id: 'checking', entityId: 'pf', balance: Money.of(1_000_000) }),
  )
  for (const line of lines) {
    await deps.transactions.save(
      transaction({
        id: line.id,
        accountId: 'checking',
        amount: Money.of(line.cents),
        bookedOn: line.on,
        description: line.merchant ?? line.id,
        merchant: line.merchant ?? null,
        categoryId: line.categoryId ?? null,
      }),
    )
  }
  const subscriptions = makeSubscriptions(deps)
  const recurring = lines.filter(line => line.merchant && line.on < '2026-10')
  for (const line of recurring) {
    await subscriptions.confirm(TENANT, line.id)
  }
  return { deps, recap: makeMonthlyRecap(deps) }
}

async function device(
  deps: ReturnType<typeof fullDeps>,
  token: string,
  locale: 'pt' | 'en',
  lastSeenAt: Date,
) {
  await deps.devices.register({
    tenantId: TENANT,
    token,
    platform: 'ANDROID',
    locale,
    createdAt: lastSeenAt,
    lastSeenAt,
  })
}

describe('monthly recap', () => {
  it('puts the closed month together and keeps the AI story', async () => {
    const { deps, recap } = await seeded()
    deps.llm.enqueue(reply(`${AI_TEXT}  `))
    const view = await recap.get(TENANT, '2026-09', { entity: 'PF' })
    expect(view).toMatchObject({
      month: '2026-09',
      entity: 'PF',
      flow: {
        income: { cents: 600_000 },
        expenses: { cents: 236_980 },
        net: { cents: 363_020 },
      },
      previousFlow: { net: { cents: 298_010 } },
      incomeChange: { amount: { cents: 100_000 }, percent: 20 },
      expensesChange: { amount: { cents: 34_990 }, percent: 17 },
      savings: { percent: 61, previousPercent: 60 },
      topCategory: {
        categoryId: 'food',
        key: 'groceries',
        name: 'Groceries',
        total: { cents: 180_000 },
        sharePercent: 76,
      },
      story: { text: AI_TEXT, locale: 'pt', source: 'AI' },
      generatedAt: NOW.toISOString(),
    })
    expect(view.changes.rose.map(item => item.categoryId)).toEqual([
      'food',
      'fun',
    ])
    expect(view.changes.fell).toMatchObject([
      {
        categoryId: 'trip',
        total: { cents: 0 },
        previous: { cents: 90_000 },
        change: { amount: { cents: -90_000 }, percent: -100 },
      },
    ])
    expect(view.subscriptions.started.map(item => item.name)).toEqual([
      'Video Max',
    ])
    expect(view.subscriptions.stopped).toMatchObject([
      { name: 'Gym Club', amount: Money.of(8_000).toJSON() },
    ])
    // The checking balance rolled back past the October charge.
    expect(view.netWorth).toEqual({
      total: Money.of(1_010_000).toJSON(),
      change: { amount: Money.of(363_020).toJSON(), percent: 56 },
    })
    const prompt = deps.llm.calls[0]
    expect(prompt?.system).toContain('Brazilian Portuguese')
    expect(prompt?.messages[0]?.content).toContain('R$')
    expect(
      await deps.documents.get(
        TENANT,
        MONTHLY_RECAP_COLLECTION,
        'PF:2026-09:pt',
      ),
    ).toEqual(view)

    const again = await recap.get(TENANT, '2026-09', { entity: 'PF' })
    expect(again).toEqual(view)
    expect(deps.llm.calls).toHaveLength(1)
  })

  it('falls back to the template and retries the model on the next read', async () => {
    const { deps, recap } = await seeded()
    deps.llm.chat = async () => {
      throw new LlmProviderError('down', 'unavailable')
    }
    const view = await recap.get(TENANT, '2026-09', {})
    expect(view.entity).toBeNull()
    expect(view.story).toEqual({
      text: brl(
        'Em setembro, entraram R$ 6.000,00 e saíram R$ 2.369,80, sobrando R$ 3.630,20 (61% da renda). O maior gasto foi Mercado, com 76% das despesas. Seu patrimônio fechou o mês em R$ 10.100,00.',
      ),
      locale: 'pt',
      source: 'TEMPLATE',
    })
    expect(await deps.documents.list(TENANT, MONTHLY_RECAP_COLLECTION)).toEqual(
      [],
    )
  })

  it('refuses an AI story that is cut, empty, too long or invents a figure', async () => {
    const { deps, recap } = await seeded()
    deps.llm
      .enqueue(reply(AI_TEXT, { stopReason: 'max_tokens' }))
      .enqueue(reply('   '))
      .enqueue(reply('a'.repeat(701)))
      .enqueue(reply('Sobraram R$ 9.999,99 em setembro.'))
    for (let call = 0; call < 4; call += 1) {
      const view = await recap.get(TENANT, '2026-09', { entity: 'PF' })
      expect(view.story.source).toBe('TEMPLATE')
    }
    expect(deps.llm.calls).toHaveLength(4)
  })

  it('swaps the long dash for a comma', async () => {
    const { deps, recap } = await seeded()
    const dash = String.fromCharCode(8212)
    deps.llm.enqueue(reply(`Setembro rendeu ${dash} e bem.`))
    const view = await recap.get(TENANT, '2026-09', { entity: 'PF' })
    expect(view.story.text).toBe('Setembro rendeu, e bem.')
  })

  it('speaks the language of the device seen last unless asked', async () => {
    const { deps, recap } = await seeded()
    await device(deps, 'old', 'pt', new Date('2026-10-01T00:00:00Z'))
    await device(deps, 'new', 'en', new Date('2026-10-07T00:00:00Z'))
    deps.llm.chat = async () => {
      throw new Error('down')
    }
    const english = await recap.get(TENANT, '2026-09', { entity: 'PF' })
    expect(english.story).toMatchObject({
      locale: 'en',
      text: brl(
        'In September, R$ 6.000,00 came in and R$ 2.369,80 went out, leaving R$ 3.630,20 (61% of income). Groceries was the biggest expense, at 76% of spending. Your net worth closed the month at R$ 10.100,00.',
      ),
    })
    const asked = await recap.get(TENANT, '2026-09', {
      entity: 'PF',
      locale: 'pt',
    })
    expect(asked.story.locale).toBe('pt')
  })

  it('tells a short month without a top category or net worth', async () => {
    const { deps, recap } = await seeded([
      { id: 'rent', cents: -50_000, on: '2024-05-05' },
    ])
    deps.llm.chat = async () => {
      throw new Error('down')
    }
    const pt = await recap.get(TENANT, '2024-05', { entity: 'PF' })
    expect(pt).toMatchObject({
      savings: { percent: null },
      topCategory: null,
      netWorth: null,
    })
    expect(pt.story.text).toBe(
      brl('Em maio, entraram R$ 0,00 e saíram R$ 500,00, faltando R$ 500,00.'),
    )
    const en = await recap.get(TENANT, '2024-05', {
      entity: 'PF',
      locale: 'en',
    })
    expect(en.story.text).toBe(
      brl('In May, R$ 0,00 came in and R$ 500,00 went out, R$ 500,00 short.'),
    )
  })

  it('keeps the built-in name of a category it cannot translate', async () => {
    const { deps, recap } = await seeded([
      { id: 'pet', cents: -20_000, on: '2026-09-05', categoryId: 'pets' },
    ])
    await deps.categories.save({
      id: 'pets',
      tenantId: TENANT,
      key: null,
      name: 'Pet care',
      icon: 'paw',
      parentId: null,
    })
    deps.llm.chat = async () => {
      throw new Error('down')
    }
    const view = await recap.get(TENANT, '2026-09', { entity: 'PF' })
    expect(view.story.text).toContain('O maior gasto foi Pet care')
  })

  it('only covers months that closed', async () => {
    const { recap } = await seeded()
    await expect(recap.get(TENANT, '2026-10', {})).rejects.toThrow(
      ValidationError,
    )
  })

  it('serves the last closed month as the latest', async () => {
    const { deps, recap } = await seeded()
    deps.llm.enqueue(reply(AI_TEXT))
    expect((await recap.latest(TENANT, { entity: 'PF' })).month).toBe('2026-09')
  })

  it('pushes the personal recap once per month', async () => {
    const { deps, recap } = await seeded()
    deps.llm.enqueue(reply(AI_TEXT))
    expect(await recap.run(TENANT)).toEqual({ month: '2026-09', sent: true })
    expect(await recap.run(TENANT)).toEqual({ month: '2026-09', sent: false })
    expect(deps.alerts.emitted).toEqual([
      {
        tenantId: TENANT,
        type: 'MONTHLY_RECAP',
        entityId: 'pf',
        data: {
          month: '2026-09',
          entity: 'PF',
          income: brl('R$ 6.000,00'),
          expenses: brl('R$ 2.369,80'),
        },
        dedupeKey: 'MONTHLY_RECAP:2026-09',
      },
    ])
  })

  it('stays quiet for a month without money in or out', async () => {
    const { deps, recap } = await seeded([])
    expect(await recap.run(TENANT)).toEqual({ month: '2026-09', sent: false })
    expect(deps.alerts.emitted).toEqual([])
  })

  it('skips a tenant without a personal profile', async () => {
    const { recap } = await seeded()
    expect(await recap.run('other-tenant')).toEqual({
      month: '2026-09',
      sent: false,
    })
  })
})
