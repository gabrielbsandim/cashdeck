import {
  type Bill,
  createPaymentPlan,
  type PaymentPlan,
  type RailId,
  routePayment,
} from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { type PaymentRail } from '@/ports/payment-rail'
import {
  type FinancialEntityRepository,
  type PaymentRepository,
  type PaymentSettingsProvider,
} from '@/ports/repositories'

export type RailRegistry = ReadonlyMap<RailId, PaymentRail>

export type BuildPaymentPlanDeps = {
  entities: FinancialEntityRepository
  payments: PaymentRepository
  settings: PaymentSettingsProvider
  rails: RailRegistry
}

export function makeBuildPaymentPlan(deps: BuildPaymentPlanDeps) {
  return async function buildPaymentPlan(
    tenantId: string,
    bill: Bill,
  ): Promise<PaymentPlan> {
    const entity = await deps.entities.findById(tenantId, bill.entityId)
    if (!entity) {
      throw new NotFoundError('Entity')
    }
    const settings = await deps.settings.get(tenantId, entity.id)
    const enabled = new Set(settings.enabledRails)
    const steps = routePayment(
      {
        entityKind: entity.kind,
        billKind: bill.kind,
        hasPixCode: bill.pixCode !== null,
      },
      (rail, kind) =>
        enabled.has(rail) &&
        deps.rails.get(rail)?.supports(kind, entity.kind) === true,
    )
    const plan = createPaymentPlan(bill.id, steps)
    await deps.payments.savePlan(tenantId, plan)
    return plan
  }
}
