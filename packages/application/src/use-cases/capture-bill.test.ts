import { describe, expect, it } from 'vitest'
import { encodeBrCode, Money, ValidationError } from '@cashdeck/domain'
import { captureBillSchema } from '@/dtos/bill'
import { NotFoundError } from '@/errors/errors'
import { makeCaptureBill } from '@/use-cases/capture-bill'
import {
  BOLETO_BARCODE,
  BOLETO_LINE,
  PIX_NO_AMOUNT,
  scenario,
  TAX_BARCODE,
  TENANT,
} from '@/testing/scenario.test-helpers'

const PIX_WITH_AMOUNT = encodeBrCode({
  key: 'tax@example.com',
  merchantName: 'Receita Exemplo',
  merchantCity: 'BRASILIA',
  amount: Money.of(15000),
})

function setup() {
  const deps = scenario()
  const capture = makeCaptureBill(deps)
  const run = (input: Record<string, unknown>) =>
    capture(TENANT, captureBillSchema.parse({ entityId: 'pf', ...input }))
  return { deps, run }
}

describe('captureBill', () => {
  it('captures a boleto from its digitable line and dedupes it', async () => {
    const { deps, run } = setup()
    const first = await run({ paymentCode: BOLETO_LINE, source: 'CAMERA' })
    expect(first.duplicate).toBe(false)
    expect(first.bill).toMatchObject({
      kind: 'BOLETO',
      code: BOLETO_BARCODE,
      dueDate: '2026-10-20',
      source: 'CAMERA',
      status: 'OPEN',
    })
    expect(first.bill.amount).toEqual(Money.of(12345))

    expect(
      (await deps.payments.findPlan(TENANT, first.bill.id))?.steps.at(-1)?.mode,
    ).toBe('ASSISTED')

    const second = await run({ paymentCode: BOLETO_BARCODE })
    expect(second.duplicate).toBe(true)
    expect(second.bill.id).toBe(first.bill.id)
  })

  it('captures a tax guide and falls back to the given or current due date', async () => {
    const { run } = setup()
    const guide = await run({ paymentCode: TAX_BARCODE, dueDate: '2026-10-20' })
    expect(guide.bill.kind).toBe('TAX_BARCODE')
    expect(guide.bill.dueDate).toBe('2026-10-20')
    expect(guide.bill.source).toBe('MANUAL')
  })

  it('captures a Pix QR code, taking the payee from the code', async () => {
    const { run } = setup()
    const { bill } = await run({ paymentCode: PIX_NO_AMOUNT, amountCents: 900 })
    expect(bill).toMatchObject({
      kind: 'PIX_QR',
      payee: 'Fulano de Tal',
      dueDate: '2026-10-08',
    })
    const named = await setup().run({
      paymentCode: PIX_NO_AMOUNT,
      amountCents: 900,
      payee: 'Landlord',
    })
    expect(named.bill.payee).toBe('Landlord')
  })

  it('captures a boleto com Pix with both codes', async () => {
    const { run } = setup()
    const { bill } = await run({
      paymentCode: BOLETO_LINE,
      pixCode: PIX_NO_AMOUNT,
    })
    expect(bill).toMatchObject({
      kind: 'BOLETO',
      code: BOLETO_BARCODE,
      pixCode: PIX_NO_AMOUNT,
      payee: 'Fulano de Tal',
    })
    expect(bill.amount).toEqual(Money.of(12345))
    const pixOnly = await setup().run({
      pixCode: PIX_NO_AMOUNT,
      amountCents: 900,
    })
    expect(pixOnly.bill).toMatchObject({
      kind: 'PIX_QR',
      code: PIX_NO_AMOUNT,
      pixCode: PIX_NO_AMOUNT,
    })
    const tax = await setup().run({
      paymentCode: TAX_BARCODE,
      pixCode: PIX_WITH_AMOUNT,
      dueDate: '2026-10-20',
    })
    expect(tax.bill).toMatchObject({
      kind: 'TAX_BARCODE',
      pixCode: PIX_WITH_AMOUNT,
    })
    expect(tax.bill.amount).toEqual(Money.of(15000))
  })

  it('rejects a Pix code that does not match its barcode', async () => {
    const { run } = setup()
    await expect(
      run({ paymentCode: PIX_NO_AMOUNT, pixCode: PIX_NO_AMOUNT }),
    ).rejects.toThrow('next to a barcode')
    await expect(
      run({ paymentCode: BOLETO_LINE, pixCode: TAX_BARCODE }),
    ).rejects.toThrow('next to a barcode')
    await expect(
      run({ paymentCode: BOLETO_LINE, pixCode: PIX_WITH_AMOUNT }),
    ).rejects.toThrow('amounts differ')
    expect(() =>
      captureBillSchema.parse({
        entityId: 'pf',
        pixCode: PIX_NO_AMOUNT,
        pixKey: 'k',
      }),
    ).toThrow()
  })

  it('captures a Pix key and a DARF without barcode with explicit amounts', async () => {
    const { run } = setup()
    const pix = await run({ pixKey: 'person@example.com', amountCents: 5000 })
    expect(pix.bill).toMatchObject({
      kind: 'PIX_KEY',
      code: 'person@example.com',
    })
    const darf = await run({
      darfWithoutBarcode: true,
      amountCents: 7000,
      dueDate: '2026-10-20',
    })
    expect(darf.bill).toMatchObject({ kind: 'DARF_NO_BARCODE', code: null })
    expect(darf.duplicate).toBe(false)
  })

  it('requires an amount when the code has none', async () => {
    const { run } = setup()
    await expect(run({ pixKey: 'person@example.com' })).rejects.toThrow(
      ValidationError,
    )
  })

  it('rejects an unknown entity', async () => {
    const { run } = setup()
    await expect(
      run({ entityId: 'missing', pixKey: 'k', amountCents: 1 }),
    ).rejects.toThrow(NotFoundError)
  })

  it('accepts exactly one payment input', () => {
    expect(captureBillSchema.safeParse({ entityId: 'pf' }).success).toBe(false)
    expect(
      captureBillSchema.safeParse({
        entityId: 'pf',
        pixKey: 'k',
        paymentCode: 'x',
      }).success,
    ).toBe(false)
  })
})
