import { describe, expect, it } from 'vitest'
import { crc16, encodeBrCode, Money, transitionBill } from '@cashdeck/domain'
import { captureBillSchema } from '@/dtos/bill'
import { AmountRequiredError, NotFoundError } from '@/errors/errors'
import { type PixCharge } from '@/ports/providers'
import { FakePixLocationResolver } from '@/testing/providers'
import { makeCaptureBill } from '@/use-cases/capture-bill'
import {
  BOLETO_BARCODE,
  BOLETO_LINE,
  NOW,
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
// The Pix half of the BOLETO_LINE bolepix: same amount.
const PIX_OF_BOLETO = encodeBrCode({
  key: '11222333000181',
  merchantName: 'Fornecedor Exemplo',
  merchantCity: 'SAO PAULO',
  amount: Money.of(12345),
})
const LOCATION = 'pix.example.com/qr/v2/cobv/abc123'

function dynamicPix(location: string, city = 'SAO PAULO'): string {
  const account = `0014br.gov.bcb.pix25${String(location.length).padStart(2, '0')}${location}`
  const tail = `5802BR5918Fornecedor Exemplo60${String(city.length).padStart(2, '0')}${city}62070503***6304`
  const body = `000201010212${`26${account.length}${account}`}520400005303986${tail}`
  return body + crc16(body)
}

const charge = (overrides: Partial<PixCharge> = {}): PixCharge => ({
  amount: Money.of(12345),
  dueDate: '2026-10-25',
  key: '11222333000181',
  payee: 'Fornecedor Exemplo Ltda',
  txid: 'abc123',
  ...overrides,
})

function setup(charges: Record<string, PixCharge | Error> = {}) {
  const pixLocations = new FakePixLocationResolver(charges)
  const deps = { ...scenario(), pixLocations }
  const capture = makeCaptureBill(deps)
  const run = (input: Record<string, unknown>) =>
    capture(TENANT, captureBillSchema.parse({ entityId: 'pf', ...input }))
  return { deps, run, pixLocations }
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

  it('accepts the same Pix code in both fields and refuses two different ones', async () => {
    const { run } = setup()
    const same = await run({
      paymentCode: PIX_NO_AMOUNT,
      pixCode: PIX_NO_AMOUNT,
      amountCents: 900,
    })
    expect(same.bill).toMatchObject({ kind: 'PIX_QR', pixCode: PIX_NO_AMOUNT })
    await expect(
      run({ paymentCode: PIX_NO_AMOUNT, pixCode: PIX_WITH_AMOUNT }),
    ).rejects.toThrow('next to a barcode')
  })

  it('keeps the barcode and drops a Pix half that is invalid or disagrees', async () => {
    const invalid = setup()
    const kept = await invalid.run({
      paymentCode: BOLETO_LINE,
      pixCode: TAX_BARCODE,
    })
    expect(kept.bill).toMatchObject({ kind: 'BOLETO', pixCode: null })
    expect(invalid.deps.audit.events).toEqual([
      expect.objectContaining({
        action: 'bill.pix_code_dropped',
        subjectId: kept.bill.id,
        result: 'INVALID_PIX_CODE',
        at: NOW,
      }),
    ])

    const mismatch = setup()
    const other = await mismatch.run({
      paymentCode: BOLETO_LINE,
      pixCode: PIX_WITH_AMOUNT,
    })
    expect(other.bill.pixCode).toBeNull()
    expect(other.bill.amount).toEqual(Money.of(12345))
    expect(mismatch.deps.audit.events[0]?.result).toBe('AMOUNT_MISMATCH')
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

  it('answers AMOUNT_REQUIRED when no code, charge or client gives an amount', async () => {
    const { run } = setup()
    const failure = await run({ pixKey: 'person@example.com' }).catch(
      (error: unknown) => error,
    )
    expect(failure).toBeInstanceOf(AmountRequiredError)
    expect(failure).toMatchObject({
      code: 'AMOUNT_REQUIRED',
      details: { field: 'amountCents', kind: 'PIX_KEY', payee: null },
    })
    await expect(run({ pixCode: PIX_NO_AMOUNT })).rejects.toMatchObject({
      code: 'AMOUNT_REQUIRED',
      details: { kind: 'PIX_QR', payee: 'Fulano de Tal' },
    })
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
    expect(() =>
      captureBillSchema.parse({
        entityId: 'pf',
        pixCode: PIX_NO_AMOUNT,
        pixKey: 'k',
      }),
    ).toThrow()
  })
})

describe('captureBill with a dynamic Pix code', () => {
  it('fills the amount, due date and payee from the charge at its location', async () => {
    const { run, pixLocations } = setup({ [LOCATION]: charge() })
    const { bill } = await run({ pixCode: dynamicPix(LOCATION) })
    expect(pixLocations.resolved).toEqual([LOCATION])
    expect(bill).toMatchObject({
      kind: 'PIX_QR',
      dueDate: '2026-10-25',
      payee: 'Fornecedor Exemplo Ltda',
    })
    expect(bill.amount).toEqual(Money.of(12345))
  })

  it('falls back to the client fields when the location fails or answers nothing', async () => {
    const failing = setup({ [LOCATION]: new Error('timeout') })
    await expect(
      failing.run({ pixCode: dynamicPix(LOCATION) }),
    ).rejects.toBeInstanceOf(AmountRequiredError)
    const { bill } = await failing.run({
      pixCode: dynamicPix(LOCATION),
      amountCents: 5000,
      dueDate: '2026-10-30',
    })
    expect(bill).toMatchObject({
      dueDate: '2026-10-30',
      payee: 'Fornecedor Exemplo',
    })

    const empty = setup()
    const partial = await empty.run({
      pixCode: dynamicPix(LOCATION),
      amountCents: 5000,
    })
    expect(partial.bill.dueDate).toBe('2026-10-08')

    const unwired = makeCaptureBill(scenario())
    const plain = await unwired(
      TENANT,
      captureBillSchema.parse({
        entityId: 'pf',
        pixCode: dynamicPix(LOCATION),
        amountCents: 700,
      }),
    )
    expect(plain.bill.amount).toEqual(Money.of(700))
  })

  it('drops the Pix half of a bolepix whose charge asks for another amount', async () => {
    const { deps, run } = setup({
      [LOCATION]: charge({ amount: Money.of(99999) }),
    })
    const { bill } = await run({
      paymentCode: BOLETO_LINE,
      pixCode: dynamicPix(LOCATION),
    })
    expect(bill).toMatchObject({ kind: 'BOLETO', pixCode: null })
    expect(deps.audit.events[0]?.result).toBe('CHARGE_AMOUNT_MISMATCH')

    const agreeing = setup({ [LOCATION]: charge({ amount: null }) })
    const paired = await agreeing.run({
      paymentCode: BOLETO_LINE,
      pixCode: dynamicPix(LOCATION),
    })
    expect(paired.bill.pixCode).toBe(dynamicPix(LOCATION))
  })

  it('treats two codes with one location as the same charge', async () => {
    const { run } = setup({ [LOCATION]: charge() })
    const first = await run({ pixCode: dynamicPix(LOCATION) })
    const again = await run({ pixCode: dynamicPix(LOCATION, 'CAMPINAS') })
    expect(again).toEqual({ bill: first.bill, duplicate: true })
  })
})

describe('captureBill pairing the halves of a bolepix', () => {
  it('finds a bill by its Pix code', async () => {
    const { run } = setup()
    const first = await run({
      paymentCode: BOLETO_LINE,
      pixCode: PIX_OF_BOLETO,
    })
    const again = await run({ pixCode: PIX_OF_BOLETO })
    expect(again).toEqual({ bill: first.bill, duplicate: true })
  })

  it('attaches a Pix code that arrives after its barcode', async () => {
    const { deps, run } = setup()
    const boleto = await run({
      paymentCode: BOLETO_LINE,
      payee: 'Fornecedor Exemplo S.A.',
    })
    const pix = await run({ pixCode: PIX_OF_BOLETO })
    expect(pix.duplicate).toBe(true)
    expect(pix.bill).toMatchObject({
      id: boleto.bill.id,
      kind: 'BOLETO',
      code: BOLETO_BARCODE,
      pixCode: PIX_OF_BOLETO,
      payee: 'Fornecedor Exemplo S.A.',
    })
    expect(await deps.bills.findById(TENANT, boleto.bill.id)).toEqual(pix.bill)
    expect(deps.audit.events.map(event => event.action)).toEqual([
      'bill.codes_merged',
    ])
  })

  it('attaches a barcode to a Pix QR bill of the same due date', async () => {
    const { run } = setup()
    const pix = await run({ pixCode: PIX_OF_BOLETO, dueDate: '2026-10-20' })
    const boleto = await run({ paymentCode: BOLETO_LINE })
    expect(boleto.bill).toMatchObject({
      id: pix.bill.id,
      kind: 'BOLETO',
      code: BOLETO_BARCODE,
      pixCode: PIX_OF_BOLETO,
      dueDate: '2026-10-20',
    })

    const viaPixCode = setup()
    const qr = await viaPixCode.run({ pixCode: PIX_OF_BOLETO })
    const both = await viaPixCode.run({
      paymentCode: BOLETO_LINE,
      pixCode: PIX_OF_BOLETO,
    })
    expect(both.bill).toMatchObject({ id: qr.bill.id, kind: 'BOLETO' })
  })

  it('keeps bills apart when neither the payee nor the due date matches', async () => {
    const { run } = setup()
    const boleto = await run({
      paymentCode: BOLETO_LINE,
      payee: 'Outra Empresa',
    })
    const pix = await run({ pixCode: PIX_OF_BOLETO })
    expect(pix.duplicate).toBe(false)
    expect(pix.bill.id).not.toBe(boleto.bill.id)
  })

  it('leaves a bill that started paying untouched', async () => {
    const processing = setup()
    const boleto = await processing.run({
      paymentCode: BOLETO_LINE,
      payee: 'Fornecedor Exemplo',
    })
    await processing.deps.bills.save(transitionBill(boleto.bill, 'PROCESSING'))
    const pix = await processing.run({ pixCode: PIX_OF_BOLETO })
    expect(pix).toMatchObject({ duplicate: true, bill: { pixCode: null } })

    const attempted = setup()
    const first = await attempted.run({
      paymentCode: BOLETO_LINE,
      payee: 'Fornecedor Exemplo',
    })
    await attempted.deps.payments.addAttempt(TENANT, {
      id: 'a1',
      billId: first.bill.id,
      stepIndex: 0,
      rail: 'ASSISTED',
      mode: 'ASSISTED',
      method: 'BOLETO',
      amount: Money.of(12345),
      outcome: 'FAILED',
      reason: 'test',
      externalId: null,
      idempotencyKey: 'k',
      at: NOW,
    })
    const later = await attempted.run({ pixCode: PIX_OF_BOLETO })
    expect(later).toMatchObject({ duplicate: true, bill: { pixCode: null } })
  })

  it('does not merge codes whose amounts differ', async () => {
    const { run } = setup()
    const pix = await run({ pixCode: PIX_NO_AMOUNT, amountCents: 900 })
    const again = await run({ pixCode: PIX_NO_AMOUNT, amountCents: 1000 })
    expect(again).toEqual({ bill: pix.bill, duplicate: true })
  })
})
