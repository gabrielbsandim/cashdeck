import {
  aboveAverage,
  type Account,
  addDays,
  CARD_BILL_ABOVE_AVERAGE,
  chargeChange,
  detectRecurring,
  groupByRecurrence,
  isUnusual,
  type LocalDate,
  Money,
  recurrenceKey,
  summarizeCharges,
  type Transaction,
  UNUSUAL_PURCHASE,
  usualAmount,
} from '@cashdeck/domain'
import { type AlertInput } from '@/ports/alerts'
import { type Connection } from '@/ports/records'
import { formatDay, formatMoney } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import { categoryIndex, flowEntries, insightScope } from '@/use-cases/insights'
import { cycleAmount } from '@/use-cases/invoice-templates'
import { lastDay, monthOf, today } from '@/use-cases/shared'

export type WatchAlertDeps = Pick<
  Deps,
  | 'documents'
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'categories'
  | 'recurrences'
  | 'cardBills'
  | 'connections'
  | 'institutions'
  | 'invoices'
  | 'clock'
  | 'alerts'
>

export type WatchAlertsResult = {
  unusualPurchase: number
  subscriptionChanged: number
  cardBillAboveAverage: number
  bankSyncStale: number
  invoiceNotIssued: number
}

const HISTORY_DAYS = 200
const USUAL_DAYS = 90
// A purchase synced late still gets its alert; older ones are history.
const RECENT_DAYS = 3
const CATEGORY_HISTORY = 5
const CARD_HISTORY = 6
const CARD_RECENT_DAYS = 10
const SUBSCRIPTION_RECENT_DAYS = 7
const STALE_SYNC_MS = 48 * 3_600_000
const BROKEN_SYNC = new Set(['LOGIN_ERROR', 'WAITING_USER_INPUT', 'OUTDATED'])
const LIVE_INVOICE = new Set(['ISSUED', 'PROCESSING'])

const brl = (cents: number) => formatMoney(Money.of(Math.round(cents)))

type Expense = { transaction: Transaction; entityId: string; cents: number }

function usualFor(expense: Expense, history: readonly Expense[]) {
  const others = history.filter(
    item =>
      item.transaction.id !== expense.transaction.id &&
      item.entityId === expense.entityId &&
      item.transaction.bookedOn <= expense.transaction.bookedOn,
  )
  const key = recurrenceKey(expense.transaction)
  const merchant = usualAmount(
    others
      .filter(item => key !== '' && recurrenceKey(item.transaction) === key)
      .map(item => item.cents),
    UNUSUAL_PURCHASE,
  )
  if (merchant !== null) {
    return { usual: merchant, scope: 'MERCHANT' }
  }
  const categoryId = expense.transaction.categoryId
  const category = usualAmount(
    others
      .filter(
        item =>
          categoryId !== null && item.transaction.categoryId === categoryId,
      )
      .map(item => item.cents),
    { ...UNUSUAL_PURCHASE, minHistory: CATEGORY_HISTORY },
  )
  return { usual: category, scope: 'CATEGORY' }
}

function unusualAlert(
  tenantId: string,
  expense: Expense,
  usual: number,
  scope: string,
): AlertInput {
  const tx = expense.transaction
  return {
    tenantId,
    type: 'UNUSUAL_PURCHASE',
    entityId: expense.entityId,
    data: {
      transactionId: tx.id,
      merchant: tx.merchant ?? tx.description,
      amount: brl(expense.cents),
      usual: brl(usual),
      times: String(Math.floor(expense.cents / usual)),
      scope,
      day: formatDay(tx.bookedOn),
    },
    dedupeKey: `UNUSUAL_PURCHASE:${tx.id}`,
  }
}

function subscriptionAlerts(
  tenantId: string,
  entityId: string,
  expenses: readonly Transaction[],
  keys: ReadonlySet<string>,
  day: LocalDate,
): AlertInput[] {
  return [...groupByRecurrence(expenses)].flatMap(([key, charges]) => {
    const charge = summarizeCharges(key, charges)
    const change = chargeChange(charge)
    const fresh = charge.lastChargeOn >= addDays(day, -SUBSCRIPTION_RECENT_DAYS)
    if (!keys.has(key) || !fresh || change === null) {
      return []
    }
    const latest = charge.transactionIds[0] as string
    const detail: Record<string, string> =
      change.kind === 'PRICE_UP'
        ? {
            previous: formatMoney(change.previous),
            percent: String(change.percent),
          }
        : { count: String(change.count), month: change.month }
    return [
      {
        tenantId,
        type: 'SUBSCRIPTION_CHANGED',
        entityId,
        data: {
          change: change.kind,
          key,
          name: charge.name,
          amount: formatMoney(charge.amount),
          transactionId: latest,
          ...detail,
        },
        dedupeKey: `SUBSCRIPTION_CHANGED:${entityId}:${key}:${latest}`,
      },
    ]
  })
}

function syncAlert(
  connection: Connection,
  institution: string,
  now: Date,
): AlertInput | null {
  const last = connection.lastSyncAt
  const old = last === null || now.getTime() - last.getTime() > STALE_SYNC_MS
  if (!old && !BROKEN_SYNC.has(connection.status)) {
    return null
  }
  const hours = last
    ? Math.floor((now.getTime() - last.getTime()) / 3_600_000)
    : null
  return {
    tenantId: connection.tenantId,
    type: 'BANK_SYNC_STALE',
    entityId: connection.entityId,
    data: {
      connectionId: connection.id,
      institution,
      status: connection.status,
      hours: hours === null ? '' : String(hours),
      lastSyncAt: last ? formatDay(today(last)) : '',
    },
    dedupeKey: `BANK_SYNC_STALE:${connection.id}:${last?.toISOString() ?? 'never'}`,
  }
}

export function makeWatchAlerts(deps: WatchAlertDeps) {
  async function emitAll(inputs: readonly AlertInput[]): Promise<number> {
    let emitted = 0
    for (const input of inputs) {
      emitted += (await deps.alerts.emit(input)) ? 1 : 0
    }
    return emitted
  }

  async function expensesOf(
    tenantId: string,
    accounts: readonly Account[],
    day: LocalDate,
  ): Promise<Expense[]> {
    const categories = await categoryIndex(deps, tenantId)
    const entries = await flowEntries(deps, tenantId, accounts, categories, {
      from: addDays(day, -HISTORY_DAYS),
      to: day,
    })
    const owner = new Map(
      accounts.map(account => [account.id, account.entityId]),
    )
    return entries
      .filter(
        entry => entry.kind === 'EXPENSE' && !entry.transaction.provisional,
      )
      .map(entry => ({
        transaction: entry.transaction,
        entityId: owner.get(entry.transaction.accountId) as string,
        cents: entry.cents,
      }))
  }

  function unusualPurchases(
    tenantId: string,
    expenses: readonly Expense[],
    day: LocalDate,
  ): AlertInput[] {
    const since = addDays(day, -USUAL_DAYS)
    const history = expenses.filter(item => item.transaction.bookedOn >= since)
    const recent = history.filter(
      item =>
        item.transaction.bookedOn >= addDays(day, -RECENT_DAYS) &&
        item.transaction.installment === null,
    )
    return recent.flatMap(expense => {
      const { usual, scope } = usualFor(expense, history)
      if (
        usual === null ||
        !isUnusual(expense.cents, usual, UNUSUAL_PURCHASE)
      ) {
        return []
      }
      return [unusualAlert(tenantId, expense, usual, scope)]
    })
  }

  async function subscriptions(
    tenantId: string,
    entityIds: readonly string[],
    expenses: readonly Expense[],
    day: LocalDate,
  ): Promise<AlertInput[]> {
    const decided = await deps.recurrences.list(tenantId)
    return entityIds.flatMap(entityId => {
      const own = expenses
        .filter(item => item.entityId === entityId)
        .map(item => item.transaction)
      const mine = decided.filter(item => item.entityId === entityId)
      const dismissed = new Set(
        mine.filter(item => item.status === 'DISMISSED').map(item => item.key),
      )
      const keys = new Set([
        ...mine
          .filter(item => item.status === 'CONFIRMED')
          .map(item => item.key),
        ...detectRecurring(own, day)
          .map(charge => charge.key)
          .filter(key => !dismissed.has(key)),
      ])
      return subscriptionAlerts(tenantId, entityId, own, keys, day)
    })
  }

  async function cardBills(
    tenantId: string,
    accounts: readonly Account[],
    day: LocalDate,
  ): Promise<AlertInput[]> {
    const cards = accounts.filter(account => account.type === 'CREDIT_CARD')
    if (cards.length === 0) {
      return []
    }
    const stored = await deps.cardBills.list(
      tenantId,
      cards.map(card => card.id),
    )
    return cards.flatMap(card => {
      const closed = stored
        .filter(
          bill =>
            bill.accountId === card.id && (bill.closesOn ?? bill.dueOn) <= day,
        )
        .sort((a, b) => a.dueOn.localeCompare(b.dueOn))
      const latest = closed.at(-1)
      if (!latest) {
        return []
      }
      if ((latest.closesOn ?? latest.dueOn) < addDays(day, -CARD_RECENT_DAYS)) {
        return []
      }
      const history = closed
        .slice(0, -1)
        .slice(-CARD_HISTORY)
        .map(bill => bill.total.cents)
      const above = aboveAverage(
        latest.total.cents,
        history,
        CARD_BILL_ABOVE_AVERAGE,
      )
      if (!above) {
        return []
      }
      return [
        {
          tenantId,
          type: 'CARD_BILL_ABOVE_AVERAGE' as const,
          entityId: card.entityId,
          data: {
            accountId: card.id,
            card: card.name,
            amount: formatMoney(latest.total),
            average: brl(above.average),
            percent: String(above.percent),
            dueDate: formatDay(latest.dueOn),
          },
          dedupeKey: `CARD_BILL_ABOVE_AVERAGE:${card.id}:${latest.dueOn}`,
        },
      ]
    })
  }

  async function staleSyncs(tenantId: string): Promise<AlertInput[]> {
    const now = deps.clock.now()
    const alerts: AlertInput[] = []
    for (const connection of await deps.connections.list(tenantId)) {
      const institution = await deps.institutions.findById(
        tenantId,
        connection.institutionId,
      )
      const alert = syncAlert(connection, institution?.name ?? 'Banco', now)
      if (alert) {
        alerts.push(alert)
      }
    }
    return alerts
  }

  // A template is late the day after its usual day, while the month still has
  // no invoice issued or on its way for it.
  async function missingInvoices(
    tenantId: string,
    day: LocalDate,
  ): Promise<AlertInput[]> {
    const company = await deps.entities.findByKind(tenantId, 'PJ')
    if (!company) {
      return []
    }
    const month = monthOf(day)
    const monthLength = Number(lastDay(month).slice(8))
    const templates = (
      await deps.invoices.listTemplates(tenantId, company.id)
    ).filter(
      template =>
        template.active &&
        Number(day.slice(8)) > Math.min(template.dayOfMonth, monthLength),
    )
    if (templates.length === 0) {
      return []
    }
    const invoices = await deps.invoices.all(tenantId, {
      entityId: company.id,
      competenceFrom: month,
      competenceTo: month,
    })
    const alerts: AlertInput[] = []
    for (const template of templates) {
      const own = invoices.filter(invoice => invoice.templateId === template.id)
      if (own.some(invoice => LIVE_INVOICE.has(invoice.status))) {
        continue
      }
      const client = await deps.invoices.findClient(tenantId, template.clientId)
      const usualDay = Math.min(template.dayOfMonth, monthLength)
      alerts.push({
        tenantId,
        type: 'INVOICE_NOT_ISSUED',
        entityId: company.id,
        invoiceId: own[0]?.id ?? null,
        data: {
          templateId: template.id,
          client: client?.name ?? '',
          amount: formatMoney(cycleAmount(template)),
          day: formatDay(`${month}-${String(usualDay).padStart(2, '0')}`),
          competence: month,
        },
        dedupeKey: `INVOICE_NOT_ISSUED:${template.id}:${month}`,
      })
    }
    return alerts
  }

  return async function runWatchAlerts(
    tenantId: string,
  ): Promise<WatchAlertsResult> {
    const day = today(deps.clock.now())
    const scope = await insightScope(deps, tenantId, undefined)
    const expenses = await expensesOf(tenantId, scope.accounts, day)
    const entityIds = scope.entities.map(entity => entity.id)
    return {
      unusualPurchase: await emitAll(unusualPurchases(tenantId, expenses, day)),
      subscriptionChanged: await emitAll(
        await subscriptions(tenantId, entityIds, expenses, day),
      ),
      cardBillAboveAverage: await emitAll(
        await cardBills(tenantId, scope.accounts, day),
      ),
      bankSyncStale: await emitAll(await staleSyncs(tenantId)),
      invoiceNotIssued: await emitAll(await missingInvoices(tenantId, day)),
    }
  }
}
