import { type z } from 'zod'
import { type AutomationView, type updateAutomationSchema } from '@/dtos/rails'
import { type Deps } from '@/use-cases/deps'
import { requireEntity } from '@/use-cases/shared'

type AutomationStatus = { pausedAt: string | null }

// Undefined keeps the stored value; null is a deliberate "no limit".
const keep = <T>(given: T | undefined, current: T): T =>
  given === undefined ? current : given

const COLLECTION = 'automation'
const STATUS_ID = 'status'

export function makeAutomation(
  deps: Pick<Deps, 'entities' | 'settings' | 'documents' | 'clock'>,
) {
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
  async function setPaused(tenantId: string, paused: boolean) {
    for (const entity of await deps.entities.list(tenantId)) {
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
    return get(tenantId)
  }

  async function update(
    tenantId: string,
    input: z.infer<typeof updateAutomationSchema>,
  ): Promise<AutomationView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    const settings = await deps.settings.get(tenantId, entity.id)
    await deps.settings.save(tenantId, entity.id, {
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
    })
    return get(tenantId)
  }

  return {
    get,
    pause: (tenantId: string) => setPaused(tenantId, true),
    resume: (tenantId: string) => setPaused(tenantId, false),
    update,
  }
}
