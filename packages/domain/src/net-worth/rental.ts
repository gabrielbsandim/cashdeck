// Amounts in cents. The tenant pays the rent plus the lines of the building's
// bill that are theirs to pay, like the gas they used.
export type Rental = {
  readonly rent: number
  // Words that pick those lines out of the bill, like "gas".
  readonly passThrough: readonly string[]
  // Words in the payee of the building's bill, like the building's name.
  readonly billFrom: string
}

export type BillLine = { readonly description: string; readonly cents: number }

export type RentCharge = {
  readonly passedOn: readonly BillLine[]
  // What to ask the tenant for.
  readonly total: number
  // What stays with the owner: the bill less what the tenant pays back.
  readonly ownerCost: number
}

// "Consumo de gás" and "GAS" are the same line.
export const plainText = (text: string) =>
  text
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toUpperCase()
    .replace(/\s+/g, ' ')
    .trim()

export function isRentalBill(rental: Rental, payee: string | null): boolean {
  const building = plainText(rental.billFrom)
  return building.length > 0 && plainText(payee ?? '').includes(building)
}

export function rentCharge(
  rental: Rental,
  lines: readonly BillLine[],
  billTotal: number,
): RentCharge {
  const words = rental.passThrough.map(plainText).filter(Boolean)
  const passedOn = lines.filter(line =>
    words.some(word => plainText(line.description).includes(word)),
  )
  const passed = passedOn.reduce((sum, line) => sum + line.cents, 0)
  return {
    passedOn,
    total: rental.rent + passed,
    ownerCost: billTotal - passed,
  }
}
