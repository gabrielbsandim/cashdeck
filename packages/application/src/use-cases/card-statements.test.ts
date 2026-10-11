import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import {
  account,
  base64,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { BOLETO_LINE, TENANT } from '@/testing/scenario.test-helpers'
import { makeCardStatements } from '@/use-cases/card-statements'

const READING = {
  card: 'Visa 1234',
  issuer: 'Card Bank',
  closing: '2026-10-01',
  due: '2026-10-25',
  currency: 'USD',
  rate: 5.4,
  iofPercent: 4.38,
  paymentCode: '',
  lines: [
    {
      merchant: 'Cloud host',
      date: '2026-09-10',
      amount: 60,
      uncertain: false,
    },
    { merchant: 'Domain', date: '2026-09-12', amount: 40, uncertain: true },
    { merchant: 'Refund', date: '2026-09-20', amount: -5, uncertain: false },
  ],
}

const upload = {
  entity: 'PJ' as const,
  fileName: 'statement.pdf',
  mimeType: 'application/pdf',
  base64: base64('pdf'),
}

function setup(reading: unknown = READING) {
  const deps = fullDeps()
  deps.llm.enqueueObject(reading)
  return { deps, statements: makeCardStatements(deps) }
}

describe('card statements', () => {
  it('reads a statement into a draft with scaled numbers', async () => {
    const { deps, statements } = setup()
    expect(await statements.latest(TENANT)).toBeNull()
    const draft = await statements.read(TENANT, upload)
    expect(draft).toMatchObject({
      entityKind: 'PJ',
      rate: 54000,
      iofBps: 438,
      paymentCode: null,
      billId: null,
    })
    expect(
      draft.lines.map(line => [
        line.amount.cents,
        line.amount.currency,
        line.needsReview,
      ]),
    ).toEqual([
      [6000, 'USD', false],
      [4000, 'USD', true],
      [-500, 'USD', false],
    ])
    expect(deps.llm.calls[0]?.messages[0]?.attachments).toEqual([
      { mimeType: 'application/pdf', dataBase64: upload.base64 },
    ])
    expect(await statements.get(TENANT, draft.id)).toEqual(draft)
    expect((await statements.latest(TENANT))?.id).toBe(draft.id)
  })

  it('turns the picked lines into a bill with IOF on top', async () => {
    const { deps, statements } = setup()
    const draft = await statements.read(TENANT, upload)
    const [first, second] = draft.lines.map(line => line.id)
    await expect(
      statements.createBill(TENANT, draft.id, { lineIds: [first as string] }),
    ).rejects.toThrow('payment code or the Pix key')
    const result = await statements.createBill(TENANT, draft.id, {
      lineIds: [first as string, second as string],
      pixKey: 'billing@example.com',
    })
    expect(result).toMatchObject({
      foreign: { cents: 10000, currency: 'USD' },
      subtotal: { cents: 54000, currency: 'BRL' },
      iof: { cents: 2365 },
      total: { cents: 56365 },
    })
    const bill = await deps.bills.findById(TENANT, result.billId)
    expect(bill).toMatchObject({
      kind: 'PIX_KEY',
      payee: 'Card Bank Visa 1234',
      dueDate: '2026-10-25',
    })
    expect(bill?.amount.cents).toBe(56365)
    await expect(
      statements.createBill(TENANT, draft.id, {
        lineIds: [first as string],
        pixKey: 'x',
      }),
    ).rejects.toThrow('already has a bill')
    expect(await statements.latest(TENANT)).toBeNull()
  })

  it('uses the boleto printed on the statement and keeps the newest draft', async () => {
    const { deps, statements } = setup({ ...READING, paymentCode: BOLETO_LINE })
    const older = await statements.read(TENANT, upload)
    deps.clock.set(new Date('2026-10-08T13:00:00Z'))
    deps.llm.enqueueObject({ ...READING, paymentCode: BOLETO_LINE })
    const newer = await statements.read(TENANT, upload)
    expect((await statements.latest(TENANT))?.id).toBe(newer.id)
    const result = await statements.createBill(TENANT, older.id, {
      lineIds: older.lines.map(line => line.id),
    })
    expect((await deps.bills.findById(TENANT, result.billId))?.kind).toBe(
      'BOLETO',
    )
  })

  it('refuses an unreadable answer, an empty pick and an unknown draft', async () => {
    const { statements } = setup({ card: 'Visa' })
    await expect(statements.read(TENANT, upload)).rejects.toThrow(
      'could not be read',
    )
    const ok = setup()
    const draft = await ok.statements.read(TENANT, upload)
    await expect(
      ok.statements.createBill(TENANT, draft.id, {
        lineIds: ['nope'],
        pixKey: 'x',
      }),
    ).rejects.toThrow(ValidationError)
    await expect(ok.statements.get(TENANT, 'nope')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('books a later installment on the bill and keeps the purchase day', async () => {
    const deps = fullDeps()
    deps.llm.enqueueObject({
      ...READING,
      closing: '2026-10-08',
      currency: 'BRL',
      rate: 1,
      iofPercent: 0,
      lines: [
        {
          merchant: 'SHOE STORE CITY(02/04)',
          date: '2026-08-20',
          amount: 99.97,
          uncertain: false,
        },
        {
          merchant: 'Travel agency (01/06)',
          date: '2026-10-01',
          amount: 86.02,
          uncertain: false,
        },
        {
          merchant: 'Bill payment',
          date: '2026-09-10',
          amount: -500,
          uncertain: false,
        },
      ],
    })
    await deps.accounts.save(
      account({ id: 'card', type: 'CREDIT_CARD', entityId: 'pf' }),
    )
    const statements = makeCardStatements(deps)
    const draft = await statements.read(TENANT, { ...upload, entity: 'PF' })

    const posted = await statements.post(TENANT, draft.id, {
      accountId: 'card',
      lineIds: draft.lines.map(line => line.id),
    })

    expect(posted.added).toBe(3)
    const stored = await deps.transactions.all(TENANT, { accountIds: ['card'] })
    const byText = new Map(stored.map(tx => [tx.description, tx]))
    expect(byText.get('SHOE STORE CITY')).toMatchObject({
      bookedOn: '2026-10-08',
      merchant: 'SHOE STORE CITY',
      installment: { number: 2, count: 4, purchaseOn: '2026-08-20' },
    })
    expect(byText.get('Travel agency')).toMatchObject({
      bookedOn: '2026-10-01',
      installment: { number: 1, count: 6, purchaseOn: '2026-10-01' },
    })
    expect(byText.get('Bill payment')?.amount.cents).toBe(50_000)
    expect(byText.get('Bill payment')?.installment).toBeNull()
  })

  it('posts the lines to the card, confirming the notified previews', async () => {
    const deps = fullDeps()
    deps.llm.enqueueObject({
      ...READING,
      card: 'Card One',
      closing: '2026-10-05',
      currency: 'BRL',
      rate: 1,
      iofPercent: 0,
      lines: [
        {
          merchant: 'Bakery',
          date: '2026-10-01',
          amount: 18,
          uncertain: false,
        },
        {
          merchant: 'Shoes',
          date: '2026-10-02',
          amount: 59.99,
          uncertain: false,
        },
        { merchant: 'Gym', date: '2026-09-28', amount: 99.9, uncertain: false },
        { merchant: 'Gym', date: '2026-09-28', amount: 99.9, uncertain: false },
      ],
    })
    await deps.accounts.save(
      account({ id: 'card', type: 'CREDIT_CARD', entityId: 'pf' }),
    )
    await deps.accounts.save(account({ id: 'other', type: 'CREDIT_CARD' }))
    await deps.accounts.save(account({ id: 'checking', entityId: 'pf' }))
    const preview = (id: string, cents: number, bookedOn: string) =>
      transaction({
        id,
        accountId: 'card',
        amount: Money.of(cents),
        bookedOn,
        description: id.toUpperCase(),
        externalId: `notification:${id}`,
        provisional: true,
      })
    await deps.transactions.save({
      ...preview('bakery', -1800, '2026-10-02'),
      categoryId: 'food',
      categorizedBy: 'AI',
    })
    await deps.transactions.save({
      ...preview('shoes', -5999, '2026-10-02'),
      installment: { number: 1, count: 3, purchaseOn: '2026-10-02' },
    })
    await deps.transactions.save(preview('lost', -1000, '2026-10-03'))
    await deps.transactions.save(preview('later', -500, '2026-10-08'))
    const statements = makeCardStatements(deps)
    const draft = await statements.read(TENANT, { ...upload, entity: 'PF' })
    const lineIds = draft.lines.map(line => line.id)

    const posted = await statements.post(TENANT, draft.id, {
      accountId: 'card',
      lineIds,
    })
    expect(posted).toEqual({
      confirmed: 2,
      added: 2,
      unmatched: [
        {
          id: 'lost',
          description: 'LOST',
          bookedOn: '2026-10-03',
          amount: { cents: -1000, currency: 'BRL' },
        },
      ],
    })
    expect(await deps.transactions.findById(TENANT, 'bakery')).toMatchObject({
      description: 'Bakery',
      bookedOn: '2026-10-01',
      categoryId: 'food',
      provisional: false,
      externalId: 'statement:2026-10-05:2026-10-01:1800:1',
    })
    expect(await deps.transactions.findById(TENANT, 'shoes')).toMatchObject({
      provisional: false,
      installment: { number: 1, count: 3 },
    })
    const stored = await deps.transactions.all(TENANT, {
      accountIds: ['card'],
      provisional: false,
    })
    expect(stored.map(tx => tx.externalId).sort()).toEqual([
      'statement:2026-10-05:2026-09-28:9990:1',
      'statement:2026-10-05:2026-09-28:9990:2',
      'statement:2026-10-05:2026-10-01:1800:1',
      'statement:2026-10-05:2026-10-02:5999:1',
    ])
    expect((await statements.get(TENANT, draft.id)).accountId).toBe('card')
    const { accountId: _, ...older } = (await deps.documents.get<object>(
      TENANT,
      'card-statements',
      draft.id,
    )) as { accountId: string }
    await deps.documents.put(TENANT, 'card-statements', 'older', {
      ...older,
      id: 'older',
    })
    expect((await statements.get(TENANT, 'older')).accountId).toBeNull()

    const again = await statements.post(TENANT, draft.id, {
      accountId: 'card',
      lineIds,
    })
    expect([again.confirmed, again.added]).toEqual([0, 0])
    expect(again.unmatched.map(tx => tx.id)).toEqual(['lost'])

    for (const accountId of ['checking', 'other']) {
      await expect(
        statements.post(TENANT, draft.id, { accountId, lineIds }),
      ).rejects.toBeInstanceOf(ValidationError)
    }
    await expect(
      statements.post(TENANT, draft.id, { accountId: 'missing', lineIds }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(
      statements.post(TENANT, draft.id, {
        accountId: 'card',
        lineIds: ['nope'],
      }),
    ).rejects.toThrow('Pick at least one line')
  })
})
