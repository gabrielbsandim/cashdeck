import { mod10, mod11Arrecadacao } from '@/codes/check-digits'
import { Money } from '@/money/money'
import { ValidationError } from '@/shared/domain-error'

export const ARRECADACAO_SEGMENTS = {
  '1': 'CITY_HALL',
  '2': 'SANITATION',
  '3': 'ENERGY_AND_GAS',
  '4': 'TELECOM',
  '5': 'GOVERNMENT',
  '6': 'MERCHANT',
  '7': 'TRAFFIC_FINE',
  '9': 'BANK',
} as const

export type ArrecadacaoSegment =
  (typeof ARRECADACAO_SEGMENTS)[keyof typeof ARRECADACAO_SEGMENTS]

export type DecodedArrecadacao = {
  readonly type: 'ARRECADACAO'
  readonly barcode: string
  readonly digitableLine: string
  readonly segment: ArrecadacaoSegment
  readonly isTaxGuide: boolean
  readonly amount: Money | null
}

function checkDigitFor(barcode: string): (digits: string) => number {
  const indicator = barcode.charAt(2)
  if (indicator === '6' || indicator === '7') {
    return mod10
  }
  if (indicator === '8' || indicator === '9') {
    return mod11Arrecadacao
  }
  throw new ValidationError('Unknown value indicator in the barcode.')
}

function blocks(barcode: string): string[] {
  return [0, 11, 22, 33].map(start => barcode.slice(start, start + 11))
}

function barcodeFromLine(line: string): string {
  const parts = [0, 12, 24, 36].map(start => line.slice(start, start + 12))
  const barcode = parts.map(part => part.slice(0, 11)).join('')
  const checkDigit = checkDigitFor(barcode)
  for (const part of parts) {
    if (checkDigit(part.slice(0, 11)) !== Number(part.charAt(11))) {
      throw new ValidationError('Digitable line check digit does not match.')
    }
  }
  return barcode
}

export function decodeArrecadacao(digits: string): DecodedArrecadacao {
  const barcode = digits.length === 48 ? barcodeFromLine(digits) : digits
  const checkDigit = checkDigitFor(barcode)
  if (
    checkDigit(barcode.slice(0, 3) + barcode.slice(4)) !==
    Number(barcode.charAt(3))
  ) {
    throw new ValidationError('Barcode check digit does not match.')
  }
  const segment =
    ARRECADACAO_SEGMENTS[barcode.charAt(1) as keyof typeof ARRECADACAO_SEGMENTS]
  if (!segment) {
    throw new ValidationError('Unknown segment in the barcode.')
  }
  const isEffectiveValue = ['6', '8'].includes(barcode.charAt(2))
  const cents = Number(barcode.slice(4, 15))
  return {
    type: 'ARRECADACAO',
    barcode,
    digitableLine: blocks(barcode)
      .map(block => block + checkDigit(block))
      .join(''),
    segment,
    isTaxGuide: segment === 'GOVERNMENT',
    amount: isEffectiveValue && cents > 0 ? Money.of(cents) : null,
  }
}
