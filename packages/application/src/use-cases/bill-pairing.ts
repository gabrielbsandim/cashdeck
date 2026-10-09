import {
  type Bill,
  type BillKind,
  type LocalDate,
  type Money,
  parseBrCode,
} from '@cashdeck/domain'

// What one capture knows about a bill before it is stored or matched.
export type IncomingBill = {
  kind: BillKind
  code: string | null
  pixCode: string | null
  location: string | null
  amount: Money | null
  // Only a due date read from a code, the charge or the client, never today.
  dueDate: LocalDate | null
  payee: string | null
}

const MIN_NAME_LENGTH = 4

const isBarcodeKind = (kind: BillKind) =>
  kind === 'BOLETO' || kind === 'TAX_BARCODE'

function normalized(name: string | null): string {
  return (name ?? '')
    .normalize('NFD')
    .replace(/[^A-Za-z0-9]/g, '')
    .toUpperCase()
}

// A BR Code cuts the merchant name at 25 characters, so a prefix matches.
export function samePayee(a: string | null, b: string | null): boolean {
  const left = normalized(a)
  const right = normalized(b)
  if (left.length < MIN_NAME_LENGTH || right.length < MIN_NAME_LENGTH) {
    return false
  }
  return left.startsWith(right) || right.startsWith(left)
}

function locationOf(pixCode: string | null): string | null {
  return pixCode === null ? null : parseBrCode(pixCode).url
}

// Two dynamic codes of one charge differ in their bytes but share a location.
export function sameLocation(stored: Bill, incoming: IncomingBill): boolean {
  return (
    incoming.location !== null &&
    locationOf(stored.pixCode) === incoming.location
  )
}

function sameCharge(stored: Bill, incoming: IncomingBill): boolean {
  return (
    stored.dueDate === incoming.dueDate ||
    samePayee(stored.payee, incoming.payee)
  )
}

// The stored bill holds the other half of a bolepix: a barcode waiting for its
// Pix code, or a Pix QR bill waiting for its barcode.
export function completesHalf(stored: Bill, incoming: IncomingBill): boolean {
  if (!sameCharge(stored, incoming)) {
    return false
  }
  if (incoming.kind === 'PIX_QR') {
    return isBarcodeKind(stored.kind) && stored.pixCode === null
  }
  return (
    isBarcodeKind(incoming.kind) &&
    incoming.pixCode === null &&
    stored.kind === 'PIX_QR'
  )
}

function amountsAgree(stored: Bill, incoming: IncomingBill): boolean {
  return incoming.amount === null || incoming.amount.equals(stored.amount)
}

// The stored bill with the half it lacks, or null when there is nothing to add.
export function withMissingHalf(
  stored: Bill,
  incoming: IncomingBill,
): Bill | null {
  if (!amountsAgree(stored, incoming)) {
    return null
  }
  if (stored.pixCode === null && incoming.pixCode !== null) {
    return {
      ...stored,
      pixCode: incoming.pixCode,
      payee: stored.payee ?? incoming.payee,
    }
  }
  if (stored.kind !== 'PIX_QR' || !isBarcodeKind(incoming.kind)) {
    return null
  }
  return {
    ...stored,
    kind: incoming.kind,
    code: incoming.code,
    dueDate: incoming.dueDate ?? stored.dueDate,
  }
}
