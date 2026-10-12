import { nextBusinessDay } from '@/calendar/business-days'
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

// A due date on a weekend or holiday is debited on the next business day; one
// left open past that was debited after the statement was issued.
export function debitOn(installment: LoanInstallment): LocalDate {
  return nextBusinessDay(installment.dueOn)
}

export function isOpen(installment: LoanInstallment, today: LocalDate) {
  return installment.paidOn === null && debitOn(installment) >= today
}

// Still owed at the end of a day: paid after it, or with no payment recorded
// and not yet debited before it.
const owedAfter = (installment: LoanInstallment, day: LocalDate) =>
  installment.paidOn === null
    ? debitOn(installment) >= day
    : installment.paidOn > day

export function loanBalanceOn(loan: LoanStatement, day: LocalDate): number {
  if (day < loan.signedOn) {
    return 0
  }
  const next = loan.installments.find(installment =>
    owedAfter(installment, day),
  )
  return next ? owedBefore(next) : 0
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

// The monthly rate whose yearly compounding is the effective rate.
export function monthlyRate(effectiveRate: number) {
  return (1 + effectiveRate / 100) ** (1 / 12) - 1
}

const sum = (
  installments: readonly LoanInstallment[],
  pick: (installment: LoanInstallment) => number,
) => installments.reduce((total, installment) => total + pick(installment), 0)

type Kept = { readonly count: number; readonly interestSaved: number }

// SAC keeps the amortization fixed, so paying `amount` now lowers every later
// balance by it and drops the installments it covers from the end.
function sacKept(open: readonly LoanInstallment[], amount: number): Kept {
  const kept = open.filter(installment => owedBefore(installment) > amount)
  const cut = open.slice(kept.length)
  const keptSaving = sum(kept, installment =>
    Math.round((installment.interest * amount) / owedBefore(installment)),
  )
  return {
    count: kept.length,
    interestSaved: keptSaving + sum(cut, installment => installment.interest),
  }
}

// Price keeps the installment, so the smaller balance is paid off sooner.
function priceKept(
  open: readonly LoanInstallment[],
  owed: number,
  rate: number,
): Kept {
  const installment = (open[0]?.principal ?? 0) + (open[0]?.interest ?? 0)
  let left = owed
  let interest = 0
  let count = 0
  while (left > 0 && count < open.length) {
    const due = Math.round(left * rate)
    interest += due
    left -= installment - due
    count += 1
  }
  return {
    count,
    interestSaved: sum(open, installment => installment.interest) - interest,
  }
}

export function prepayment(
  loan: LoanStatement,
  today: LocalDate,
  amount: number,
): Prepayment {
  if (amount <= 0) {
    throw new ValidationError('The amount must be positive.')
  }
  const { open, balance } = loanStanding(loan, today)
  const kept =
    loan.system === 'SAC'
      ? sacKept(open, amount)
      : priceKept(open, balance - amount, monthlyRate(loan.effectiveRate))
  return {
    amount,
    interestSaved: kept.interestSaved,
    feesSaved: sum(open.slice(kept.count), installment => installment.fees),
    monthsCut: open.length - kept.count,
    lastDueOn: open[kept.count - 1]?.dueOn ?? null,
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
