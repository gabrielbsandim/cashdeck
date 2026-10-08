import { type LocalDate } from '@/calendar/local-date'
import { decodeArrecadacao, type DecodedArrecadacao } from '@/codes/arrecadacao'
import { decodeBoleto, type DecodedBoleto } from '@/codes/boleto'
import { type BrCode, parseBrCode } from '@/codes/br-code'
import { ValidationError } from '@/shared/domain-error'

export type DecodedPaymentCode = DecodedBoleto | DecodedArrecadacao | BrCode

export function decodePaymentCode(
  raw: string,
  reference: LocalDate,
): DecodedPaymentCode {
  const trimmed = raw.trim()
  if (trimmed.startsWith('000201')) {
    return parseBrCode(trimmed)
  }
  const digits = trimmed.replace(/[\s.-]/g, '')
  if (!/^\d+$/.test(digits)) {
    throw new ValidationError(
      'Payment code must be a barcode, a digitable line or a Pix code.',
    )
  }
  const isArrecadacao = digits.startsWith('8')
  if (isArrecadacao && (digits.length === 44 || digits.length === 48)) {
    return decodeArrecadacao(digits)
  }
  if (!isArrecadacao && (digits.length === 44 || digits.length === 47)) {
    return decodeBoleto(digits, reference)
  }
  throw new ValidationError('Payment code has an unexpected length.')
}
