import { type LocalDate, shiftMonth } from '@/calendar/local-date'
import {
  type LoanInstallment,
  type LoanStatement,
  monthlyRate,
} from '@/loans/loan'
import { ValidationError } from '@/shared/domain-error'

export type PaidInstallment = {
  readonly number: number
  readonly dueOn: LocalDate
  readonly total: number
  readonly paid: number | null
}

// What a bank app shows when it offers no full schedule: the contract, the
// installments paid, one of them broken down and the balance owed now.
export type LoanTerms = Omit<LoanStatement, 'installments'> & {
  readonly paid: readonly PaidInstallment[]
  readonly reference: {
    readonly number: number
    readonly principal: number
    readonly interest: number
    readonly fees: number
  }
  // Owed before the next installment, already corrected by the indexer.
  readonly balance: number
}

// Paid installments without a breakdown split like the reference one, and the
// rest of the term is projected with the indexer at zero.
export function loanFromTerms(terms: LoanTerms): LoanStatement {
  const paid = [...terms.paid].sort((a, b) => a.number - b.number)
  const last = paid.at(-1)
  if (!last) {
    throw new ValidationError('At least one paid installment is needed.')
  }
  if (
    !paid.some(installment => installment.number === terms.reference.number)
  ) {
    throw new ValidationError('The reference installment must be a paid one.')
  }
  return {
    lender: terms.lender,
    contract: terms.contract,
    system: terms.system,
    indexer: terms.indexer,
    effectiveRate: terms.effectiveRate,
    cet: terms.cet,
    principal: terms.principal,
    propertyValue: terms.propertyValue,
    signedOn: terms.signedOn,
    termMonths: terms.termMonths,
    installments: [...settled(terms, paid), ...projected(terms, last)],
  }
}

function settled(
  terms: LoanTerms,
  paid: readonly PaidInstallment[],
): LoanInstallment[] {
  const { reference } = terms
  const share = reference.principal / (reference.principal + reference.interest)
  const parts = paid.map(installment => {
    if (installment.number === reference.number) {
      return { ...installment, ...reference }
    }
    const charged = installment.total - reference.fees
    const principal = Math.round(charged * share)
    return { ...installment, principal, interest: charged - principal }
  })
  // The balance after each one leaves the indexer out, as it is unknown.
  return parts.map((part, index) => ({
    number: part.number,
    dueOn: part.dueOn,
    total: part.total,
    principal: part.principal,
    interest: part.interest,
    fees: reference.fees,
    lateFees: 0,
    balance:
      terms.balance +
      parts.slice(index + 1).reduce((sum, later) => sum + later.principal, 0),
    paidOn: part.dueOn,
    paid: part.paid ?? part.total,
  }))
}

function projected(terms: LoanTerms, last: PaidInstallment): LoanInstallment[] {
  const count = terms.termMonths - last.number
  const rate = monthlyRate(terms.effectiveRate)
  const payment = Math.round(
    (terms.balance * rate) / (1 - (1 + rate) ** -count),
  )
  const installments: LoanInstallment[] = []
  let owed = terms.balance
  for (let index = 1; index <= count; index += 1) {
    const interest = Math.round(owed * rate)
    const amortization =
      terms.system === 'PRICE'
        ? payment - interest
        : Math.round(owed / (count - index + 1))
    const principal = index === count ? owed : amortization
    owed -= principal
    installments.push({
      number: last.number + index,
      dueOn: `${shiftMonth(last.dueOn.slice(0, 7), index)}-${last.dueOn.slice(8)}`,
      total: principal + interest + terms.reference.fees,
      principal,
      interest,
      fees: terms.reference.fees,
      lateFees: 0,
      balance: owed,
      paidOn: null,
      paid: null,
    })
  }
  return installments
}
