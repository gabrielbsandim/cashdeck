import { type LocalDate } from '@/calendar/local-date'
import { type DecodedPaymentCode } from '@/codes/payment-code'
import { type Money } from '@/money/money'
import { InvalidTransitionError, ValidationError } from '@/shared/domain-error'

export const BILL_KINDS = [
  'BOLETO',
  'PIX_KEY',
  'PIX_QR',
  'TAX_BARCODE',
  'DARF_NO_BARCODE',
] as const
export type BillKind = (typeof BILL_KINDS)[number]

export const BILL_STATUSES = [
  'OPEN',
  'NEEDS_CONFIRMATION',
  'PROCESSING',
  'AWAITING_BANK_APPROVAL',
  'ASSISTED',
  'PAID',
  'CANCELLED',
] as const
export type BillStatus = (typeof BILL_STATUSES)[number]

export const BILL_SOURCES = [
  'GMAIL',
  'SHARE',
  'CAMERA',
  'CHAT',
  'DDA',
  'MANUAL',
] as const
export type BillSource = (typeof BILL_SOURCES)[number]

export type PaidBy = 'RAIL' | 'USER'

export type Bill = {
  readonly id: string
  readonly tenantId: string
  readonly entityId: string
  readonly kind: BillKind
  readonly status: BillStatus
  readonly source: BillSource
  readonly payee: string | null
  readonly amount: Money
  readonly dueDate: LocalDate
  readonly code: string | null
  readonly createdAt: Date
  readonly paidAt: Date | null
  readonly paidBy: PaidBy | null
}

export type CreateBillInput = Omit<
  Bill,
  'status' | 'paidAt' | 'paidBy' | 'payee' | 'code'
> & {
  payee?: string | null
  code?: string | null
}

export function createBill(input: CreateBillInput): Bill {
  if (!input.amount.isPositive()) {
    throw new ValidationError('A bill amount must be positive.')
  }
  const code = input.code?.trim() || null
  if (code === null && input.kind !== 'DARF_NO_BARCODE') {
    throw new ValidationError(`A ${input.kind} bill needs its payment code.`)
  }
  return {
    ...input,
    payee: input.payee?.trim() || null,
    code,
    status: 'OPEN',
    paidAt: null,
    paidBy: null,
  }
}

export function billKindFor(decoded: DecodedPaymentCode): BillKind {
  switch (decoded.type) {
    case 'PIX':
      return 'PIX_QR'
    case 'ARRECADACAO':
      return decoded.isTaxGuide ? 'TAX_BARCODE' : 'BOLETO'
    case 'BOLETO':
      return 'BOLETO'
  }
}

const TRANSITIONS: Record<BillStatus, readonly BillStatus[]> = {
  OPEN: [
    'NEEDS_CONFIRMATION',
    'PROCESSING',
    'AWAITING_BANK_APPROVAL',
    'ASSISTED',
    'PAID',
    'CANCELLED',
  ],
  NEEDS_CONFIRMATION: ['OPEN', 'ASSISTED', 'PAID', 'CANCELLED'],
  PROCESSING: ['PAID', 'OPEN', 'AWAITING_BANK_APPROVAL', 'ASSISTED'],
  AWAITING_BANK_APPROVAL: ['PAID', 'OPEN', 'PROCESSING', 'ASSISTED'],
  ASSISTED: ['PAID', 'CANCELLED'],
  PAID: [],
  CANCELLED: [],
}

export function canTransition(from: BillStatus, to: BillStatus): boolean {
  return TRANSITIONS[from].includes(to)
}

export function transitionBill(bill: Bill, to: BillStatus): Bill {
  if (bill.status === to) {
    return bill
  }
  if (!canTransition(bill.status, to)) {
    throw new InvalidTransitionError('Bill', bill.status, to)
  }
  return { ...bill, status: to }
}

export function markBillPaid(bill: Bill, by: PaidBy, at: Date): Bill {
  return { ...transitionBill(bill, 'PAID'), paidAt: at, paidBy: by }
}

export function isSettled(bill: Bill): boolean {
  return bill.status === 'PAID' || bill.status === 'CANCELLED'
}
