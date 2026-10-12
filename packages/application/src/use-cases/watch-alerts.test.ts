import { describe, expect, it } from 'vitest'
import { type AlertType, Money } from '@cashdeck/domain'
import { type InvoiceTemplate } from '@/ports/records'
import {
  account,
  fullDeps,
  invoice,
  transaction,
} from '@/testing/deps.test-helpers'
import { InMemoryEntityRepository } from '@/testing/repositories'
import { NOW, personal, TENANT } from '@/testing/scenario.test-helpers'
import { alertText } from '@/use-cases/alert-events'
import { makeRunDailyAlerts } from '@/use-cases/daily-alerts'
import { makeWatchAlerts } from '@/use-cases/watch-alerts'

// Intl puts a no-break space after the currency sign.
const brl = (text: string) => text.replace(' ', '\u00a0')

const NONE = {
  unusualPurchase: 0,
  subscriptionChanged: 0,
  cardBillAboveAverage: 0,
  bankSyncStale: 0,
  invoiceNotIssued: 0,
}

type Deps = ReturnType<typeof fullDeps>

async function spend(
  deps: Deps,
  rows: Array<[string, string, number, string, Record<string, unknown>?]>,
) {
  for (const [id, bookedOn, cents, description, extra] of rows) {
    await deps.transactions.save(
      transaction({
        id,
        accountId: 'checking',
        bookedOn,
        amount: Money.of(-cents),
        description,
        ...extra,
      }),
    )
  }
}

async function setup() {
  const deps = fullDeps()
  await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
  return deps
}

function expectReadable(deps: Deps) {
  for (const alert of deps.alerts.emitted) {
    for (const locale of ['pt', 'en'] as const) {
      const text = alertText(alert.type, alert.data, locale)
      expect(`${text.title} ${text.body}`).not.toContain('undefined')
    }
  }
}

describe('watch alerts', () => {
  it('raises nothing on a quiet tenant and runs inside the daily alerts', async () => {
    const deps = await setup()
    expect(await makeRunDailyAlerts(deps)(TENANT)).toEqual({
      dueSoon: 0,
      lowBalance: 0,
      ...NONE,
    })
  })

  it('flags a purchase far above the merchant or the category usual', async () => {
    const deps = await setup()
    await spend(deps, [
      ['p1', '2026-09-02', 3000, 'Padaria Lua'],
      ['p2', '2026-09-12', 2800, 'Padaria Lua'],
      ['p3', '2026-09-22', 3200, 'Padaria Lua'],
      ['p4', '2026-10-07', 50000, 'Padaria Lua'],
      ['p5', '2026-10-07', 60000, 'Padaria Lua', { provisional: true }],
      [
        'p6',
        '2026-10-08',
        90000,
        'Padaria Lua',
        { installment: { number: 1, count: 3, purchaseOn: null } },
      ],
      ['p7', '2026-09-01', 2000, 'Padaria Lua'],
      ['old', '2026-09-20', 90000, 'Padaria Lua'],
      ['tiny', '2026-10-08', 15000, 'Banca Sol'],
      ['b1', '2026-09-01', 1000, 'Banca Sol'],
      ['b2', '2026-09-02', 1000, 'Banca Sol'],
      ['b3', '2026-09-03', 1000, 'Banca Sol'],
      ['new', '2026-10-08', 90000, 'Loja Nova', { categoryId: 'shop' }],
      ['alone', '2026-10-08', 90000, 'Loja Unica'],
      ['pix', '2026-10-08', 90000, 'PIX ENVIADO', { categoryId: 'gift' }],
      ...[1, 2, 3, 4, 5].map(
        (n): [string, string, number, string, Record<string, unknown>] => [
          `s${n}`,
          `2026-09-1${n}`,
          10000,
          `Loja ${n}`,
          { categoryId: 'shop' },
        ],
      ),
    ])
    const run = makeWatchAlerts(deps)

    expect(await run(TENANT)).toEqual({ ...NONE, unusualPurchase: 2 })
    expect(deps.alerts.emitted.map(alert => alert.data)).toEqual([
      expect.objectContaining({
        transactionId: 'new',
        usual: brl('R$ 100,00'),
        scope: 'CATEGORY',
      }),
      expect.objectContaining({
        transactionId: 'p4',
        merchant: 'Padaria Lua',
        amount: brl('R$ 500,00'),
        usual: brl('R$ 30,00'),
        times: '16',
        scope: 'MERCHANT',
        day: '07/10',
      }),
    ])
    expect(deps.alerts.emitted[1]).toMatchObject({
      entityId: 'pf',
      dedupeKey: 'UNUSUAL_PURCHASE:p4',
    })
    expectReadable(deps)
    expect(await run(TENANT)).toEqual(NONE)
  })

  it('warns about a pricier or doubled subscription still running', async () => {
    const deps = await setup()
    const monthly = (name: string, cents: number[], days: string[]) =>
      cents.map((value, index): [string, string, number, string] => [
        `${name}-${index}`,
        days[index] as string,
        value,
        name,
      ])
    await spend(deps, [
      ...monthly(
        'STREAMING EXEMPLO',
        [3990, 3990, 3990, 4590],
        ['2026-07-05', '2026-08-05', '2026-09-05', '2026-10-05'],
      ),
      ...monthly(
        'MUSICA EXEMPLO',
        [1990, 1990, 1990, 1990],
        ['2026-08-03', '2026-09-03', '2026-10-03', '2026-10-06'],
      ),
      ...monthly('NUVEM EXEMPLO', [1000, 2000], ['2026-09-07', '2026-10-07']),
      ...monthly(
        'JORNAL EXEMPLO',
        [2990, 2990, 2990, 3490],
        ['2026-07-04', '2026-08-04', '2026-09-04', '2026-10-04'],
      ),
      ...monthly(
        'REVISTA EXEMPLO',
        [990, 990, 990, 1190],
        ['2026-06-20', '2026-07-20', '2026-08-20', '2026-09-20'],
      ),
      ...monthly('MERCADO EXEMPLO', [5000, 9000], ['2026-09-06', '2026-10-06']),
    ])
    const recurrence = {
      tenantId: TENANT,
      entityId: 'pf',
      amount: Money.of(1000),
      dayOfMonth: 7,
      lastSeenOn: null,
    }
    await deps.recurrences.save({
      ...recurrence,
      id: 'r1',
      key: 'nuvem exemplo',
      name: 'Nuvem',
      status: 'CONFIRMED',
    })
    await deps.recurrences.save({
      ...recurrence,
      id: 'r2',
      key: 'jornal exemplo',
      name: 'Jornal',
      status: 'DISMISSED',
    })
    const run = makeWatchAlerts(deps)

    expect(await run(TENANT)).toEqual({ ...NONE, subscriptionChanged: 3 })
    expect(
      deps.alerts.emitted.map(alert => [alert.data.key, alert.data.change]),
    ).toEqual([
      ['nuvem exemplo', 'PRICE_UP'],
      ['musica exemplo', 'DUPLICATE'],
      ['streaming exemplo', 'PRICE_UP'],
    ])
    expect(deps.alerts.emitted[2]?.data).toMatchObject({
      previous: brl('R$ 39,90'),
      amount: brl('R$ 45,90'),
      percent: '15',
      transactionId: 'STREAMING EXEMPLO-3',
    })
    expect(deps.alerts.emitted[1]?.data).toMatchObject({
      count: '2',
      month: '2026-10',
    })
    expectReadable(deps)
    expect(await run(TENANT)).toEqual(NONE)
  })

  it('compares the card bill that just closed with the six before', async () => {
    const deps = await setup()
    for (const id of ['card', 'old-card', 'empty-card', 'calm-card']) {
      await deps.accounts.save(
        account({
          id,
          entityId: 'pf',
          type: 'CREDIT_CARD',
          name: `Card ${id}`,
        }),
      )
    }
    const bill = (
      accountId: string,
      dueOn: string,
      cents: number,
      closesOn: string | null = null,
    ) => ({
      id: `${accountId}-${dueOn}`,
      tenantId: TENANT,
      accountId,
      externalId: null,
      closesOn,
      dueOn,
      total: Money.of(cents),
      minimum: null,
    })
    await deps.cardBills.saveAll([
      ...['03', '04', '05', '06', '07', '08', '09'].map((month, index) =>
        bill('card', `2026-${month}-10`, index === 0 ? 900_000 : 100_000),
      ),
      bill('card', '2026-10-10', 180_000, '2026-10-01'),
      bill('card', '2026-11-10', 999_000, '2026-11-01'),
      bill('old-card', '2026-06-10', 100_000),
      bill('old-card', '2026-07-10', 100_000),
      bill('old-card', '2026-08-10', 100_000),
      bill('old-card', '2026-09-10', 900_000, '2026-09-01'),
      bill('calm-card', '2026-08-10', 100_000),
      bill('calm-card', '2026-09-10', 100_000),
      bill('calm-card', '2026-10-05', 100_000),
      bill('calm-card', '2026-10-07', 110_000),
    ])
    const run = makeWatchAlerts(deps)

    expect(await run(TENANT)).toEqual({ ...NONE, cardBillAboveAverage: 1 })
    expect(deps.alerts.emitted[0]).toMatchObject({
      type: 'CARD_BILL_ABOVE_AVERAGE',
      entityId: 'pf',
      data: {
        accountId: 'card',
        card: 'Card card',
        amount: brl('R$ 1.800,00'),
        average: brl('R$ 1.000,00'),
        percent: '80',
        dueDate: '10/10',
      },
      dedupeKey: 'CARD_BILL_ABOVE_AVERAGE:card:2026-10-10',
    })
    expectReadable(deps)
    expect(await run(TENANT)).toEqual(NONE)
  })

  it('warns once per stale or broken bank connection', async () => {
    const deps = await setup()
    const hoursAgo = (hours: number) =>
      new Date(NOW.getTime() - hours * 3_600_000)
    await deps.institutions.save({
      id: 'inst',
      tenantId: TENANT,
      name: 'Banco Exemplo',
      manual: false,
    })
    const connection = {
      tenantId: TENANT,
      entityId: 'pf',
      institutionId: 'inst',
      provider: 'PLUGGY',
      status: 'UPDATED',
    }
    for (const row of [
      { id: 'fresh', lastSyncAt: hoursAgo(1) },
      { id: 'stale', lastSyncAt: hoursAgo(50) },
      { id: 'broken', lastSyncAt: hoursAgo(1), status: 'LOGIN_ERROR' },
      { id: 'never', lastSyncAt: null, institutionId: 'gone' },
    ]) {
      await deps.connections.save({ ...connection, itemId: row.id, ...row })
    }
    const run = makeWatchAlerts(deps)

    expect(await run(TENANT)).toEqual({ ...NONE, bankSyncStale: 3 })
    expect(
      deps.alerts.emitted.map(alert => [
        alert.data.connectionId,
        alert.data.institution,
        alert.data.hours,
      ]),
    ).toEqual([
      ['stale', 'Banco Exemplo', '50'],
      ['broken', 'Banco Exemplo', '1'],
      ['never', 'Banco', ''],
    ])
    expect(deps.alerts.emitted[0]?.data.lastSyncAt).toBe('06/10')
    expect(deps.alerts.emitted[2]?.dedupeKey).toBe(
      'BANK_SYNC_STALE:never:never',
    )
    expectReadable(deps)
    expect(await run(TENANT)).toEqual(NONE)
  })

  it('warns when a recurring invoice missed its usual day', async () => {
    const deps = await setup()
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Cliente Exemplo',
      taxId: null,
      country: 'BR',
    })
    const template = (
      id: string,
      dayOfMonth: number,
      active = true,
    ): InvoiceTemplate => ({
      id,
      tenantId: TENANT,
      entityId: 'pj',
      clientId: id === 'lost' ? 'gone' : 'client',
      serviceCode: '01.01',
      description: 'Consulting',
      amount: Money.of(500_000),
      billing: 'FIXED',
      hours: null,
      dayOfMonth,
      active,
    })
    for (const item of [
      template('late', 5),
      template('issued', 5),
      template('drafted', 3),
      template('lost', 1),
      template('later', 20),
      template('paused', 2, false),
    ]) {
      await deps.invoices.saveTemplate(item)
    }
    await deps.invoices.save(
      invoice({
        id: 'i1',
        templateId: 'issued',
        status: 'PROCESSING',
        competence: '2026-10',
      }),
    )
    await deps.invoices.save(
      invoice({
        id: 'i2',
        templateId: 'drafted',
        status: 'DRAFT',
        competence: '2026-10',
      }),
    )
    await deps.invoices.save(
      invoice({ id: 'i3', templateId: 'late', competence: '2026-09' }),
    )
    const run = makeWatchAlerts(deps)

    expect(await run(TENANT)).toEqual({ ...NONE, invoiceNotIssued: 3 })
    expect(
      deps.alerts.emitted.map(alert => [
        alert.data.templateId,
        alert.invoiceId,
        alert.data.client,
        alert.data.day,
      ]),
    ).toEqual(
      expect.arrayContaining([
        ['late', null, 'Cliente Exemplo', '05/10'],
        ['drafted', 'i2', 'Cliente Exemplo', '03/10'],
        ['lost', null, '', '01/10'],
      ]),
    )
    expect(
      deps.alerts.emitted.find(alert => alert.data.templateId === 'late'),
    ).toMatchObject({
      entityId: 'pj',
      data: { amount: brl('R$ 5.000,00'), competence: '2026-10' },
      dedupeKey: 'INVOICE_NOT_ISSUED:late:2026-10',
    })
    expectReadable(deps)
    expect(await run(TENANT)).toEqual(NONE)
  })

  it('skips invoices for a tenant without a company', async () => {
    const deps = {
      ...(await setup()),
      entities: new InMemoryEntityRepository([personal]),
    }
    expect(await makeWatchAlerts(deps)(TENANT)).toEqual(NONE)
  })

  it('writes every new type in both languages', () => {
    const data: Record<string, Record<string, string>[]> = {
      UNUSUAL_PURCHASE: [
        {
          merchant: 'Loja',
          amount: 'R$ 1',
          usual: 'R$ 1',
          times: '3',
          day: '01/10',
        },
      ],
      SUBSCRIPTION_CHANGED: [
        {
          change: 'PRICE_UP',
          name: 'Stream',
          amount: 'R$ 2',
          previous: 'R$ 1',
          percent: '100',
        },
        { change: 'DUPLICATE', name: 'Stream', amount: 'R$ 2', count: '2' },
      ],
      CARD_BILL_ABOVE_AVERAGE: [
        {
          card: 'Card',
          amount: 'R$ 2',
          percent: '50',
          average: 'R$ 1',
          dueDate: '10/10',
        },
      ],
      BANK_SYNC_STALE: [
        { institution: 'Banco', hours: '50' },
        { institution: 'Banco', hours: '' },
      ],
      INVOICE_NOT_ISSUED: [{ client: 'Cliente', amount: 'R$ 1', day: '05/10' }],
    }
    const texts = Object.entries(data).flatMap(([type, samples]) =>
      samples.flatMap(sample =>
        (['pt', 'en'] as const).map(locale =>
          alertText(type as AlertType, sample, locale),
        ),
      ),
    )
    expect(new Set(texts.map(text => text.body)).size).toBe(texts.length)
    for (const text of texts) {
      expect(`${text.title} ${text.body}`).not.toContain('undefined')
    }
  })
})
