import { type LocalDate } from '@/calendar/local-date'
import { ValidationError } from '@/shared/domain-error'

export const AMORTIZATION_SYSTEMS = ['SAC', 'PRICE'] as const
export type AmortizationSystem = (typeof AMORTIZATION_SYSTEMS)[number]

// Amounts in cents, so a loan is stored and read back as plain JSON.
export type LoanInstallment = {
  readonly number: number
  readonly dueOn: LocalDate
  readonly total: number
  readonly principal: number
  readonly interest: number
  // Insurance and the bank's admin fee.
  readonly fees: number
  // Fine and late interest charged when it was paid after the due date.
  readonly lateFees: number
  // What is owed once it is paid.
  readonly balance: number
  readonly paidOn: LocalDate | null
  readonly paid: number | null
}

export type LoanStatement = {
  readonly lender: string
  readonly contract: string
  readonly system: AmortizationSystem
  readonly indexer: string
  // Percent a year.
  readonly effectiveRate: number
  readonly cet: number
  readonly principal: number
  readonly propertyValue: number | null
  readonly signedOn: LocalDate
  readonly termMonths: number
  readonly installments: readonly LoanInstallment[]
}

export type LoanTotals = {
  readonly count: number
  readonly total: number
  readonly interest: number
  readonly principal: number
  readonly fees: number
  readonly lateFees: number
}

export type LoanStanding = {
  readonly balance: number
  readonly paid: LoanTotals
  readonly remaining: LoanTotals
  readonly open: readonly LoanInstallment[]
  readonly lastDueOn: LocalDate | null
}

export type Prepayment = {
  readonly amount: number
  readonly interestSaved: number
  readonly feesSaved: number
  readonly monthsCut: number
  readonly lastDueOn: LocalDate | null
  readonly balanceAfter: number
}

const totalsOf = (
  installments: readonly LoanInstallment[],
  charged: (installment: LoanInstallment) => number,
): LoanTotals => {
  const add = (pick: (installment: LoanInstallment) => number) =>
    installments.reduce((sum, installment) => sum + pick(installment), 0)
  return {
    count: installments.length,
    total: add(charged),
    interest: add(installment => installment.interest),
    principal: add(installment => installment.principal),
    fees: add(installment => installment.fees),
    lateFees: add(installment => installment.lateFees),
  }
}

const owedBefore = (installment: LoanInstallment) =>
  installment.balance + installment.principal

// A past due installment the statement still shows open was debited after it
// was issued; the bank debits it by itself.
export function isOpen(installment: LoanInstallment, today: LocalDate) {
  return installment.paidOn === null && installment.dueOn >= today
}

export function loanStanding(
  loan: LoanStatement,
  today: LocalDate,
): LoanStanding {
  const open = loan.installments.filter(installment =>
    isOpen(installment, today),
  )
  const settled = loan.installments.filter(
    installment => !isOpen(installment, today),
  )
  const next = open[0]
  return {
    balance: next ? owedBefore(next) : 0,
    paid: totalsOf(
      settled,
      installment => installment.paid ?? installment.total,
    ),
    remaining: totalsOf(open, installment => installment.total),
    open,
    lastDueOn: loan.installments.at(-1)?.dueOn ?? null,
  }
}

// SAC keeps the amortization fixed, so paying `amount` now lowers every later
// balance by it and drops the installments it covers from the end.
export function prepayment(
  loan: LoanStatement,
  today: LocalDate,
  amount: number,
): Prepayment {
  if (loan.system !== 'SAC') {
    throw new ValidationError('Only SAC loans can be simulated.')
  }
  if (amount <= 0) {
    throw new ValidationError('The amount must be positive.')
  }
  const { open, balance } = loanStanding(loan, today)
  const cut = open.filter(installment => owedBefore(installment) <= amount)
  const kept = open.filter(installment => owedBefore(installment) > amount)
  const keptSaving = kept.reduce(
    (sum, installment) =>
      sum +
      Math.round((installment.interest * amount) / owedBefore(installment)),
    0,
  )
  return {
    amount,
    interestSaved:
      keptSaving +
      cut.reduce((sum, installment) => sum + installment.interest, 0),
    feesSaved: cut.reduce((sum, installment) => sum + installment.fees, 0),
    monthsCut: cut.length,
    lastDueOn: kept.at(-1)?.dueOn ?? null,
    balanceAfter: Math.max(0, balance - amount),
  }
}

// Whether a debit of these cents paid, or will pay, one of its installments.
export function chargesInstallment(loan: LoanStatement, cents: number) {
  return loan.installments.some(
    installment => installment.total === cents || installment.paid === cents,
  )
}

export function installmentIn(
  loan: LoanStatement,
  month: string,
): LoanInstallment | null {
  return (
    loan.installments.find(installment =>
      installment.dueOn.startsWith(month),
    ) ?? null
  )
}
