import { type Bill } from '@/bills/bill'
import { boletoBeneficiary, type DecodedBoleto } from '@/codes/boleto'
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

// The beneficiary account in the barcode is what a forged e-mail cannot copy,
// so it keys the boleto; the payee name stays beside it, as keys stored before.
function boletoRecipients(bill: Bill, decoded: DecodedBoleto): string[] {
  const { bankCode, barcode } = decoded
  const payee = bill.payee ? normalizeName(bill.payee) : ''
  const byCode = `boleto:${bankCode}:code:${barcode}`
  const byName = payee === '' ? [] : [`boleto:${bankCode}:${payee}`]
  const account = boletoBeneficiary(barcode)
  if (account !== null) {
    return [`boleto:${bankCode}:account:${account}`, ...byName]
  }
  if (byName.length === 0) {
    return [byCode]
  }
  // An e-mail can print any name, and with no account to read its boleto asks.
  return bill.source === 'GMAIL' ? [...byName, byCode] : byName
}

function barcodeRecipients(bill: Bill): string[] {
  if (!bill.code || bill.kind === 'PIX_KEY' || bill.kind === 'PIX_QR') {
    return []
  }
  const decoded = decodePaymentCode(bill.code, bill.dueDate)
  switch (decoded.type) {
    case 'ARRECADACAO':
      return [
        `collector:${decoded.barcode.charAt(1)}:${decoded.barcode.slice(15, 19)}`,
      ]
    case 'BOLETO':
      return boletoRecipients(bill, decoded)
    case 'PIX':
      return []
  }
}

function readableRecipients(bill: Bill): Array<string | null> {
  try {
    return [pixRecipient(bill), ...barcodeRecipients(bill)]
  } catch {
    return [`unreadable:${bill.id}`]
  }
}

// Every recipient the bill could pay: a bolepix names both its Pix key and its
// beneficiary, and each one has to be known before paying without asking.
export function recipientKeys(bill: Bill): string[] {
  if (bill.unverifiedSender) {
    return [`unverified:${bill.id}`]
  }
  const keys = readableRecipients(bill).filter(
    (key): key is string => key !== null,
  )
  if (keys.length > 0) {
    return keys
  }
  const payee = bill.payee ? normalizeName(bill.payee) : bill.id
  return [`${bill.kind.toLowerCase()}:${payee}`]
}
