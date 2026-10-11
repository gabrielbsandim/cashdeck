import { type EntityKind } from '@cashdeck/domain'
import { type CardBillsView } from '@/dtos/insights'
import { cardBillsOf } from '@/use-cases/card-cycle'
import { type Deps } from '@/use-cases/deps'
import { insightScope } from '@/use-cases/insights'
import { today } from '@/use-cases/shared'

type CardBillDeps = Pick<Deps, 'entities' | 'accounts' | 'cardBills' | 'clock'>

export function makeListCardBills(deps: CardBillDeps) {
  return async function listCardBills(
    tenantId: string,
    kind?: EntityKind,
  ): Promise<CardBillsView> {
    const day = today(deps.clock.now())
    const scope = await insightScope(deps, tenantId, kind)
    const cards = scope.accounts.filter(
      account => account.type === 'CREDIT_CARD',
    )
    if (cards.length === 0) {
      return { cards: [] }
    }
    const stored = await deps.cardBills.list(
      tenantId,
      cards.map(card => card.id),
    )
    const kinds = new Map(
      scope.entities.map(entity => [entity.id, entity.kind]),
    )
    return {
      cards: cards.map(card => ({
        accountId: card.id,
        name: card.name,
        suffix: card.numberSuffix,
        entityKind: kinds.get(card.entityId) as EntityKind,
        bills: cardBillsOf(
          card,
          stored.filter(bill => bill.accountId === card.id),
          day,
        ),
      })),
    }
  }
}
