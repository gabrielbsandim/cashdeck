import { describe, expect, it } from 'vitest'
import {
  isRentalBill,
  plainText,
  type Rental,
  rentCharge,
} from '@/net-worth/rental'

const rental: Rental = {
  rent: 160000,
  passThrough: ['gás'],
  billFrom: 'Jardim Azul',
}

const lines = [
  { description: 'Taxas de condomínio 10/2026', cents: 37278 },
  { description: 'Fundo de reserva 10/2026', cents: 1863 },
  { description: 'Consumo de GAS 10/2026', cents: 13665 },
  { description: 'Rateio segurança 06/30', cents: 6963 },
]

describe('plainText', () => {
  it('drops accents, case and extra spaces', () => {
    expect(plainText('  Condomínio   Jardim  ')).toBe('CONDOMINIO JARDIM')
  })
})

describe('isRentalBill', () => {
  it('matches the building in the payee, whatever the accents', () => {
    expect(isRentalBill(rental, 'CONDOMÍNIO RESIDENCIAL JARDIM AZUL')).toBe(
      true,
    )
    expect(isRentalBill(rental, 'Residencial Jardim Verde')).toBe(false)
    expect(isRentalBill(rental, null)).toBe(false)
  })

  it('matches nothing when the building is blank', () => {
    expect(isRentalBill({ ...rental, billFrom: ' ' }, 'Jardim Azul')).toBe(
      false,
    )
  })
})

describe('rentCharge', () => {
  it('adds the lines the tenant pays to the rent', () => {
    expect(rentCharge(rental, lines, 59769)).toEqual({
      passedOn: [lines[2]],
      total: 173665,
      ownerCost: 46104,
    })
  })

  it('asks for the rent alone when no line matches', () => {
    const none = { ...rental, passThrough: ['água', ' '] }
    expect(rentCharge(none, lines, 59769)).toEqual({
      passedOn: [],
      total: 160000,
      ownerCost: 59769,
    })
  })
})
