import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
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

function setup() {
  const deps = scenario()
  const capture = makeCaptureBill(deps)
  const run = (input: Record<string, unknown>) =>
    capture(TENANT, captureBillSchema.parse({ entityId: 'pf', ...input }))
  return { deps, run }
}

describe('captureBill', () => {
  it('captures a boleto from its digitable line and dedupes it', async () => {
    const { run } = setup()
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
