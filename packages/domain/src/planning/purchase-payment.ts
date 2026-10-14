// Income tax on fixed income falls the longer the money stays invested.
const INCOME_TAX = [
  { upTo: 6, rate: 0.225 },
  { upTo: 12, rate: 0.2 },
  { upTo: 24, rate: 0.175 },
] as const
const LONG_TERM_TAX = 0.15

// The CDI compounds over business days.
const BUSINESS_DAYS_A_YEAR = 252

export function incomeTaxRate(months: number): number {
  return (
    INCOME_TAX.find(bracket => months <= bracket.upTo)?.rate ?? LONG_TERM_TAX
  )
}

// Daily rates in percent per day, as the central bank publishes the CDI.
export function yearlyFromDaily(daily: readonly number[]): number | null {
  if (daily.length === 0) {
    return null
  }
  const mean = daily.reduce((sum, rate) => sum + rate, 0) / daily.length
  return ((1 + mean / 100) ** BUSINESS_DAYS_A_YEAR - 1) * 100
}

export type PaymentComparison = {
  installments: number
  // Paid at once, after the discount.
  cashCents: number
  // The installments, worth less today since the money earns until each bill.
  cardTodayCents: number
  better: 'CASH' | 'CARD'
  gainCents: number
  // The discount at which paying at once costs the same as the installments.
  breakEvenPercent: number
}

export type PaymentInput = {
  // What leaves savings without any discount.
  amountCents: number
  // The discount applies to the full price, before any trade-in.
  priceCents: number
  discountPercent: number
  installments: number
  yearlyPercent: number
}

// The first installment comes with the bill after the purchase.
export function comparePayment(input: PaymentInput): PaymentComparison | null {
  if (input.installments < 2 || input.amountCents <= 0) {
    return null
  }
  const gross = (1 + input.yearlyPercent / 100) ** (1 / 12) - 1
  const monthly = gross * (1 - incomeTaxRate(input.installments))
  const each = input.amountCents / input.installments
  const cardToday = Array.from(
    { length: input.installments },
    (_, index) => each / (1 + monthly) ** (index + 1),
  ).reduce((sum, value) => sum + value, 0)
  const cash =
    input.amountCents - (input.priceCents * input.discountPercent) / 100
  const cardTodayCents = Math.round(cardToday)
  const cashCents = Math.round(cash)
  return {
    installments: input.installments,
    cashCents,
    cardTodayCents,
    better: cashCents <= cardTodayCents ? 'CASH' : 'CARD',
    gainCents: Math.abs(cardTodayCents - cashCents),
    breakEvenPercent:
      Math.round(((input.amountCents - cardToday) * 1000) / input.priceCents) /
      10,
  }
}

export type MonthlyAmount = { month: string; cents: number }

// The first month from which the installments already on the cards stay at
// or below the limit; null when they never do within the months given.
export function installmentsFadeMonth(
  committed: readonly MonthlyAmount[],
  limitCents: number,
): string | null {
  const last = committed.reduce(
    (found, point, index) => (point.cents > limitCents ? index : found),
    -1,
  )
  return committed[last + 1]?.month ?? null
}
