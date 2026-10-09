import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { fullDeps, invoice } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeCompanySummary } from '@/use-cases/home'
import {
  cycleAmount,
  makeInvoiceTemplates,
  makeRecurringInvoices,
} from '@/use-cases/invoice-templates'

const INPUT = {
  client: { name: 'Example Inc', taxId: 'EIN-12-3456789', country: 'US' },
  description: 'Software development',
  serviceCode: '01.01',
  amountCents: 500000,
  currency: 'USD',
  billing: 'FIXED' as const,
  hours: null,
  dayOfMonth: 5,
  active: true,
}

function setup() {
  const deps = fullDeps()
  return {
    deps,
    templates: makeInvoiceTemplates(deps),
    recurring: makeRecurringInvoices(deps),
  }
}

describe('invoice templates', () => {
  it('creates, lists, reads, updates and deletes with audit events', async () => {
    const { deps, templates } = setup()
    const created = await templates.create(TENANT, INPUT)
    expect(created).toMatchObject({
      client: { name: 'Example Inc', taxId: 'EIN-12-3456789', country: 'US' },
      amount: { cents: 500000, currency: 'USD' },
      cycleAmount: { cents: 500000 },
      dayOfMonth: 5,
      active: true,
    })
    expect(await templates.list(TENANT)).toHaveLength(1)
    expect((await templates.get(TENANT, created.id)).id).toBe(created.id)

    const hourly = await templates.update(TENANT, created.id, {
      billing: 'HOURLY',
      amountCents: 10000,
      hours: 120.5,
      client: { name: 'Example Inc' },
    })
    expect(hourly).toMatchObject({
      billing: 'HOURLY',
      hours: 120.5,
      cycleAmount: { cents: 1205000, currency: 'USD' },
      client: { id: created.client.id, taxId: 'EIN-12-3456789', country: 'US' },
    })
    const paused = await templates.update(TENANT, created.id, {
      active: false,
      currency: 'EUR',
      description: 'Consulting',
      serviceCode: '01.06',
      dayOfMonth: 31,
    })
    expect(paused).toMatchObject({
      active: false,
      hours: 120.5,
      amount: { currency: 'EUR' },
      description: 'Consulting',
    })
    expect(await templates.remove(TENANT, created.id)).toEqual({
      id: created.id,
    })
    expect(await templates.list(TENANT)).toEqual([])
    expect(deps.audit.events.map(event => event.action)).toEqual([
      'invoice-template.create',
      'invoice-template.update',
      'invoice-template.update',
      'invoice-template.delete',
    ])
  })

  it('creates a new client and refuses hourly templates without hours', async () => {
    const { deps, templates } = setup()
    const created = await templates.create(TENANT, {
      ...INPUT,
      client: { name: 'Cliente Exemplo' },
      currency: 'BRL',
    })
    expect(created.client).toMatchObject({ taxId: null, country: 'BR' })
    const moved = await templates.update(TENANT, created.id, {
      client: { name: 'Other Client', taxId: null },
    })
    expect(moved.client.name).toBe('Other Client')
    await expect(
      templates.create(TENANT, { ...INPUT, billing: 'HOURLY' }),
    ).rejects.toThrow(ValidationError)
    await expect(
      templates.update(TENANT, created.id, { billing: 'HOURLY' }),
    ).rejects.toThrow(ValidationError)
    await deps.invoices.saveTemplate({
      ...(await deps.invoices.findTemplate(TENANT, created.id))!,
      id: 'foreign',
      entityId: 'pf',
    })
    await expect(templates.get(TENANT, 'foreign')).rejects.toThrow(
      NotFoundError,
    )
    await expect(templates.remove(TENANT, 'missing')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('shows an unknown client as empty', async () => {
    const { deps, templates } = setup()
    await deps.invoices.saveTemplate({
      id: 'orphan',
      tenantId: TENANT,
      entityId: 'pj',
      clientId: 'gone',
      serviceCode: '01.01',
      description: 'Work',
      amount: Money.of(100),
      billing: 'HOURLY',
      hours: null,
      dayOfMonth: 1,
      active: true,
    })
    expect(await templates.get(TENANT, 'orphan')).toMatchObject({
      client: { name: '', taxId: null, country: 'BR' },
      cycleAmount: { cents: 0 },
    })
  })
})

describe('recurring invoices', () => {
  it('drafts each due template once a month and shows it on the company home', async () => {
    const { deps, templates, recurring } = setup()
    const due = await templates.create(TENANT, INPUT)
    const later = await templates.create(TENANT, { ...INPUT, dayOfMonth: 20 })
    await templates.create(TENANT, { ...INPUT, active: false })
    const domestic = await templates.create(TENANT, {
      ...INPUT,
      client: {
        name: 'Cliente Exemplo',
        taxId: '11222333000181',
        country: 'BR',
      },
      currency: 'BRL',
      dayOfMonth: 8,
    })

    expect(await recurring(TENANT)).toEqual({ templates: 3, created: 2 })
    expect(await recurring(TENANT)).toEqual({ templates: 3, created: 0 })
    const drafts = await deps.invoices.all(TENANT, { status: 'DRAFT' })
    expect(drafts.map(draft => draft.templateId).sort()).toEqual(
      [due.id, domestic.id].sort(),
    )
    expect(drafts.find(draft => draft.templateId === due.id)).toMatchObject({
      competence: '2026-10',
      issueOn: '2026-10-08',
      isExport: true,
      issuer: 'fake',
      amount: Money.of(500000, 'USD'),
    })
    expect(drafts.find(d => d.templateId === domestic.id)?.isExport).toBe(false)
    expect(drafts.some(draft => draft.templateId === later.id)).toBe(false)
    expect(
      deps.audit.events.filter(e => e.action === 'invoice.draft'),
    ).toHaveLength(2)

    const home = await makeCompanySummary(deps)(TENANT)
    expect(home.drafts).toHaveLength(2)
    expect(home.drafts.every(draft => draft.recurring)).toBe(true)
  })

  it('treats a day the month lacks as its last day and skips cancelled drafts', async () => {
    const { deps, templates, recurring } = setup()
    deps.clock.set(new Date('2026-02-28T12:00:00Z'))
    const end = await templates.create(TENANT, { ...INPUT, dayOfMonth: 31 })
    const cancelled = await templates.create(TENANT, {
      ...INPUT,
      dayOfMonth: 1,
    })
    await deps.invoices.save(
      invoice({
        id: 'old',
        templateId: cancelled.id,
        status: 'CANCELLED',
        competence: '2026-02',
      }),
    )
    await deps.invoices.saveTemplate({
      ...(await deps.invoices.findTemplate(TENANT, end.id))!,
      id: 'ghost',
      clientId: 'gone',
    })
    expect(await recurring(TENANT)).toEqual({ templates: 3, created: 2 })
    const ghost = (await deps.invoices.all(TENANT, { status: 'DRAFT' })).find(
      draft => draft.templateId === 'ghost',
    )
    expect(ghost?.isExport).toBe(false)
  })

  it('computes the cycle amount', () => {
    const template = {
      id: 't',
      tenantId: TENANT,
      entityId: 'pj',
      clientId: 'c',
      serviceCode: '01.01',
      description: 'Work',
      amount: Money.of(15050, 'USD'),
      billing: 'HOURLY' as const,
      hours: 10,
      dayOfMonth: 1,
      active: true,
    }
    expect(cycleAmount(template).cents).toBe(150500)
    expect(cycleAmount({ ...template, billing: 'FIXED' }).cents).toBe(15050)
  })
})
