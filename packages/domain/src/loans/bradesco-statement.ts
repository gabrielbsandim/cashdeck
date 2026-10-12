import { type LocalDate } from '@/calendar/local-date'
import {
  AMORTIZATION_SYSTEMS,
  type AmortizationSystem,
  type LoanInstallment,
  type LoanStatement,
} from '@/loans/loan'

const AMOUNT = String.raw`\d{1,3}(?:\.\d{3})*,\d{2}`
const DATE = String.raw`\d{2}/\d{2}/\d{4}`
const FACTOR = String.raw`\d+,\d{6}`

// Number, due date, total, principal, correction, MIP, DFI, admin fee, fine,
// late interest, FGTS, correction, balance, status with payment, interest.
const ROW = new RegExp(
  [
    String.raw`(\d{1,3}) (${DATE}) (${AMOUNT}) (${AMOUNT}) ${FACTOR}`,
    `(${AMOUNT}) (${AMOUNT}) (${AMOUNT}) (${AMOUNT}) (${AMOUNT}) ${AMOUNT}`,
    `${FACTOR} (${AMOUNT})`,
    String.raw`(?:Paga (${DATE}) (${AMOUNT})|A Vencer - ${AMOUNT}) (${AMOUNT})`,
  ].join(' '),
  'g',
)

const cents = (amount: string) =>
  Math.round(Number(amount.replace(/\./g, '').replace(',', '.')) * 100)

const percent = (value: string) => Number(value.replace(',', '.'))

const isoDate = (date: string): LocalDate => {
  const [day, month, year] = date.split('/')
  return `${year}-${month}-${day}`
}

const pick = (text: string, pattern: RegExp) => pattern.exec(text)?.[1]

function installmentOf(row: RegExpExecArray): LoanInstallment {
  const amount = (index: number) => cents(row[index] as string)
  const paidOn = row[11]
  return {
    number: Number(row[1]),
    dueOn: isoDate(row[2] as string),
    total: amount(3),
    principal: amount(4),
    interest: amount(13),
    fees: amount(5) + amount(6) + amount(7),
    lateFees: amount(8) + amount(9),
    balance: amount(10),
    paidOn: paidOn ? isoDate(paidOn) : null,
    paid: paidOn ? amount(12) : null,
  }
}

const systemOf = (value: string | undefined): AmortizationSystem | null =>
  AMORTIZATION_SYSTEMS.find(system => system === value) ?? null

// The "Extrato Financeiro" of a Bradesco housing loan, as the PDF text reader
// gives it; anything else, or a statement missing its terms, reads as null.
export function readBradescoLoanStatement(text: string): LoanStatement | null {
  const flat = text.replace(/\s+/g, ' ')
  if (!flat.includes('Extrato Financeiro') || !flat.includes('ENCARGOS')) {
    return null
  }
  const contract = pick(flat, /CONTRATO (\d+)/)
  const signedOn = pick(flat, new RegExp(`Data do contrato (${DATE})`))
  const principal = pick(flat, new RegExp(`(${AMOUNT}) Valor Financiamento`))
  const rates = new RegExp(
    String.raw`Efetiva\(a\.a\) CET\(a\.a\) ([\d,]+)% ([\d,]+)%`,
  ).exec(flat)
  const system = systemOf(pick(flat, /Sistema Amortização (\w+)/))
  const term = pick(flat, /\d+\/(\d+) Prazo/)
  const installments = [...flat.matchAll(ROW)]
    .map(installmentOf)
    .filter(installment => installment.number > 0)
  const terms = [contract, signedOn, principal, rates, system, term]
  if (terms.some(value => !value) || installments.length === 0) {
    return null
  }
  const propertyValue = pick(flat, new RegExp(`Valor Imóvel (${AMOUNT})`))
  const [, effective, cet] = rates as RegExpExecArray
  return {
    lender: 'Bradesco',
    contract: contract as string,
    system: system as AmortizationSystem,
    indexer: pick(flat, /(\w+) Indexador/) ?? '',
    effectiveRate: percent(effective as string),
    cet: percent(cet as string),
    principal: cents(principal as string),
    propertyValue: propertyValue ? cents(propertyValue) : null,
    signedOn: isoDate(signedOn as string),
    termMonths: Number(term),
    installments,
  }
}
