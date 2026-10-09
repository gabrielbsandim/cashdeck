import { type FinancialEntity, Money, ValidationError } from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type createInvoiceTemplateSchema,
  type InvoiceTemplateView,
  type templateClientSchema,
  type updateInvoiceTemplateSchema,
} from '@/dtos/invoices'
import {
  type Invoice,
  type InvoiceClient,
  type InvoiceTemplate,
} from '@/ports/records'
import { type AuditEvent } from '@/ports/repositories'
import { type Deps } from '@/use-cases/deps'
import {
  lastDay,
  monthOf,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'

type TemplateDeps = Pick<
  Deps,
  'entities' | 'invoices' | 'audit' | 'clock' | 'ids'
>

type TemplateInput = z.infer<typeof createInvoiceTemplateSchema>
type TemplatePatch = z.infer<typeof updateInvoiceTemplateSchema>
type ClientInput = z.infer<typeof templateClientSchema>

export function cycleAmount(template: InvoiceTemplate): Money {
  if (template.billing === 'FIXED') {
    return template.amount
  }
  return Money.of(
    Math.round(template.amount.cents * (template.hours ?? 0)),
    template.amount.currency,
  )
}

function assertBilling(template: InvoiceTemplate): void {
  if (template.billing === 'HOURLY' && template.hours === null) {
    throw new ValidationError('An hourly template needs the hours per cycle.')
  }
}

async function templateAudit(
  deps: Pick<Deps, 'audit' | 'clock' | 'ids'>,
  template: InvoiceTemplate,
  event: Pick<AuditEvent, 'actor' | 'action' | 'result' | 'details'>,
): Promise<void> {
  await deps.audit.record({
    id: deps.ids.next(),
    tenantId: template.tenantId,
    subjectId: template.id,
    rail: null,
    at: deps.clock.now(),
    ...event,
  })
}

export function makeInvoiceTemplates(deps: TemplateDeps) {
  async function company(tenantId: string): Promise<FinancialEntity> {
    return requireEntity(deps.entities, tenantId, 'PJ')
  }

  async function clientFor(
    entity: FinancialEntity,
    input: ClientInput,
  ): Promise<InvoiceClient> {
    const existing = await deps.invoices.findClientByName(
      entity.tenantId,
      entity.id,
      input.name,
    )
    const client: InvoiceClient = {
      id: existing?.id ?? deps.ids.next(),
      tenantId: entity.tenantId,
      entityId: entity.id,
      name: input.name,
      taxId:
        input.taxId === undefined ? (existing?.taxId ?? null) : input.taxId,
      country: input.country ?? existing?.country ?? 'BR',
    }
    await deps.invoices.saveClient(client)
    return client
  }

  async function view(template: InvoiceTemplate): Promise<InvoiceTemplateView> {
    const client = await deps.invoices.findClient(
      template.tenantId,
      template.clientId,
    )
    return {
      id: template.id,
      client: {
        id: template.clientId,
        name: client?.name ?? '',
        taxId: client?.taxId ?? null,
        country: client?.country ?? 'BR',
      },
      description: template.description,
      serviceCode: template.serviceCode,
      amount: money(template.amount),
      billing: template.billing,
      hours: template.hours,
      cycleAmount: money(cycleAmount(template)),
      dayOfMonth: template.dayOfMonth,
      active: template.active,
    }
  }

  async function find(tenantId: string, id: string): Promise<InvoiceTemplate> {
    const entity = await company(tenantId)
    const template = required(
      await deps.invoices.findTemplate(tenantId, id),
      'Invoice template',
    )
    return required(
      template.entityId === entity.id ? template : null,
      'Invoice template',
    )
  }

  async function list(tenantId: string): Promise<InvoiceTemplateView[]> {
    const entity = await company(tenantId)
    const templates = await deps.invoices.listTemplates(tenantId, entity.id)
    const views: InvoiceTemplateView[] = []
    for (const template of templates) {
      views.push(await view(template))
    }
    return views
  }

  async function get(tenantId: string, id: string) {
    return view(await find(tenantId, id))
  }

  async function create(
    tenantId: string,
    input: TemplateInput,
  ): Promise<InvoiceTemplateView> {
    const entity = await company(tenantId)
    const client = await clientFor(entity, input.client)
    const template: InvoiceTemplate = {
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      clientId: client.id,
      serviceCode: input.serviceCode,
      description: input.description,
      amount: Money.of(input.amountCents, input.currency),
      billing: input.billing,
      hours: input.hours,
      dayOfMonth: input.dayOfMonth,
      active: input.active,
    }
    assertBilling(template)
    await deps.invoices.saveTemplate(template)
    await templateAudit(deps, template, {
      actor: 'USER',
      action: 'invoice-template.create',
      result: 'CREATED',
      details: { clientId: client.id, dayOfMonth: template.dayOfMonth },
    })
    return view(template)
  }

  async function update(
    tenantId: string,
    id: string,
    patch: TemplatePatch,
  ): Promise<InvoiceTemplateView> {
    const current = await find(tenantId, id)
    const entity = await company(tenantId)
    const client = patch.client ? await clientFor(entity, patch.client) : null
    const updated: InvoiceTemplate = {
      ...current,
      clientId: client?.id ?? current.clientId,
      serviceCode: patch.serviceCode ?? current.serviceCode,
      description: patch.description ?? current.description,
      amount: Money.of(
        patch.amountCents ?? current.amount.cents,
        patch.currency ?? current.amount.currency,
      ),
      billing: patch.billing ?? current.billing,
      hours: patch.hours === undefined ? current.hours : patch.hours,
      dayOfMonth: patch.dayOfMonth ?? current.dayOfMonth,
      active: patch.active ?? current.active,
    }
    assertBilling(updated)
    await deps.invoices.saveTemplate(updated)
    await templateAudit(deps, updated, {
      actor: 'USER',
      action: 'invoice-template.update',
      result: 'UPDATED',
      details: { fields: Object.keys(patch) },
    })
    return view(updated)
  }

  async function remove(tenantId: string, id: string) {
    const template = await find(tenantId, id)
    await deps.invoices.deleteTemplate(tenantId, template.id)
    await templateAudit(deps, template, {
      actor: 'USER',
      action: 'invoice-template.delete',
      result: 'DELETED',
      details: {},
    })
    return { id: template.id }
  }

  return { list, get, create, update, remove }
}

export type RecurringInvoicesResult = { templates: number; created: number }

// A template is due once its day has come this month (the last day stands in
// for days the month lacks), so a run after a weekend or an outage catches up.
function isDue(template: InvoiceTemplate, day: string): boolean {
  const monthLength = Number(lastDay(monthOf(day)).slice(8))
  return Number(day.slice(8)) >= Math.min(template.dayOfMonth, monthLength)
}

export function makeRecurringInvoices(
  deps: TemplateDeps & Pick<Deps, 'issuer'>,
) {
  return async function recurringInvoices(
    tenantId: string,
  ): Promise<RecurringInvoicesResult> {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    const now = deps.clock.now()
    const day = today(now)
    const month = monthOf(day)
    const active = (
      await deps.invoices.listTemplates(tenantId, entity.id)
    ).filter(template => template.active)
    const existing = await deps.invoices.all(tenantId, {
      entityId: entity.id,
      competenceFrom: month,
      competenceTo: month,
    })
    const drafted = new Set(existing.map(invoice => invoice.templateId))
    let created = 0
    for (const template of active) {
      if (!isDue(template, day) || drafted.has(template.id)) {
        continue
      }
      const client = await deps.invoices.findClient(tenantId, template.clientId)
      const draft: Invoice = {
        id: deps.ids.next(),
        tenantId,
        entityId: entity.id,
        clientId: template.clientId,
        templateId: template.id,
        issuer: deps.issuer.id,
        externalId: null,
        number: null,
        status: 'DRAFT',
        amount: cycleAmount(template),
        fxRate: null,
        isExport: (client?.country ?? 'BR') !== 'BR',
        competence: month,
        issueOn: day,
        description: template.description,
        serviceCode: template.serviceCode,
        pdfUrl: null,
        xmlUrl: null,
        createdAt: now,
      }
      await deps.invoices.save(draft)
      await templateAudit(deps, template, {
        actor: 'SYSTEM',
        action: 'invoice.draft',
        result: 'DRAFT',
        details: { invoiceId: draft.id, competence: month },
      })
      created += 1
    }
    return { templates: active.length, created }
  }
}
