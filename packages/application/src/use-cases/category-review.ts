import {
  addDays,
  type CategoryRule,
  categorize,
  directionOf,
  type EntityKind,
  Money,
  recurrenceKey,
  reviewKey,
  ruleMatches,
  sharedPattern,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type CategorizeGroupResult,
  type categorizeGroupSchema,
  type ReviewGroupView,
  type ReviewQueueView,
  type ReviewReason,
  type RuleSuggestionView,
} from '@/dtos/category-review'
import { accountIdsOf, applyRule, learnRule } from '@/use-cases/categorization'
import {
  type CategoryRulesDeps,
  entityKinds,
  toCategoryRuleView,
} from '@/use-cases/category-rules'
import { type Deps } from '@/use-cases/deps'
import { insightScope } from '@/use-cases/insights'
import { required, today } from '@/use-cases/shared'

export const RULE_SUGGESTIONS_DISMISSED = 'rule-suggestions-dismissed'

const REVIEW_DAYS = 90
const SUGGESTION_DAYS = 180
// The model's answers below this are kept but shown to the user again.
export const REVIEW_CONFIDENCE = 0.75
const MIN_REPEATS = 2

type ReviewDeps = CategoryRulesDeps & Pick<Deps, 'documents'>

type Scoped = { transaction: Transaction; entityId: string }

function reasonOf(
  tx: Transaction,
  reference: string | null,
): ReviewReason | null {
  if (tx.categorizedBy === 'USER') {
    return null
  }
  if (tx.categoryId === null) {
    return 'UNCATEGORIZED'
  }
  if (
    tx.categorizedBy === 'AI' &&
    (tx.categoryConfidence ?? 0) < REVIEW_CONFIDENCE
  ) {
    return 'LOW_CONFIDENCE'
  }
  // A rule carries a choice the user already made, such as one payee split by
  // amount, so it never disagrees with the group.
  if (tx.categorizedBy === 'RULE') {
    return null
  }
  return reference !== null && tx.categoryId !== reference
    ? 'INCONSISTENT'
    : null
}

const newestFirst = (a: Transaction, b: Transaction) =>
  b.bookedOn.localeCompare(a.bookedOn) || a.id.localeCompare(b.id)

// What the user chose last for these words wins; otherwise the category most
// of the group already carries, the newest breaking a tie.
function referenceOf(group: readonly Transaction[]): string | null {
  const sorted = [...group].sort(newestFirst)
  const chosen = sorted.find(
    tx => tx.categorizedBy === 'USER' && tx.categoryId !== null,
  )
  if (chosen) {
    return chosen.categoryId
  }
  const counts = new Map<string, number>()
  for (const tx of sorted) {
    if (tx.categoryId !== null) {
      counts.set(tx.categoryId, (counts.get(tx.categoryId) ?? 0) + 1)
    }
  }
  let best: string | null = null
  for (const [categoryId, count] of counts) {
    if (best === null || count > (counts.get(best) as number)) {
      best = categoryId
    }
  }
  return best
}

function confidenceOf(
  group: readonly Transaction[],
  categoryId: string | null,
): number | null {
  const scores = group
    .filter(tx => categoryId !== null && tx.categoryId === categoryId)
    .map(tx => tx.categoryConfidence ?? 0)
  return scores.length ? Math.max(...scores) : null
}

function groupBy<T>(items: readonly T[], keyOf: (item: T) => string) {
  const groups = new Map<string, T[]>()
  for (const item of items) {
    const key = keyOf(item)
    groups.set(key, [...(groups.get(key) ?? []), item])
  }
  return groups
}

function reviewGroup(
  id: string,
  members: readonly Scoped[],
  kind: EntityKind,
): ReviewGroupView | null {
  const all = members.map(member => member.transaction)
  const reference = referenceOf(all)
  const flagged = all
    .map(tx => ({ tx, reason: reasonOf(tx, reference) }))
    .filter(
      (entry): entry is { tx: Transaction; reason: ReviewReason } =>
        entry.reason !== null,
    )
  if (flagged.length === 0) {
    return null
  }
  const pending = flagged.map(entry => entry.tx).sort(newestFirst)
  const latest = pending[0] as Transaction
  const pattern = sharedPattern(pending)
  return {
    id,
    entityKind: kind,
    merchant: latest.merchant ?? latest.description,
    pattern: pattern?.pattern ?? '',
    counterparty: pattern?.counterparty ?? null,
    direction: directionOf(latest),
    count: pending.length,
    total: money(
      Money.of(
        pending.reduce((sum, tx) => sum + Math.abs(tx.amount.cents), 0),
        latest.amount.currency,
      ),
    ),
    reasons: [...new Set(flagged.map(entry => entry.reason))],
    suggestedCategoryId: reference,
    confidence: confidenceOf(all, reference),
    canCreateRule: pattern !== null,
    lastBookedOn: latest.bookedOn,
    transactionIds: pending.map(tx => tx.id),
  }
}

const byWeight = (a: ReviewGroupView, b: ReviewGroupView) =>
  b.count - a.count ||
  b.total.cents - a.total.cents ||
  a.merchant.localeCompare(b.merchant)

function suggestionId(
  entityId: string,
  rule: Pick<
    CategoryRule,
    'pattern' | 'counterparty' | 'direction' | 'categoryId'
  >,
): string {
  const target = rule.counterparty ? `#${rule.counterparty}` : rule.pattern
  return `${entityId}|${rule.direction}|${target}|${rule.categoryId}`
}

// One stored rule already labels every member the same way: nothing to add.
function covered(
  rules: readonly CategoryRule[],
  entityId: string,
  categoryId: string,
  members: readonly Transaction[],
): boolean {
  return rules.some(
    rule =>
      (rule.entityId === null || rule.entityId === entityId) &&
      rule.categoryId === categoryId &&
      members.every(tx => ruleMatches(rule, tx)),
  )
}

function suggestionOf(
  members: readonly Scoped[],
  context: {
    rules: readonly CategoryRule[]
    kinds: ReadonlyMap<string, EntityKind>
    dismissed: ReadonlySet<string>
  },
): RuleSuggestionView | null {
  const txs = members.map(member => member.transaction).sort(newestFirst)
  const latest = txs[0] as Transaction
  const categoryId = latest.categoryId as string
  const unanimous = txs.every(tx => tx.categoryId === categoryId)
  const entityId = (members[0] as Scoped).entityId
  const pattern = sharedPattern(txs)
  if (txs.length < MIN_REPEATS || !unanimous || pattern === null) {
    return null
  }
  const direction = directionOf(latest)
  const id = suggestionId(entityId, { ...pattern, direction, categoryId })
  if (
    context.dismissed.has(id) ||
    covered(context.rules, entityId, categoryId, txs)
  ) {
    return null
  }
  return {
    id,
    entityKind: context.kinds.get(entityId) as EntityKind,
    merchant: latest.merchant ?? latest.description,
    pattern: pattern.pattern,
    counterparty: pattern.counterparty,
    direction,
    categoryId,
    count: txs.length,
  }
}

export function makeCategoryReview(deps: ReviewDeps) {
  async function scoped(
    tenantId: string,
    kind: EntityKind | undefined,
    days: number,
  ): Promise<Scoped[]> {
    const scope = await insightScope(deps, tenantId, kind)
    if (scope.accounts.length === 0) {
      return []
    }
    const owner = new Map(
      scope.accounts.map(account => [account.id, account.entityId]),
    )
    const found = await deps.transactions.all(tenantId, {
      accountIds: [...owner.keys()],
      from: addDays(today(deps.clock.now()), -days),
    })
    return found
      .filter(tx => tx.transferGroupId === null && !tx.provisional)
      .map(transaction => ({
        transaction,
        entityId: owner.get(transaction.accountId) as string,
      }))
  }

  async function dismissedIds(tenantId: string): Promise<Set<string>> {
    const stored = await deps.documents.list<{ id: string }>(
      tenantId,
      RULE_SUGGESTIONS_DISMISSED,
    )
    return new Set(stored.map(entry => entry.id))
  }

  async function suggestions(
    tenantId: string,
    kind: EntityKind | undefined,
  ): Promise<RuleSuggestionView[]> {
    const chosen = (await scoped(tenantId, kind, SUGGESTION_DAYS)).filter(
      member =>
        member.transaction.categorizedBy === 'USER' &&
        member.transaction.categoryId !== null &&
        recurrenceKey(member.transaction) !== '',
    )
    const context = {
      rules: await deps.categories.listRules(tenantId),
      kinds: await entityKinds(deps, tenantId),
      dismissed: await dismissedIds(tenantId),
    }
    const clusters = groupBy(
      chosen,
      member =>
        `${member.entityId}|${directionOf(member.transaction)}|${recurrenceKey(member.transaction)}`,
    )
    return [...clusters.values()]
      .map(members => suggestionOf(members, context))
      .filter((entry): entry is RuleSuggestionView => entry !== null)
      .sort((a, b) => b.count - a.count || a.merchant.localeCompare(b.merchant))
  }

  async function queue(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<ReviewQueueView> {
    const kinds = await entityKinds(deps, tenantId)
    const members = await scoped(tenantId, kind, REVIEW_DAYS)
    const groups = groupBy(
      members,
      member => `${member.entityId}|${reviewKey(member.transaction)}`,
    )
    const views = [...groups]
      .map(([id, group]) =>
        reviewGroup(
          id,
          group,
          kinds.get((group[0] as Scoped).entityId) as EntityKind,
        ),
      )
      .filter((view): view is ReviewGroupView => view !== null)
      .sort(byWeight)
    return {
      pending: views.reduce((total, view) => total + view.count, 0),
      groups: views,
      suggestions: await suggestions(tenantId, kind),
    }
  }

  async function categorizeGroup(
    tenantId: string,
    input: z.infer<typeof categorizeGroupSchema>,
  ): Promise<CategorizeGroupResult> {
    required(
      await deps.categories.findById(tenantId, input.categoryId),
      'Category',
    )
    const txs: Transaction[] = []
    for (const id of new Set(input.transactionIds)) {
      txs.push(
        required(await deps.transactions.findById(tenantId, id), 'Transaction'),
      )
    }
    const owners = new Set<string>()
    for (const tx of txs) {
      const account = required(
        await deps.accounts.findById(tenantId, tx.accountId),
        'Account',
      )
      owners.add(account.entityId)
    }
    const labeled = txs.filter(tx => tx.transferGroupId === null)
    const pattern = input.createRule ? sharedPattern(labeled) : null
    const directions = new Set(labeled.map(directionOf))
    if (pattern !== null && (owners.size !== 1 || directions.size !== 1)) {
      throw new ValidationError(
        'A rule needs transactions of one entity and one direction.',
      )
    }
    for (const tx of labeled) {
      await deps.transactions.save(
        categorize(tx, {
          categoryId: input.categoryId,
          by: 'USER',
          confidence: 1,
        }),
      )
    }
    if (pattern === null) {
      return { updated: labeled.length, similarUpdated: 0, rule: null }
    }
    const [entityId] = owners
    const rule = (await learnRule(
      deps,
      tenantId,
      entityId as string,
      pattern.pattern,
      input.categoryId,
      {
        counterparty: pattern.counterparty,
        direction: directionOf(labeled[0] as Transaction),
      },
    )) as CategoryRule
    const accountIds = await accountIdsOf(deps, tenantId, rule.entityId)
    const similarUpdated = await applyRule(
      deps,
      tenantId,
      rule,
      accountIds,
      null,
    )
    const kinds = await entityKinds(deps, tenantId)
    return {
      updated: labeled.length,
      similarUpdated,
      rule: toCategoryRuleView(rule, kinds),
    }
  }

  async function findSuggestion(
    tenantId: string,
    id: string,
  ): Promise<RuleSuggestionView> {
    const all = await suggestions(tenantId, undefined)
    return required(
      all.find(suggestion => suggestion.id === id) ?? null,
      'Rule suggestion',
    )
  }

  async function acceptSuggestion(
    tenantId: string,
    id: string,
  ): Promise<CategorizeGroupResult> {
    const suggestion = await findSuggestion(tenantId, id)
    const entityId = id.slice(0, id.indexOf('|'))
    const rule = (await learnRule(
      deps,
      tenantId,
      entityId,
      suggestion.pattern,
      suggestion.categoryId,
      {
        counterparty: suggestion.counterparty,
        direction: suggestion.direction,
      },
    )) as CategoryRule
    const accountIds = await accountIdsOf(deps, tenantId, entityId)
    const similarUpdated = await applyRule(
      deps,
      tenantId,
      rule,
      accountIds,
      null,
    )
    const kinds = await entityKinds(deps, tenantId)
    return {
      updated: 0,
      similarUpdated,
      rule: toCategoryRuleView(rule, kinds),
    }
  }

  async function dismissSuggestion(
    tenantId: string,
    id: string,
  ): Promise<{ id: string }> {
    await findSuggestion(tenantId, id)
    await deps.documents.put(tenantId, RULE_SUGGESTIONS_DISMISSED, id, {
      id,
      at: deps.clock.now().toISOString(),
    })
    return { id }
  }

  return {
    queue,
    categorizeGroup,
    acceptSuggestion,
    dismissSuggestion,
  }
}
