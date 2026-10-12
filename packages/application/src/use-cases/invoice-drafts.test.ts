import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { updateInvoiceDraftSchema } from '@/dtos/invoices'
import { NotFoundError } from '@/errors/errors'
import { fullDeps, invoice } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeInvoiceDrafts } from '@/use-cases/invoice-drafts'

async function setup() {
  const deps = fullDeps()
  await deps.invoices.saveClient({
    id: 'client',
    tenantId: TENANT,
    entityId: 'pj',
    name: 'Client Example',
    taxId: '11222333000181',
    country: 'BR',
  })
  await deps.invoices.save(
    invoice({ id: 'draft', status: 'DRAFT', templateId: 'template' }),
  )
  return { deps, drafts: makeInvoiceDrafts(deps) }
}

describe('invoice drafts', () => {
  it('reads an invoice with its client and service', async () => {
    const { drafts } = await setup()
    expect(await drafts.get(TENANT, 'draft')).toMatchObject({
      id: 'draft',
      client: 'Client Example',
      clientTaxId: '11222333000181',
      clientCountry: 'BR',
      description: 'Software development',
      serviceCode: '01.01',
      status: 'DRAFT',
      recurring: true,
    })
  })

  it('edits a draft and keeps what the patch leaves out', async () => {
    const { deps, drafts } = await setup()
    const edited = await drafts.update(TENANT, 'draft', {
      description: 'Maintenance',
      amountCents: 250000,
      issueOn: '2026-10-05',
      competence: '2026-10',
    })
    expect(edited).toMatchObject({
      client: 'Client Example',
      description: 'Maintenance',
      serviceCode: '01.01',
      amount: { cents: 250000, currency: 'BRL' },
      issueOn: '2026-10-05',
      competence: '2026-10',
      isExport: false,
    })
    expect(await deps.invoices.findById(TENANT, 'draft')).toMatchObject({
      templateId: 'template',
      status: 'DRAFT',
    })
    expect(deps.audit.events.at(-1)).toMatchObject({
      action: 'invoice.update',
      actor: 'USER',
      subjectId: 'draft',
      details: {
        fields: ['description', 'amountCents', 'issueOn', 'competence'],
      },
    })
  })

  it('moves a draft to a foreign client as an export, dropping the old rate', async () => {
    const { deps, drafts } = await setup()
    await deps.invoices.save(
      invoice({
        id: 'usd',
        status: 'DRAFT',
        amount: Money.of(1000, 'USD'),
        fxRate: 5.4,
      }),
    )
    const kept = await drafts.update(TENANT, 'usd', { serviceCode: '01.06' })
    expect((await deps.invoices.findById(TENANT, 'usd'))?.fxRate).toBe(5.4)
    expect(kept.serviceCode).toBe('01.06')

    const moved = await drafts.update(TENANT, 'usd', {
      client: { name: 'Example Inc', country: 'US' },
      currency: 'EUR',
    })
    expect(moved).toMatchObject({
      client: 'Example Inc',
      clientCountry: 'US',
      clientTaxId: null,
      isExport: true,
      amount: { cents: 1000, currency: 'EUR' },
    })
    expect((await deps.invoices.findById(TENANT, 'usd'))?.fxRate).toBeNull()
  })

  it('keeps the client id of a draft whose client is gone', async () => {
    const { deps, drafts } = await setup()
    await deps.invoices.save(
      invoice({ id: 'orphan', status: 'DRAFT', clientId: 'gone' }),
    )
    const edited = await drafts.update(TENANT, 'orphan', { amountCents: 5 })
    expect(edited).toMatchObject({
      client: '',
      clientTaxId: null,
      clientCountry: 'BR',
      isExport: false,
    })
    expect((await deps.invoices.findById(TENANT, 'orphan'))?.clientId).toBe(
      'gone',
    )
  })

  it('refuses anything but a draft of the company', async () => {
    const { deps, drafts } = await setup()
    await deps.invoices.save(invoice({ id: 'issued' }))
    await deps.invoices.save(
      invoice({ id: 'other', status: 'DRAFT', entityId: 'pf' }),
    )
    await expect(
      drafts.update(TENANT, 'issued', { amountCents: 1 }),
    ).rejects.toBeInstanceOf(ValidationError)
    await expect(
      drafts.update(TENANT, 'other', { amountCents: 1 }),
    ).rejects.toBeInstanceOf(NotFoundError)
    await expect(drafts.get(TENANT, 'missing')).rejects.toBeInstanceOf(
      NotFoundError,
    )
  })

  it('validates a patch like the template form', () => {
    expect(updateInvoiceDraftSchema.safeParse({}).success).toBe(false)
    expect(updateInvoiceDraftSchema.safeParse({ amountCents: 0 }).success).toBe(
      false,
    )
    expect(
      updateInvoiceDraftSchema.safeParse({ currency: 'real' }).success,
    ).toBe(false)
    expect(
      updateInvoiceDraftSchema.safeParse({ issueOn: '2026-10-05' }).success,
    ).toBe(true)
  })
})
