import { ValidationError } from '@cashdeck/domain'
import { type IssuedInvoice } from '@/ports/providers'
import {
  INVOICE_FILE_KINDS,
  type Invoice,
  type InvoiceFile,
  type InvoiceFileKind,
} from '@/ports/records'
import { type AuditEvent } from '@/ports/repositories'
import { emitAlert, invoiceAlert } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import { required } from '@/use-cases/shared'

type LifecycleDeps = Pick<
  Deps,
  'invoices' | 'issuer' | 'audit' | 'clock' | 'ids'
> &
  Partial<Pick<Deps, 'alerts'>>

export type InvoicePollResult = {
  checked: number
  changed: number
  failures: Array<{ invoiceId: string; reason: string }>
}

const FILES: Record<
  InvoiceFileKind,
  {
    mimeType: string
    extension: string
    url: (invoice: Invoice) => string | null
  }
> = {
  PDF: {
    mimeType: 'application/pdf',
    extension: 'pdf',
    url: invoice => invoice.pdfUrl,
  },
  XML: {
    mimeType: 'application/xml',
    extension: 'xml',
    url: invoice => invoice.xmlUrl,
  },
}

export function makeInvoiceLifecycle(deps: LifecycleDeps) {
  async function audit(
    invoice: Invoice,
    event: Pick<AuditEvent, 'actor' | 'action' | 'result' | 'details'>,
  ): Promise<void> {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: invoice.tenantId,
      subjectId: invoice.id,
      rail: null,
      at: deps.clock.now(),
      ...event,
    })
  }

  async function storeFile(
    invoice: Invoice,
    kind: InvoiceFileKind,
  ): Promise<InvoiceFile | null> {
    const spec = FILES[kind]
    const url = spec.url(invoice)
    if (invoice.status !== 'ISSUED' || !url) {
      return null
    }
    const bytes = await deps.issuer.download(url)
    const file: InvoiceFile = {
      tenantId: invoice.tenantId,
      invoiceId: invoice.id,
      kind,
      fileName: `nfse-${invoice.number ?? invoice.id}.${spec.extension}`,
      mimeType: spec.mimeType,
      size: bytes.length,
      bytes,
      createdAt: deps.clock.now(),
    }
    await deps.invoices.saveFile(file)
    return file
  }

  // A failed download is not fatal: the PDF and XML routes fetch on demand.
  async function storeFiles(invoice: Invoice): Promise<number> {
    let stored = 0
    for (const kind of INVOICE_FILE_KINDS) {
      const existing = await deps.invoices.findFile(
        invoice.tenantId,
        invoice.id,
        kind,
      )
      const file = existing
        ? null
        : await storeFile(invoice, kind).catch(() => null)
      stored += file ? 1 : 0
    }
    return stored
  }

  async function apply(
    invoice: Invoice,
    issued: IssuedInvoice,
  ): Promise<Invoice> {
    const updated: Invoice = {
      ...invoice,
      status: issued.status,
      number: issued.number ?? invoice.number,
      pdfUrl: issued.pdfUrl ?? invoice.pdfUrl,
      xmlUrl: issued.xmlUrl ?? invoice.xmlUrl,
    }
    await deps.invoices.save(updated)
    if (updated.status !== invoice.status) {
      await audit(updated, {
        actor: 'SYSTEM',
        action: 'invoice.status',
        result: updated.status,
        details: { from: invoice.status, externalId: invoice.externalId },
      })
      const client = await deps.invoices.findClient(
        updated.tenantId,
        updated.clientId,
      )
      await emitAlert(deps.alerts, invoiceAlert(updated, client?.name ?? ''))
    }
    await storeFiles(updated)
    return updated
  }

  async function refresh(invoice: Invoice): Promise<Invoice> {
    if (!invoice.externalId) {
      return invoice
    }
    return apply(invoice, await deps.issuer.get(invoice.externalId))
  }

  async function refreshExternal(
    tenantId: string,
    externalId: string,
  ): Promise<Invoice | null> {
    const invoice = await deps.invoices.findByExternalId(tenantId, externalId)
    return invoice && refresh(invoice)
  }

  async function poll(tenantId: string): Promise<InvoicePollResult> {
    const waiting = await deps.invoices.all(tenantId, { status: 'PROCESSING' })
    const result: InvoicePollResult = { checked: 0, changed: 0, failures: [] }
    for (const invoice of waiting) {
      result.checked += 1
      try {
        const updated = await refresh(invoice)
        result.changed += updated.status === invoice.status ? 0 : 1
      } catch (error) {
        result.failures.push({ invoiceId: invoice.id, reason: String(error) })
      }
    }
    return result
  }

  async function cancelIssued(invoice: Invoice, reason: string) {
    const issued = await deps.issuer.cancel(
      invoice.externalId as string,
      reason,
    )
    return { ...invoice, status: issued.status }
  }

  const CANCELLERS: Partial<
    Record<
      Invoice['status'],
      (invoice: Invoice, reason: string) => Promise<Invoice>
    >
  > = {
    DRAFT: async invoice => ({ ...invoice, status: 'CANCELLED' }),
    ISSUED: cancelIssued,
  }

  async function cancel(
    tenantId: string,
    invoiceId: string,
    reason: string,
  ): Promise<Invoice> {
    const invoice = required(
      await deps.invoices.findById(tenantId, invoiceId),
      'Invoice',
    )
    const canceller = CANCELLERS[invoice.status]
    if (!canceller) {
      throw new ValidationError(
        'Only a draft or an issued invoice can be cancelled.',
      )
    }
    const cancelled = {
      ...(await canceller(invoice, reason)),
      cancelReason: reason,
    }
    await deps.invoices.save(cancelled)
    await audit(cancelled, {
      actor: 'USER',
      action: 'invoice.cancel',
      result: cancelled.status,
      details: { externalId: invoice.externalId, from: invoice.status, reason },
    })
    return cancelled
  }

  async function file(
    tenantId: string,
    invoiceId: string,
    kind: InvoiceFileKind,
  ): Promise<InvoiceFile> {
    const invoice = required(
      await deps.invoices.findById(tenantId, invoiceId),
      'Invoice',
    )
    const stored = await deps.invoices.findFile(tenantId, invoice.id, kind)
    return stored ?? required(await storeFile(invoice, kind), 'Invoice file')
  }

  return { refresh, refreshExternal, poll, cancel, file, storeFiles }
}
