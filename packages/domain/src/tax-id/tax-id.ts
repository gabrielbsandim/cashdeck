import { ValidationError } from '@/shared/domain-error'

export type TaxIdKind = 'CPF' | 'CNPJ'

const CNPJ_FIRST_WEIGHTS = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
const CNPJ_SECOND_WEIGHTS = [6, ...CNPJ_FIRST_WEIGHTS]

function cpfCheckDigit(body: string): number {
  const start = body.length + 1
  const sum = [...body].reduce(
    (total, char, index) => total + Number(char) * (start - index),
    0,
  )
  const rest = (sum * 10) % 11
  return rest === 10 ? 0 : rest
}

// Alphanumeric CNPJs (issued from July 2026) weigh each character by its ASCII
// code minus 48, which keeps the classic numeric CNPJ result unchanged.
function cnpjCheckDigit(body: string, weights: number[]): number {
  const sum = [...body].reduce(
    (total, char, index) =>
      total + (char.charCodeAt(0) - 48) * (weights[index] as number),
    0,
  )
  const rest = sum % 11
  return rest < 2 ? 0 : 11 - rest
}

function isValidCpf(value: string): boolean {
  if (!/^\d{11}$/.test(value) || /^(\d)\1{10}$/.test(value)) {
    return false
  }
  const first = cpfCheckDigit(value.slice(0, 9))
  const second = cpfCheckDigit(value.slice(0, 10))
  return value.endsWith(`${first}${second}`)
}

function isValidCnpj(value: string): boolean {
  if (!/^[0-9A-Z]{12}\d{2}$/.test(value) || /^(\d)\1{13}$/.test(value)) {
    return false
  }
  const first = cnpjCheckDigit(value.slice(0, 12), CNPJ_FIRST_WEIGHTS)
  const second = cnpjCheckDigit(value.slice(0, 13), CNPJ_SECOND_WEIGHTS)
  return value.endsWith(`${first}${second}`)
}

export class TaxId {
  private constructor(
    readonly kind: TaxIdKind,
    readonly value: string,
  ) {}

  static parse(raw: string): TaxId {
    const value = raw.toUpperCase().replace(/[\s./-]/g, '')
    if (isValidCpf(value)) {
      return new TaxId('CPF', value)
    }
    if (isValidCnpj(value)) {
      return new TaxId('CNPJ', value)
    }
    throw new ValidationError('Tax id is not a valid CPF or CNPJ.')
  }

  format(): string {
    if (this.kind === 'CPF') {
      return this.value.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, '$1.$2.$3-$4')
    }
    return this.value.replace(
      /^(\w{2})(\w{3})(\w{3})(\w{4})(\d{2})$/,
      '$1.$2.$3/$4-$5',
    )
  }

  equals(other: TaxId): boolean {
    return this.value === other.value
  }

  toString(): string {
    return this.value
  }
}

// A CNPJ or CPF printed in a document, formatted or not, but never a slice of
// a longer digit run such as a barcode.
const PRINTED_TAX_ID =
  /(?<!\d)(?:\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}|\d{3}\.?\d{3}\.?\d{3}-?\d{2})(?!\d)/g

export function findTaxIds(text: string): string[] {
  const found = new Set<string>()
  for (const [printed] of text.matchAll(PRINTED_TAX_ID)) {
    const value = printed.replace(/\D/g, '')
    if (isValidCpf(value) || isValidCnpj(value)) {
      found.add(value)
    }
  }
  return [...found]
}
