import { Money, ValidationError } from '@cashdeck/domain'
import { type z } from 'zod'
import {
  type InvoiceDetailView,
  type updateInvoiceDraftSchema,
} from '@/dtos/invoices'
import { type Invoice } from '@/ports/records'
import { type Deps } from '@/use-cases/deps'
import { toInvoiceView } from '@/use-cases/invoices'
import { isExportFor, saveClientFor } from '@/use-cases/invoice-templates'
import { required, requireEntity } from '@/use-cases/shared'

type DraftDeps = Pick<Deps, 'entities' | 'invoices' | 'audit' | 'clock' | 'ids'>

type DraftPatch = z.infer<typeof updateInvoiceDraftSchema>

export function makeInvoiceDrafts(deps: DraftDeps) {
  async function find(tenantId: string, id: string) {
    const entity = await requireEntity(deps.entities, tenantId, 'PJ')
    const invoice = await deps.invoices.findById(tenantId, id)
    const owned = invoice?.entityId === entity.id ? invoice : null
    return { entity, invoice: required(owned, 'Invoice') }
  }

  async function view(invoice: Invoice): Promise<InvoiceDetailView> {
    const client = await deps.invoices.findClient(
      invoice.tenantId,
      invoice.clientId,
    )
    return {
      ...toInvoiceView(invoice, client),
      clientTaxId: client?.taxId ?? null,
      clientCountry: client?.country ?? 'BR',
      description: invoice.description,
      serviceCode: invoice.serviceCode,
    }
  }

  async function get(tenantId: string, id: string) {
    return view((await find(tenantId, id)).invoice)
  }

  // Export and the exchange rate follow the client and the currency the same
  // way a drafted template sets them, so issuing reads them as if new.
  async function update(
    tenantId: string,
    id: string,
    patch: DraftPatch,
  ): Promise<InvoiceDetailView> {
    const { entity, invoice } = await find(tenantId, id)
    if (invoice.status !== 'DRAFT') {
      throw new ValidationError('Only a draft invoice can be edited.')
    }
    const client = patch.client
      ? await saveClientFor(deps, entity, patch.client)
      : await deps.invoices.findClient(tenantId, invoice.clientId)
    const amount = Money.of(
      patch.amountCents ?? invoice.amount.cents,
      patch.currency ?? invoice.amount.currency,
    )
    const sameCurrency = amount.currency === invoice.amount.currency
    const updated: Invoice = {
      ...invoice,
      clientId: client?.id ?? invoice.clientId,
      description: patch.description ?? invoice.description,
      serviceCode: patch.serviceCode ?? invoice.serviceCode,
      amount,
      fxRate: sameCurrency ? invoice.fxRate : null,
      isExport: isExportFor(client),
      issueOn: patch.issueOn ?? invoice.issueOn,
      competence: patch.competence ?? invoice.competence,
    }
    await deps.invoices.save(updated)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'USER',
      action: 'invoice.update',
      subjectId: invoice.id,
      rail: null,
      result: 'UPDATED',
      details: { fields: Object.keys(patch) },
      at: deps.clock.now(),
    })
    return view(updated)
  }

  return { get, update }
}
