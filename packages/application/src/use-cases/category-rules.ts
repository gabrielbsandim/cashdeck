import {
  type CategoryRule,
  createCategoryRule,
  type EntityKind,
} from '@cashdeck/domain'
import { type z } from 'zod'
import {
  type CategoryRuleView,
  type updateCategoryRuleSchema,
} from '@/dtos/category-review'
import { type Deps } from '@/use-cases/deps'
import {
  accountIdsOf,
  applyRule,
  type RuleDeps,
} from '@/use-cases/categorization'
import { required } from '@/use-cases/shared'

export type CategoryRulesDeps = RuleDeps & Pick<Deps, 'entities' | 'accounts'>

export async function entityKinds(
  deps: Pick<Deps, 'entities'>,
  tenantId: string,
): Promise<Map<string, EntityKind>> {
  const entities = await deps.entities.list(tenantId)
  return new Map(entities.map(entity => [entity.id, entity.kind]))
}

export function toCategoryRuleView(
  rule: CategoryRule,
  kinds: ReadonlyMap<string, EntityKind>,
): CategoryRuleView {
  return {
    id: rule.id,
    entityKind: rule.entityId ? (kinds.get(rule.entityId) ?? null) : null,
    pattern: rule.pattern,
    counterparty: rule.counterparty,
    direction: rule.direction,
    minCents: rule.minCents,
    maxCents: rule.maxCents,
    categoryId: rule.categoryId,
    priority: rule.priority,
    createdAt: rule.createdAt.toISOString(),
  }
}

const labelOf = (rule: CategoryRule) => rule.pattern || `${rule.counterparty}`

export function makeCategoryRules(deps: CategoryRulesDeps) {
  async function find(tenantId: string, id: string): Promise<CategoryRule> {
    const rules = await deps.categories.listRules(tenantId)
    return required(rules.find(rule => rule.id === id) ?? null, 'Category rule')
  }

  async function list(tenantId: string): Promise<CategoryRuleView[]> {
    const kinds = await entityKinds(deps, tenantId)
    const rules = await deps.categories.listRules(tenantId)
    return [...rules]
      .sort((a, b) => labelOf(a).localeCompare(labelOf(b)))
      .map(rule => toCategoryRuleView(rule, kinds))
  }

  // New words replace a payee document, so the edited rule matches by text.
  async function update(
    tenantId: string,
    id: string,
    patch: z.infer<typeof updateCategoryRuleSchema>,
  ): Promise<{ rule: CategoryRuleView; updated: number }> {
    const current = await find(tenantId, id)
    if (patch.categoryId !== undefined) {
      required(
        await deps.categories.findById(tenantId, patch.categoryId),
        'Category',
      )
    }
    const rule = createCategoryRule({
      ...current,
      pattern: patch.pattern ?? current.pattern,
      counterparty: patch.pattern === undefined ? current.counterparty : null,
      direction:
        patch.direction === undefined ? current.direction : patch.direction,
      minCents:
        patch.minCents === undefined ? current.minCents : patch.minCents,
      maxCents:
        patch.maxCents === undefined ? current.maxCents : patch.maxCents,
      categoryId: patch.categoryId ?? current.categoryId,
    })
    await deps.categories.saveRule(rule)
    const accountIds = await accountIdsOf(deps, tenantId, rule.entityId)
    const updated = await applyRule(deps, tenantId, rule, accountIds, null)
    const kinds = await entityKinds(deps, tenantId)
    return { rule: toCategoryRuleView(rule, kinds), updated }
  }

  async function remove(tenantId: string, id: string): Promise<{ id: string }> {
    const rule = await find(tenantId, id)
    await deps.categories.deleteRule(tenantId, rule.id)
    return { id: rule.id }
  }

  return { list, update, remove }
}
