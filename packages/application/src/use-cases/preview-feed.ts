import {
  type Account,
  addDays,
  createTransaction,
  daysBetween,
  Money,
  normalizeDescription,
  type Transaction,
} from '@cashdeck/domain'
import { ProviderNotConfiguredError } from '@/errors/errors'
import {
  type PreviewAccount,
  type ProviderTransaction,
} from '@/ports/providers'
import { type Deps } from '@/use-cases/deps'
import { today } from '@/use-cases/shared'

// Two feeds date one movement within this many days of each other.
export const PAIRING_DAYS = 2
// How far back the preview feed is read; older movements are the main one's.
export const PREVIEW_DAYS = 7
// A preview the main provider has not confirmed this long after collecting
// its day was a pending charge that fell through, or a duplicate.
export const PREVIEW_GRACE_DAYS = 3

export type Movement = Pick<Transaction, 'amount' | 'bookedOn' | 'description'>

const distance = (a: Movement, b: Movement) =>
  Math.abs(daysBetween(a.bookedOn, b.bookedOn))

const sameAmount = (a: Movement, b: Movement) => a.amount.equals(b.amount)

// A converted or adjusted charge keeps the merchant words and the direction.
function sameMerchant(a: Movement, b: Movement) {
  const words = normalizeDescription(a.description)
  return (
    words !== '' &&
    words === normalizeDescription(b.description) &&
    a.amount.isPositive() === b.amount.isPositive()
  )
}

// Each side's movements pair at most once: by amount first, then by merchant,
// always with the closest day.
export function pairMovements<A extends Movement, B extends Movement>(
  left: readonly A[],
  right: readonly B[],
): Array<[A, B]> {
  const pairs: Array<[A, B]> = []
  const taken = new Set<B>()
  const pending = new Set(left)
  const closest = (item: A, alike: typeof sameAmount) =>
    right
      .filter(other => !taken.has(other) && alike(item, other))
      .filter(other => distance(item, other) <= PAIRING_DAYS)
      .sort((a, b) => distance(item, a) - distance(item, b))[0]
  const pass = (alike: typeof sameAmount) => {
    for (const item of [...pending]) {
      const match = closest(item, alike)
      if (!match) {
        continue
      }
      taken.add(match)
      pending.delete(item)
      pairs.push([item, match])
    }
  }
  pass(sameAmount)
  pass(sameMerchant)
  return pairs
}

// The user's edits survive confirmation; every fact comes from the main feed.
export function confirmPreview(
  preview: Transaction,
  confirmed: Transaction,
): Transaction {
  return {
    ...confirmed,
    id: preview.id,
    categoryId: preview.categoryId,
    categorizedBy: preview.categorizedBy,
    categoryConfidence: preview.categoryConfidence,
    note: preview.note,
    transferGroupId: preview.transferGroupId,
    invoiceId: preview.invoiceId,
    provisional: false,
  }
}

const touched = (tx: Transaction) =>
  tx.categorizedBy === 'USER' ||
  tx.note !== null ||
  tx.transferGroupId !== null ||
  tx.invoiceId !== null

export type PreviewSettlement = { confirmed: number; dropped: number }

type SettleDeps = Pick<Deps, 'transactions'>

// Run as the main provider brings an account's movements: each preview it
// recognises takes its facts, and one it never brought goes away unless the
// user already worked on it. `collectedOn` is null when the main provider
// does not say how far it collected, and then nothing is dropped.
export async function settlePreviews(
  deps: SettleDeps,
  account: Account,
  incoming: readonly Transaction[],
  collectedOn: string | null,
): Promise<PreviewSettlement> {
  const previews = await deps.transactions.all(account.tenantId, {
    accountIds: [account.id],
    provisional: true,
  })
  if (previews.length === 0) {
    return { confirmed: 0, dropped: 0 }
  }
  const known = new Set(
    (
      await deps.transactions.all(account.tenantId, {
        accountIds: [account.id],
        provisional: false,
      })
    ).map(tx => tx.externalId),
  )
  const fresh = incoming.filter(tx => !known.has(tx.externalId))
  const pairs = pairMovements(fresh, previews)
  for (const [confirmed, preview] of pairs) {
    await deps.transactions.save(confirmPreview(preview, confirmed))
  }
  const paired = new Set(pairs.map(([, preview]) => preview.id))
  const expired = collectedOn
    ? previews.filter(
        tx =>
          !paired.has(tx.id) &&
          !touched(tx) &&
          tx.bookedOn <= addDays(collectedOn, -PREVIEW_GRACE_DAYS),
      )
    : []
  for (const tx of expired) {
    await deps.transactions.delete(account.tenantId, tx.id)
  }
  return { confirmed: pairs.length, dropped: expired.length }
}

type PreviewDeps = Pick<
  Deps,
  'accounts' | 'institutions' | 'transactions' | 'preview' | 'clock' | 'ids'
>

export function makePreviewFeed(deps: PreviewDeps) {
  async function institutionNames(accounts: readonly Account[]) {
    const names = new Map<string, string>()
    for (const account of accounts) {
      const institution = await deps.institutions.findById(
        account.tenantId,
        account.institutionId,
      )
      names.set(account.id, institution?.name ?? '')
    }
    return names
  }

  const toPreview = (account: Account, tx: ProviderTransaction) =>
    createTransaction({
      id: deps.ids.next(),
      tenantId: account.tenantId,
      accountId: account.id,
      amount: Money.of(tx.amountCents, tx.currency),
      bookedOn: tx.bookedOn,
      description: tx.description,
      externalId: tx.externalId,
      merchant: tx.merchant ?? null,
      counterparty: tx.counterparty ?? null,
      installment: tx.installment ?? null,
      provisional: true,
    })

  type Candidate = { account: Account; stored: Transaction[]; pairs: number }

  // Two accounts of one bank can share a name, so the one whose stored
  // movements the feed repeats wins, then the one with the same balance.
  function pick(
    offer: PreviewAccount,
    candidates: readonly Candidate[],
  ): Candidate | null {
    const [best, next] = [...candidates].sort((a, b) => b.pairs - a.pairs)
    if (!best || !next || best.pairs > next.pairs) {
      return best ?? null
    }
    const balanced = candidates.filter(
      candidate => candidate.account.balance.cents === offer.balanceCents,
    )
    const [only, other] = balanced
    return only && !other ? only : null
  }

  async function sync(tenantId: string) {
    const day = today(deps.clock.now())
    const range = { from: addDays(day, -PREVIEW_DAYS), to: day }
    const offers = await deps.preview.listAccounts().catch(notConfigured)
    if (!offers) {
      return { accounts: 0, previews: 0 }
    }
    const fetched = await deps.preview.listTransactions(range)
    const accounts = (await deps.accounts.list(tenantId)).filter(
      account => account.connectionId !== null,
    )
    const names = await institutionNames(accounts)
    let matched = 0
    let previews = 0
    for (const offer of offers) {
      const movements = fetched
        .filter(tx => tx.accountExternalId === offer.externalId)
        .map(tx => ({ tx, ...movementOf(tx) }))
      const candidates: Candidate[] = []
      for (const account of accounts.filter(
        candidate =>
          candidate.type === offer.type &&
          candidate.name.trim() === offer.name.trim() &&
          names.get(candidate.id) === offer.institutionName,
      )) {
        const stored = await deps.transactions.all(tenantId, {
          accountIds: [account.id],
          from: addDays(range.from, -PAIRING_DAYS),
        })
        candidates.push({
          account,
          stored,
          pairs: pairMovements(movements, stored).length,
        })
      }
      const chosen = pick(offer, candidates)
      if (!chosen) {
        continue
      }
      matched += 1
      const paired = new Set(
        pairMovements(movements, chosen.stored).map(([item]) => item),
      )
      previews += await deps.transactions.saveNew(
        movements
          .filter(item => !paired.has(item))
          .map(item => toPreview(chosen.account, item.tx)),
      )
    }
    // A failed request only delays the next preview; the main feed still runs.
    await deps.preview.requestRefresh().catch((error: unknown) => {
      console.warn(`[preview] refresh request failed: ${String(error)}`)
    })
    return { accounts: matched, previews }
  }

  return { sync }
}

// Without credentials the feed is simply off; any other failure is real.
function notConfigured(error: unknown): null {
  if (error instanceof ProviderNotConfiguredError) {
    return null
  }
  throw error
}

function movementOf(tx: ProviderTransaction): Movement {
  return {
    amount: Money.of(tx.amountCents, tx.currency),
    bookedOn: tx.bookedOn,
    description: tx.description,
  }
}
