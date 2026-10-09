import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { type IssuedInvoice } from '@/ports/providers'
import { fullDeps, invoice } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeInvoiceLifecycle } from '@/use-cases/invoice-lifecycle'
import { makeIssueInvoice } from '@/use-cases/invoices'

const REASON = 'Amount issued by mistake'

const issued = (overrides: Partial<IssuedInvoice> = {}): IssuedInvoice => ({
  externalId: 'ext-1',
  number: '42',
  status: 'ISSUED',
  pdfUrl: 'https://issuer.test/ext-1.pdf',
  xmlUrl: 'https://issuer.test/ext-1.xml',
  ...overrides,
})

function setup() {
  const deps = fullDeps()
  return { deps, lifecycle: makeInvoiceLifecycle(deps) }
}

const text = (bytes: Uint8Array) => new TextDecoder().decode(bytes)

describe('invoice lifecycle', () => {
  it('polls processing invoices and stores the documents once issued', async () => {
    const { deps, lifecycle } = setup()
    deps.issuer.issued.set('ext-1', issued())
    deps.issuer.issued.set(
      'ext-2',
      issued({
        externalId: 'ext-2',
        status: 'PROCESSING',
        number: null,
        pdfUrl: null,
        xmlUrl: null,
      }),
    )
    await deps.invoices.save(
      invoice({ id: 'a', status: 'PROCESSING', externalId: 'ext-1' }),
    )
    await deps.invoices.save(
      invoice({ id: 'b', status: 'PROCESSING', externalId: 'ext-2' }),
    )
    await deps.invoices.save(
      invoice({ id: 'c', status: 'PROCESSING', externalId: 'missing' }),
    )
    await deps.invoices.save(invoice({ id: 'd', status: 'PROCESSING' }))

    const result = await lifecycle.poll(TENANT)
    expect(result).toMatchObject({ checked: 4, changed: 1 })
    expect(result.failures).toEqual([
      { invoiceId: 'c', reason: expect.stringContaining('missing') },
    ])
    expect(await deps.invoices.findById(TENANT, 'a')).toMatchObject({
      status: 'ISSUED',
      number: '42',
      pdfUrl: 'https://issuer.test/ext-1.pdf',
    })
    const pdf = await deps.invoices.findFile(TENANT, 'a', 'PDF')
    expect(pdf).toMatchObject({
      fileName: 'nfse-42.pdf',
      mimeType: 'application/pdf',
    })
    expect(text(pdf?.bytes ?? new Uint8Array())).toBe(
      'document:https://issuer.test/ext-1.pdf',
    )
    expect(await deps.invoices.findFile(TENANT, 'a', 'XML')).toMatchObject({
      fileName: 'nfse-42.xml',
      mimeType: 'application/xml',
    })
    expect(deps.audit.events.map(event => event.action)).toEqual([
      'invoice.status',
    ])
    expect(await deps.invoices.findFile(TENANT, 'b', 'PDF')).toBeNull()
  })

  it('refreshes by external id and keeps known values', async () => {
    const { deps, lifecycle } = setup()
    deps.issuer.issued.set(
      'ext-1',
      issued({ number: null, pdfUrl: null, xmlUrl: null }),
    )
    await deps.invoices.save(
      invoice({
        id: 'a',
        externalId: 'ext-1',
        number: '7',
        pdfUrl: 'https://issuer.test/a.pdf',
      }),
    )
    const refreshed = await lifecycle.refreshExternal(TENANT, 'ext-1')
    expect(refreshed).toMatchObject({
      number: '7',
      pdfUrl: 'https://issuer.test/a.pdf',
      xmlUrl: null,
    })
    expect(deps.audit.events).toHaveLength(0)
    expect(await deps.invoices.findFile(TENANT, 'a', 'PDF')).not.toBeNull()
    await lifecycle.refreshExternal(TENANT, 'ext-1')
    expect(await lifecycle.refreshExternal(TENANT, 'unknown')).toBeNull()
  })

  it('keeps going when a document download fails', async () => {
    const { deps, lifecycle } = setup()
    deps.issuer.download = async () => {
      throw new Error('offline')
    }
    deps.issuer.issued.set('ext-1', issued())
    await deps.invoices.save(
      invoice({ id: 'a', status: 'PROCESSING', externalId: 'ext-1' }),
    )
    expect((await lifecycle.poll(TENANT)).changed).toBe(1)
    expect(await deps.invoices.findFile(TENANT, 'a', 'PDF')).toBeNull()
  })

  it('serves stored documents and fetches missing ones on demand', async () => {
    const { deps, lifecycle } = setup()
    await deps.invoices.save(
      invoice({ id: 'a', number: null, xmlUrl: 'https://issuer.test/a.xml' }),
    )
    const xml = await lifecycle.file(TENANT, 'a', 'XML')
    expect(xml.fileName).toBe('nfse-a.xml')
    expect(await lifecycle.file(TENANT, 'a', 'XML')).toBe(
      await deps.invoices.findFile(TENANT, 'a', 'XML'),
    )
    await expect(lifecycle.file(TENANT, 'a', 'PDF')).rejects.toThrow(
      NotFoundError,
    )
    await expect(lifecycle.file(TENANT, 'nope', 'PDF')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('cancels drafts locally and issued invoices at the issuer', async () => {
    const { deps, lifecycle } = setup()
    deps.issuer.issued.set('ext-1', issued())
    await deps.invoices.save(invoice({ id: 'draft', status: 'DRAFT' }))
    await deps.invoices.save(
      invoice({ id: 'done', status: 'ISSUED', externalId: 'ext-1' }),
    )
    await deps.invoices.save(
      invoice({ id: 'busy', status: 'PROCESSING', externalId: 'ext-1' }),
    )

    expect(await lifecycle.cancel(TENANT, 'draft', REASON)).toMatchObject({
      status: 'CANCELLED',
      cancelReason: REASON,
    })
    expect(await lifecycle.cancel(TENANT, 'done', REASON)).toMatchObject({
      status: 'CANCELLED',
    })
    expect(deps.issuer.issued.get('ext-1')?.status).toBe('CANCELLED')
    expect(
      deps.audit.events.map(event => [
        event.action,
        event.actor,
        event.details.from,
      ]),
    ).toEqual([
      ['invoice.cancel', 'USER', 'DRAFT'],
      ['invoice.cancel', 'USER', 'ISSUED'],
    ])
    await expect(lifecycle.cancel(TENANT, 'busy', REASON)).rejects.toThrow(
      ValidationError,
    )
    await expect(lifecycle.cancel(TENANT, 'nope', REASON)).rejects.toThrow(
      NotFoundError,
    )
  })

  it('stores the documents when an invoice is issued at once', async () => {
    const deps = fullDeps()
    deps.issuer.issue = async () => issued()
    await deps.invoices.saveClient({
      id: 'client',
      tenantId: TENANT,
      entityId: 'pj',
      name: 'Client',
      taxId: '11222333000181',
      country: 'BR',
    })
    await deps.invoices.save(invoice({ id: 'a', status: 'DRAFT' }))
    await makeIssueInvoice(deps)(TENANT, 'a')
    expect(await deps.invoices.findFile(TENANT, 'a', 'PDF')).not.toBeNull()
    expect(await deps.invoices.findFile(TENANT, 'a', 'XML')).not.toBeNull()
  })
})
