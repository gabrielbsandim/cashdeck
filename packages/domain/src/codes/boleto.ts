import { addDays, daysBetween, type LocalDate } from '@/calendar/local-date'
import { mod10, mod11Boleto } from '@/codes/check-digits'
import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

export type DecodedBoleto = {
  readonly type: 'BOLETO'
  readonly barcode: string
  readonly digitableLine: string
  readonly bankCode: string
  readonly amount: Money | null
  readonly dueDate: LocalDate | null
}

const FIRST_CYCLE_BASE = '1997-10-07'
const SECOND_CYCLE_BASE = '2025-02-22'

// The due date factor wrapped from 9999 back to 1000 on 2025-02-22, so a factor
// maps to two dates; the one closest to the reference date wins.
export function dueDateFromFactor(
  factor: number,
  reference: LocalDate,
): LocalDate | null {
  if (factor === 0) {
    return null
  }
  const candidates = [
    addDays(FIRST_CYCLE_BASE, factor),
    addDays(SECOND_CYCLE_BASE, factor - 1000),
  ]
  const distance = (date: LocalDate) => Math.abs(daysBetween(reference, date))
  return candidates.reduce((best, date) =>
    distance(date) < distance(best) ? date : best,
  )
}

const REAL_CURRENCY = '9'

// An invoice access key is also 44 digits and passes the modulo 11 one time in
// ten, so the currency digit is what tells it apart from a boleto.
function assertBarcode(barcode: string): void {
  if (barcode.charAt(3) !== REAL_CURRENCY) {
    throw new ValidationError('Boleto currency code is not the real.')
  }
  const body = barcode.slice(0, 4) + barcode.slice(5)
  if (mod11Boleto(body) !== Number(barcode.charAt(4))) {
    throw new ValidationError('Boleto barcode check digit does not match.')
  }
}

function lineFromBarcode(barcode: string): string {
  const fields = [
    barcode.slice(0, 4) + barcode.slice(19, 24),
    barcode.slice(24, 34),
    barcode.slice(34, 44),
  ]
  return (
    fields.map(field => field + mod10(field)).join('') +
    barcode.charAt(4) +
    barcode.slice(5, 19)
  )
}

function barcodeFromLine(line: string): string {
  const fields = [line.slice(0, 10), line.slice(10, 21), line.slice(21, 32)]
  for (const field of fields) {
    const body = field.slice(0, -1)
    if (mod10(body) !== Number(field.slice(-1))) {
      throw new ValidationError(
        'Boleto digitable line check digit does not match.',
      )
    }
  }
  return (
    line.slice(0, 4) +
    line.charAt(32) +
    line.slice(33, 47) +
    line.slice(4, 9) +
    line.slice(10, 20) +
    line.slice(21, 31)
  )
}

// Where each bank prints the beneficiary's account in the free field (barcode
// positions 20 to 44); a bank missing here has a layout nobody checked yet.
const BENEFICIARY_LAYOUTS: Record<string, (free: string) => string> = {
  '001': bancoDoBrasilBeneficiary,
  '033': free => free.slice(1, 8),
  '104': free => free.slice(0, 7),
  '237': free => free.slice(0, 4) + free.slice(17, 24),
  '341': free => free.slice(0, 3) + free.slice(12, 21),
  '748': free => free.slice(11, 22),
  '756': free => free.slice(1, 5) + free.slice(7, 14),
}

function bancoDoBrasilBeneficiary(free: string): string {
  if (free.startsWith('000000')) {
    return `c7:${free.slice(6, 13)}`
  }
  if (free.endsWith('21')) {
    return `c6:${free.slice(0, 6)}`
  }
  return `ac:${free.slice(11, 23)}`
}

// The account that receives the money, read from the barcode itself, or null
// when the bank's layout is unknown.
export function boletoBeneficiary(barcode: string): string | null {
  const layout = BENEFICIARY_LAYOUTS[barcode.slice(0, 3)]
  return layout ? layout(barcode.slice(19, 44)) : null
}

export function decodeBoleto(
  digits: string,
  reference: LocalDate,
): DecodedBoleto {
  const barcode = digits.length === 47 ? barcodeFromLine(digits) : digits
  assertBarcode(barcode)
  const cents = Number(barcode.slice(9, 19))
  return {
    type: 'BOLETO',
    barcode,
    digitableLine: lineFromBarcode(barcode),
    bankCode: barcode.slice(0, 3),
    amount: cents > 0 ? Money.of(cents) : null,
    dueDate: dueDateFromFactor(Number(barcode.slice(5, 9)), reference),
  }
}
