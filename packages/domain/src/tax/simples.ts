import { isBusinessDay } from '@/calendar/business-days'
import { addDays, localDate, type LocalDate } from '@/calendar/local-date'
import { Money } from '@/money/money'

export type SimplesAnnex = 'III' | 'V'

// Fator R: twelve months of payroll over twelve months of revenue.
export const FATOR_R_THRESHOLD = 0.28

type Bracket = {
  readonly upToCents: number
  readonly rate: number
  readonly deductionCents: number
  // ISS, PIS and COFINS share of the rate, which an export does not pay.
  readonly domesticOnlyShare: number
  readonly issShare: number
}

const REAIS = 100

const bracket = (
  upTo: number,
  rate: number,
  deduction: number,
  domesticOnlyShare: number,
  issShare: number,
): Bracket => ({
  upToCents: upTo * REAIS,
  rate,
  deductionCents: deduction * REAIS,
  domesticOnlyShare,
  issShare,
})

// LC 123/2006 Annexes III and V as amended by LC 155/2016.
const ANNEXES: Record<SimplesAnnex, readonly Bracket[]> = {
  III: [
    bracket(180_000, 0.06, 0, 0.491, 0.335),
    bracket(360_000, 0.112, 9_360, 0.491, 0.32),
    bracket(720_000, 0.135, 17_640, 0.491, 0.325),
    bracket(1_800_000, 0.16, 35_640, 0.491, 0.325),
    bracket(3_600_000, 0.21, 125_640, 0.491, 0.335),
    bracket(4_800_000, 0.33, 648_000, 0.195, 0),
  ],
  V: [
    bracket(180_000, 0.155, 0, 0.3115, 0.14),
    bracket(360_000, 0.18, 4_500, 0.3415, 0.17),
    bracket(720_000, 0.195, 9_900, 0.3715, 0.19),
    bracket(1_800_000, 0.205, 17_100, 0.4015, 0.21),
    bracket(3_600_000, 0.23, 62_100, 0.4065, 0.235),
    bracket(4_800_000, 0.305, 540_000, 0.2, 0),
  ],
}

export function fatorR(payroll12: Money, revenue12: Money): number {
  return revenue12.isPositive() ? payroll12.cents / revenue12.cents : 0
}

export function annexFor(payroll12: Money, revenue12: Money): SimplesAnnex {
  return fatorR(payroll12, revenue12) >= FATOR_R_THRESHOLD ? 'III' : 'V'
}

function bracketFor(annex: SimplesAnnex, rbt12: Money): Bracket {
  const brackets = ANNEXES[annex]
  const found = brackets.find(candidate => rbt12.cents <= candidate.upToCents)
  return found ?? (brackets.at(-1) as Bracket)
}

export function effectiveRate(annex: SimplesAnnex, rbt12: Money): number {
  const found = bracketFor(annex, rbt12)
  if (!rbt12.isPositive()) {
    return found.rate
  }
  return (rbt12.cents * found.rate - found.deductionCents) / rbt12.cents
}

const ISS_CAP = 0.05

// The ISS share of the effective rate, capped at 5%. Null in the last bracket,
// where ISS leaves the DAS and the city charges its own rate.
export function issRate(annex: SimplesAnnex, rbt12: Money): number | null {
  const { issShare } = bracketFor(annex, rbt12)
  if (issShare === 0) {
    return null
  }
  return Math.min(effectiveRate(annex, rbt12) * issShare, ISS_CAP)
}

// LC 123/2006 art. 3, par. 15: each market finds its rate from its own RBT12.
export type DasEstimateInput = {
  annex: SimplesAnnex
  domesticRbt12: Money
  exportRbt12: Money
  domestic: Money
  exports: Money
}

export function estimateDas(input: DasEstimateInput): Money {
  const exportBracket = bracketFor(input.annex, input.exportRbt12)
  const domestic =
    input.domestic.cents * effectiveRate(input.annex, input.domesticRbt12)
  const exports =
    input.exports.cents *
    effectiveRate(input.annex, input.exportRbt12) *
    (1 - exportBracket.domesticOnlyShare)
  return Money.of(Math.round(domestic + exports), input.domestic.currency)
}

// The DAS of a competence is due on the 20th of the next month, moved back
// to the last business day before it.
export function dasDueDate(competence: string): LocalDate {
  const [year, month] = competence.split('-').map(Number) as [number, number]
  let due = localDate(year, month + 1, 20)
  while (!isBusinessDay(due)) {
    due = addDays(due, -1)
  }
  return due
}
