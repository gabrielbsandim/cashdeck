import {
  type Bill,
  type BrCode,
  type PaymentMethod,
  parseBrCode,
  ValidationError,
} from '@cashdeck/domain'

// A BOLETO step on a bolepix pays the barcode: the Pix step already ran.
export function pixPayloadOf(bill: Bill, method: PaymentMethod): string | null {
  if (method !== 'PIX') {
    return null
  }
  const extra = bill.pixCode?.trim()
  if (extra) {
    return extra
  }
  return bill.kind === 'PIX_QR' ? bill.code : null
}

export type PixKeyType = 'CPF' | 'CNPJ' | 'EMAIL' | 'PHONE' | 'EVP'

const EVP = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const KEY_RULES: Array<[PixKeyType, (key: string) => boolean]> = [
  ['EVP', key => EVP.test(key)],
  ['EMAIL', key => key.includes('@')],
  ['PHONE', key => /^\+\d{12,13}$/.test(key)],
  ['CPF', key => /^\d{11}$/.test(key.replace(/[.-]/g, ''))],
  ['CNPJ', key => /^\d{14}$/.test(key.replace(/[./-]/g, ''))],
]

export function pixKeyType(key: string): PixKeyType {
  const rule = KEY_RULES.find(([, matches]) => matches(key.trim()))
  if (!rule) {
    throw new ValidationError(`"${key}" is not a Pix key.`)
  }
  return rule[0]
}

export function normalizePixKey(key: string): string {
  const trimmed = key.trim()
  const type = pixKeyType(trimmed)
  return type === 'CPF' || type === 'CNPJ'
    ? trimmed.replace(/\D/g, '')
    : trimmed
}

export type DecodedPix = {
  payload: string
  code: BrCode
  dynamic: boolean
}

export function decodePix(payload: string): DecodedPix {
  const code = parseBrCode(payload)
  return { payload: code.payload, code, dynamic: code.url !== null }
}

// A static code with a printed amount must match the bill, or the bill was
// captured wrong; a dynamic code is priced by its location, so the rail checks.
export function staticAmountMismatch(pix: DecodedPix, bill: Bill): boolean {
  if (pix.dynamic || pix.code.amount === null) {
    return false
  }
  return pix.code.amount.cents !== bill.amount.cents
}

export function paymentDescription(bill: Bill): string {
  return (bill.payee ?? 'Cashdeck').slice(0, 140)
}
