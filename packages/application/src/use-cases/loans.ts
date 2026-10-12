import {
  type EntityKind,
  type LoanInstallment,
  type LoanStatement,
  loanStanding,
  Money,
  prepayment,
  readBradescoLoanStatement,
  ValidationError,
} from '@cashdeck/domain'
import { money } from '@/dtos/common'
import {
  type ImportLoanInput,
  type LoansView,
  type LoanView,
  type PrepaymentView,
} from '@/dtos/loans'
import { type Deps } from '@/use-cases/deps'
import {
  decodeUpload,
  requireEntity,
  required,
  today,
} from '@/use-cases/shared'

export const LOANS_COLLECTION = 'loans'

export type StoredLoan = LoanStatement & {
  id: string
  entityId: string
  entity: EntityKind
  importedAt: string
}

type LoanDeps = Pick<Deps, 'entities' | 'documents' | 'documentText' | 'clock'>

const UPCOMING = 12

const cents = (value: number) => money(Money.of(value))

const installmentView = (installment: LoanInstallment) => ({
  number: installment.number,
  dueOn: installment.dueOn,
  total: cents(installment.total),
  principal: cents(installment.principal),
  interest: cents(installment.interest),
  fees: cents(installment.fees),
})

export const loadLoans = (deps: Pick<Deps, 'documents'>, tenantId: string) =>
  deps.documents.list<StoredLoan>(tenantId, LOANS_COLLECTION)

export function loanView(loan: StoredLoan, day: string): LoanView {
  const standing = loanStanding(loan, day)
  const next = standing.open[0]
  return {
    id: loan.id,
    entity: loan.entity,
    name: `${loan.lender} ${loan.contract}`,
    lender: loan.lender,
    contract: loan.contract,
    system: loan.system,
    indexer: loan.indexer,
    effectiveRate: loan.effectiveRate,
    cet: loan.cet,
    principal: cents(loan.principal),
    propertyValue:
      loan.propertyValue === null ? null : cents(loan.propertyValue),
    signedOn: loan.signedOn,
    termMonths: loan.termMonths,
    paidCount: standing.paid.count,
    balance: cents(standing.balance),
    lastDueOn: standing.lastDueOn,
    next: next ? installmentView(next) : null,
    upcoming: standing.open.slice(0, UPCOMING).map(installmentView),
    remaining: {
      count: standing.remaining.count,
      total: cents(standing.remaining.total),
      interest: cents(standing.remaining.interest),
      principal: cents(standing.remaining.principal),
      fees: cents(standing.remaining.fees),
    },
    paid: {
      count: standing.paid.count,
      total: cents(standing.paid.total),
      interest: cents(standing.paid.interest),
      principal: cents(standing.paid.principal),
      lateFees: cents(standing.paid.lateFees),
    },
    importedAt: loan.importedAt,
  }
}

export function makeLoans(deps: LoanDeps) {
  const day = () => today(deps.clock.now())

  async function find(tenantId: string, id: string) {
    return required(
      await deps.documents.get<StoredLoan>(tenantId, LOANS_COLLECTION, id),
      'Loan',
    )
  }

  // A new statement of the same contract replaces the stored one.
  async function importStatement(
    tenantId: string,
    input: ImportLoanInput,
  ): Promise<LoanView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const text = await deps.documentText.read({
      mimeType: input.mimeType,
      bytes: decodeUpload(input.base64),
    })
    const statement = readBradescoLoanStatement(text ?? '')
    if (!statement) {
      throw new ValidationError('The file is not a loan statement we can read.')
    }
    const loan: StoredLoan = {
      ...statement,
      id: `${statement.lender}-${statement.contract}`.toLowerCase(),
      entityId: entity.id,
      entity: entity.kind,
      importedAt: deps.clock.now().toISOString(),
    }
    await deps.documents.put(tenantId, LOANS_COLLECTION, loan.id, loan)
    return loanView(loan, day())
  }

  async function list(tenantId: string): Promise<LoansView> {
    const loans = await loadLoans(deps, tenantId)
    return {
      items: loans
        .sort((a, b) => a.signedOn.localeCompare(b.signedOn))
        .map(loan => loanView(loan, day())),
    }
  }

  async function simulatePrepayment(
    tenantId: string,
    id: string,
    amount: number,
  ): Promise<PrepaymentView> {
    const result = prepayment(await find(tenantId, id), day(), amount)
    return {
      amount: cents(result.amount),
      interestSaved: cents(result.interestSaved),
      feesSaved: cents(result.feesSaved),
      monthsCut: result.monthsCut,
      lastDueOn: result.lastDueOn,
      balanceAfter: cents(result.balanceAfter),
    }
  }

  async function remove(tenantId: string, id: string) {
    await find(tenantId, id)
    await deps.documents.delete(tenantId, LOANS_COLLECTION, id)
    return { id }
  }

  return { importStatement, list, simulatePrepayment, remove }
}
