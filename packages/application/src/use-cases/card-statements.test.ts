import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { base64, fullDeps } from '@/testing/deps.test-helpers'
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
})
