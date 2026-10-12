import { type z } from 'zod'
import { type AutomationView, type updateAutomationSchema } from '@/dtos/rails'
import { type Actor, type PaymentSettings } from '@/ports/repositories'
import { type Deps } from '@/use-cases/deps'
import { requireEntity } from '@/use-cases/shared'

type AutomationStatus = { pausedAt: string | null }

// Undefined keeps the stored value; null is a deliberate "no limit".
const keep = <T>(given: T | undefined, current: T): T =>
  given === undefined ? current : given

const COLLECTION = 'automation'
const STATUS_ID = 'status'
const USER: Actor = { kind: 'USER', id: null, requestId: null }

const LIMITS = [
  'confirmAboveCents',
  'dailyCapCents',
  'entityDailyCapCents',
  'paymentCapCents',
  'maxDeviationPercent',
  'approvalCutoff',
] as const

function changedLimits(before: PaymentSettings, after: PaymentSettings) {
  const changed = LIMITS.filter(
    field => JSON.stringify(before[field]) !== JSON.stringify(after[field]),
  )
  return Object.fromEntries(
    changed.map(field => [field, { from: before[field], to: after[field] }]),
  )
}

export function makeAutomation(
  deps: Pick<
    Deps,
    'entities' | 'settings' | 'documents' | 'audit' | 'clock' | 'ids'
  >,
) {
  async function audit(
    tenantId: string,
    actor: Actor,
    fields: { action: string; subjectId: string; result: string },
    details: Record<string, unknown>,
  ): Promise<void> {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: actor.kind,
      actorId: actor.id,
      requestId: actor.requestId,
      rail: null,
      details,
      at: deps.clock.now(),
      ...fields,
    })
  }

  async function get(tenantId: string): Promise<AutomationView> {
    const status = await deps.documents.get<AutomationStatus>(
      tenantId,
      COLLECTION,
      STATUS_ID,
    )
    const entities = await deps.entities.list(tenantId)
    const views: AutomationView['entities'] = []
    for (const entity of entities.sort((a, b) =>
      a.kind.localeCompare(b.kind),
    )) {
      const settings = await deps.settings.get(tenantId, entity.id)
      views.push({
        entity: entity.kind,
        confirmAboveCents: settings.confirmAboveCents,
        dailyCapCents: settings.dailyCapCents,
        entityDailyCapCents: settings.entityDailyCapCents,
        paymentCapCents: settings.paymentCapCents,
        maxDeviationPercent: settings.maxDeviationPercent,
        approvalCutoff: settings.approvalCutoff,
      })
    }
    return { pausedSince: status?.pausedAt ?? null, entities: views }
  }

  // The kill switch: every entity falls to assisted until resumed.
  async function setPaused(tenantId: string, paused: boolean, actor: Actor) {
    const entities = await deps.entities.list(tenantId)
    for (const entity of entities) {
      const settings = await deps.settings.get(tenantId, entity.id)
      await deps.settings.save(tenantId, entity.id, {
        ...settings,
        killSwitch: paused,
      })
    }
    await deps.documents.put<AutomationStatus>(
      tenantId,
      COLLECTION,
      STATUS_ID,
      {
        pausedAt: paused ? deps.clock.now().toISOString() : null,
      },
    )
    await audit(
      tenantId,
      actor,
      {
        action: paused ? 'automation.paused' : 'automation.resumed',
        subjectId: tenantId,
        result: paused ? 'PAUSED' : 'RESUMED',
      },
      { entities: entities.map(entity => entity.id) },
    )
    return get(tenantId)
  }

  async function update(
    tenantId: string,
    input: z.infer<typeof updateAutomationSchema>,
    actor: Actor = USER,
  ): Promise<AutomationView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const settings = await deps.settings.get(tenantId, entity.id)
    const next: PaymentSettings = {
      ...settings,
      confirmAboveCents: keep(
        input.confirmAboveCents,
        settings.confirmAboveCents,
      ),
      dailyCapCents: input.dailyCapCents ?? settings.dailyCapCents,
      entityDailyCapCents: keep(
        input.entityDailyCapCents,
        settings.entityDailyCapCents,
      ),
      paymentCapCents: keep(input.paymentCapCents, settings.paymentCapCents),
      maxDeviationPercent: keep(
        input.maxDeviationPercent,
        settings.maxDeviationPercent,
      ),
      approvalCutoff: input.approvalCutoff ?? settings.approvalCutoff,
    }
    await deps.settings.save(tenantId, entity.id, next)
    await audit(
      tenantId,
      actor,
      {
        action: 'automation.limits_updated',
        subjectId: entity.id,
        result: 'UPDATED',
      },
      { changes: changedLimits(settings, next) },
    )
    return get(tenantId)
  }

  return {
    get,
    pause: (tenantId: string, actor: Actor = USER) =>
      setPaused(tenantId, true, actor),
    resume: (tenantId: string, actor: Actor = USER) =>
      setPaused(tenantId, false, actor),
    update,
  }
}
