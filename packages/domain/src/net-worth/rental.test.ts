import { describe, expect, it } from 'vitest'
import {
  isRentalBill,
  plainText,
  type Rental,
  rentCharge,
  rentReceived,
} from '@/net-worth/rental'

const rental: Rental = {
  rent: 160000,
  passThrough: ['gás'],
  billFrom: 'Jardim Azul',
}

const lines = [
  { description: 'Taxas de condomínio 10/2026', cents: 41020 },
  { description: 'Fundo de reserva 10/2026', cents: 2051 },
  { description: 'Consumo de GAS 10/2026', cents: 9870 },
  { description: 'Rateio segurança 06/30', cents: 5000 },
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
    expect(rentCharge(rental, lines, 57941)).toEqual({
      passedOn: [lines[2]],
      total: 169870,
      ownerCost: 48071,
    })
  })

  it('asks for the rent alone when no line matches', () => {
    const none = { ...rental, passThrough: ['água', ' '] }
    expect(rentCharge(none, lines, 57941)).toEqual({
      passedOn: [],
      total: 160000,
      ownerCost: 57941,
    })
  })
})

describe('rentReceived', () => {
  it('takes the credit of the exact charge closest to the due date', () => {
    const credits = [
      { bookedOn: '2026-09-14', cents: 169870 },
      { bookedOn: '2026-10-05', cents: 169870 },
      { bookedOn: '2026-10-09', cents: 169800 },
      { bookedOn: '2026-10-16', cents: 169870 },
    ]
    expect(rentReceived(169870, '2026-10-10', credits)).toEqual({
      bookedOn: '2026-10-05',
      cents: 169870,
    })
    expect(rentReceived(169870, '2026-12-10', credits)).toBeNull()
  })
})
