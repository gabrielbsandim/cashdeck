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

function assertBarcode(barcode: string): void {
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
