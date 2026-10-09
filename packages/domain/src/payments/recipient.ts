import { type Bill } from '@/bills/bill'
import { parseBrCode } from '@/codes/br-code'
import { decodePaymentCode } from '@/codes/payment-code'

// Normalised so the same key typed with or without punctuation or accents maps
// to one recipient; an EVP or e-mail key only loses case and spaces.
export function normalizePixKey(key: string): string {
  const trimmed = key.trim().toLowerCase()
  if (!/^\+?[\d.\-/()\s]+$/.test(trimmed)) {
    return trimmed.replace(/\s/g, '')
  }
  const sign = trimmed.startsWith('+') ? '+' : ''
  return sign + trimmed.replace(/\D/g, '')
}

export function normalizeName(name: string): string {
  return name
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .toUpperCase()
    .replace(/\s+/g, ' ')
    .trim()
}

function pixPayloadOf(bill: Bill): string | null {
  if (bill.pixCode) {
    return bill.pixCode
  }
  return bill.kind === 'PIX_QR' ? bill.code : null
}

// A static code names the Pix key; a dynamic one only names the merchant, as
// its key sits behind the location URL.
function pixRecipient(bill: Bill): string | null {
  if (bill.kind === 'PIX_KEY' && bill.code) {
    return `pix:${normalizePixKey(bill.code)}`
  }
  const payload = pixPayloadOf(bill)
  if (!payload) {
    return null
  }
  const code = parseBrCode(payload)
  if (code.key) {
    return `pix:${normalizePixKey(code.key)}`
  }
  const merchant = normalizeName(code.merchantName)
  return `pix-merchant:${merchant}:${normalizeName(code.merchantCity)}`
}

// A barcode carries no beneficiary document: a boleto is keyed by its bank and
// payee name, or by the whole code when the payee is unknown, so it always asks.
function barcodeRecipient(bill: Bill): string | null {
  if (!bill.code || bill.kind === 'PIX_KEY' || bill.kind === 'PIX_QR') {
    return null
  }
  const decoded = decodePaymentCode(bill.code, bill.dueDate)
  switch (decoded.type) {
    case 'ARRECADACAO':
      return `collector:${decoded.barcode.charAt(1)}:${decoded.barcode.slice(15, 19)}`
    case 'BOLETO': {
      const payee = bill.payee ? normalizeName(bill.payee) : ''
      const tail = payee === '' ? `code:${decoded.barcode}` : payee
      return `boleto:${decoded.bankCode}:${tail}`
    }
    case 'PIX':
      return null
  }
}

function readableRecipients(bill: Bill): Array<string | null> {
  try {
    return [pixRecipient(bill), barcodeRecipient(bill)]
  } catch {
    return [`unreadable:${bill.id}`]
  }
}

// Every recipient the bill could pay: a bolepix names both its Pix key and its
// beneficiary, and each one has to be known before paying without asking.
export function recipientKeys(bill: Bill): string[] {
  const keys = readableRecipients(bill).filter(
    (key): key is string => key !== null,
  )
  if (keys.length > 0) {
    return keys
  }
  const payee = bill.payee ? normalizeName(bill.payee) : bill.id
  return [`${bill.kind.toLowerCase()}:${payee}`]
}
