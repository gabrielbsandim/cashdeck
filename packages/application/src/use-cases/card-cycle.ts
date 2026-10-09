import { type Account, type LocalDate, shiftMonth } from '@cashdeck/domain'
import { type CardBill } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { lastDay, monthOf } from '@/use-cases/shared'

export type CardDues = ReadonlyMap<string, LocalDate | null>

export function sameDayIn(month: string, dayOfMonth: string): LocalDate {
  const sameDay = `${month}-${dayOfMonth}`
  const last = lastDay(month)
  return sameDay < last ? sameDay : last
}

export function latestDue(stored: readonly CardBill[]): LocalDate | null {
  return (
    stored
      .map(bill => bill.dueOn)
      .sort()
      .at(-1) ?? null
  )
}

// Issuers keep the due day fixed, so the cycle after the last known bill
// falls on the same day of a later month.
export function dueAfter(latest: LocalDate, day: LocalDate): LocalDate {
  let month = shiftMonth(monthOf(latest), 1)
  while (sameDayIn(month, latest.slice(8)) < day) {
    month = shiftMonth(month, 1)
  }
  return sameDayIn(month, latest.slice(8))
}

// The issuer's date when it sends one, else the next unpaid stored bill, else
// the cycle projected from the bill history.
export function nextDue(
  card: Account,
  stored: readonly CardBill[],
  day: LocalDate,
): LocalDate | null {
  if (card.credit?.dueOn) {
    return card.credit.dueOn
  }
  const pending = stored
    .map(bill => bill.dueOn)
    .filter(due => due >= day)
    .sort()
    .at(0)
  if (pending) {
    return pending
  }
  const latest = latestDue(stored)
  return latest ? dueAfter(latest, day) : null
}

export async function cardDues(
  deps: Pick<Deps, 'cardBills'>,
  tenantId: string,
  accounts: readonly Account[],
  day: LocalDate,
): Promise<CardDues> {
  const cards = accounts.filter(account => account.type === 'CREDIT_CARD')
  if (cards.length === 0) {
    return new Map()
  }
  const stored = await deps.cardBills.list(
    tenantId,
    cards.map(card => card.id),
  )
  return new Map(
    cards.map(card => [
      card.id,
      nextDue(
        card,
        stored.filter(bill => bill.accountId === card.id),
        day,
      ),
    ]),
  )
}
