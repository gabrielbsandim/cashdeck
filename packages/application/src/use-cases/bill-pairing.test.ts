import { describe, expect, it } from 'vitest'
import { encodeBrCode, Money } from '@cashdeck/domain'
import { bill } from '@/testing/deps.test-helpers'
import {
  type IncomingBill,
  sameLocation,
  samePayee,
  withMissingHalf,
} from '@/use-cases/bill-pairing'

const PIX = encodeBrCode({
  key: 'k@example.com',
  merchantName: 'Supplier',
  merchantCity: 'City',
})

const incoming = (overrides: Partial<IncomingBill> = {}): IncomingBill => ({
  kind: 'PIX_QR',
  code: PIX,
  pixCode: PIX,
  location: null,
  amount: null,
  dueDate: null,
  payee: null,
  ...overrides,
})

describe('samePayee', () => {
  it('matches names that differ in case, accents, punctuation or truncation', () => {
    expect(
      samePayee('Condomínio Edifício Exemplo', 'CONDOMINIO EDIFICIO EXE'),
    ).toBe(true)
    expect(samePayee('ACME', 'Acme Servicos S.A.')).toBe(true)
  })

  it('refuses short, missing or different names', () => {
    expect(samePayee('Ab', 'Ab')).toBe(false)
    expect(samePayee(null, 'Acme')).toBe(false)
    expect(samePayee('Acme', 'Other Company')).toBe(false)
  })
})

describe('sameLocation', () => {
  it('never matches a stored bill without a Pix code', () => {
    expect(
      sameLocation(
        bill({ id: 'b1' }),
        incoming({ location: 'pix.example.com/x' }),
      ),
    ).toBe(false)
  })
})

describe('withMissingHalf', () => {
  it('takes the incoming payee when the stored bill has none', () => {
    const merged = withMissingHalf(
      bill({ id: 'b1', payee: null }),
      incoming({ payee: 'Supplier', amount: Money.of(12345) }),
    )
    expect(merged).toMatchObject({ pixCode: PIX, payee: 'Supplier' })
  })

  it('keeps the stored due date when the barcode carries none', () => {
    const stored = bill({ id: 'b1', kind: 'PIX_QR', code: PIX, pixCode: PIX })
    const merged = withMissingHalf(
      stored,
      incoming({ kind: 'TAX_BARCODE', code: '858', pixCode: null }),
    )
    expect(merged).toMatchObject({
      kind: 'TAX_BARCODE',
      code: '858',
      dueDate: stored.dueDate,
    })
  })
})
