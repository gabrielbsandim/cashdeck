import {
  daysBetween,
  type FinancialEntity,
  type LocalDate,
  ValidationError,
} from '@cashdeck/domain'
import { type z } from 'zod'
import { money } from '@/dtos/common'
import {
  type InvoiceView,
  type issuerCertificateSchema,
  type IssuerSetupView,
  type listInvoicesQuerySchema,
  type saveIssuerSchema,
} from '@/dtos/invoices'
import { ProviderError } from '@/errors/errors'
import { type Invoice } from '@/ports/records'
import { type Page } from '@/ports/repositories'
import { emitAlert, invoiceAlert } from '@/use-cases/alert-events'
import { credentialName, putCredential } from '@/use-cases/credentials'
import { type Deps } from '@/use-cases/deps'
import { makeInvoiceLifecycle } from '@/use-cases/invoice-lifecycle'
import { issQuote } from '@/use-cases/revenue'
import {
  brlOf,
  decodeUpload,
  monthOf,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'

// LC 116/2003, item 1: the IT services a small company usually invoices.
export const SERVICE_CODES = [
  { code: '01.01', description: 'Análise e desenvolvimento de sistemas' },
  { code: '01.02', description: 'Programação' },
  {
    code: '01.03',
    description: 'Processamento, armazenamento ou hospedagem de dados',
  },
  { code: '01.04', description: 'Elaboração de programas de computadores' },
  {
    code: '01.05',
    description: 'Licenciamento ou cessão de direito de uso de programas',
  },
  { code: '01.06', description: 'Assessoria e consultoria em informática' },
  { code: '01.07', description: 'Suporte técnico em informática' },
  {
    code: '01.08',
    description: 'Planejamento, confecção e manutenção de páginas eletrônicas',
  },
] as const

export type IssuerSetup = {
  kind: IssuerSetupView['kind']
  city: string
  municipalRegistration: string
  serviceCode: string
  certificateName: string | null
  certificateExpiresOn: LocalDate | null
  certificateFingerprint: string | null
}

export const ISSUER_COLLECTION = 'issuer'

const EXPIRING_SOON_DAYS = 45

export function certificateStateOf(
  expiresOn: LocalDate | null,
  day: LocalDate,
): IssuerSetupView['certificateState'] {
  if (expiresOn === null) {
    return null
  }
  const days = daysBetween(day, expiresOn)
  if (days < 0) {
    return 'EXPIRED'
  }
  return days <= EXPIRING_SOON_DAYS ? 'EXPIRING_SOON' : 'VALID'
}

export function serviceCodeOf(code: string) {
  const known = SERVICE_CODES.find(candidate => candidate.code === code)
  return known ?? { code, description: code }
}

export function issuerCertificateSecret(entityId: string): string {
  return credentialName('NFSE_CERTIFICATE', entityId)
}

function toSetupView(setup: IssuerSetup, day: LocalDate): IssuerSetupView {
  return {
    kind: setup.kind,
    city: setup.city,
    certificateName: setup.certificateName,
    certificateExpiresOn: setup.certificateExpiresOn,
    certificateState: certificateStateOf(setup.certificateExpiresOn, day),
    municipalRegistration: setup.municipalRegistration,
    serviceCode: serviceCodeOf(setup.serviceCode),
  }
}

async function company(deps: Pick<Deps, 'entities'>, tenantId: string) {
  return requireEntity(deps.entities, tenantId, 'PJ')
}

export function makeIssuerSetup(
  deps: Pick<Deps, 'entities' | 'documents' | 'clock'>,
) {
  return {
    async get(tenantId: string): Promise<IssuerSetupView | null> {
      const entity = await company(deps, tenantId)
      const setup = await deps.documents.get<IssuerSetup>(
        tenantId,
        ISSUER_COLLECTION,
        entity.id,
      )
      return setup && toSetupView(setup, today(deps.clock.now()))
    },

    async save(
      tenantId: string,
      input: z.infer<typeof saveIssuerSchema>,
    ): Promise<IssuerSetupView> {
      const entity = await company(deps, tenantId)
      const current = await deps.documents.get<IssuerSetup>(
        tenantId,
        ISSUER_COLLECTION,
        entity.id,
      )
      const setup: IssuerSetup = {
        certificateName: null,
        certificateExpiresOn: null,
        certificateFingerprint: null,
        ...current,
        ...input,
      }
      await deps.documents.put(tenantId, ISSUER_COLLECTION, entity.id, setup)
      return toSetupView(setup, today(deps.clock.now()))
    },
  }
}

export function makeUploadIssuerCertificate(
  deps: Pick<
    Deps,
    'entities' | 'documents' | 'secrets' | 'vault' | 'certificates' | 'clock'
  >,
) {
  return async function uploadIssuerCertificate(
    tenantId: string,
    input: z.infer<typeof issuerCertificateSchema>,
  ): Promise<IssuerSetupView> {
    const entity = await company(deps, tenantId)
    const setup = required(
      await deps.documents.get<IssuerSetup>(
        tenantId,
        ISSUER_COLLECTION,
        entity.id,
      ),
      'Issuer setup',
    )
    const bytes = decodeUpload(input.base64)
    const facts = deps.certificates.inspect({ fileName: input.fileName, bytes })
    await putCredential(
      deps,
      tenantId,
      issuerCertificateSecret(entity.id),
      JSON.stringify({
        fileName: input.fileName,
        base64: input.base64,
        password: input.password,
      }),
    )
    const updated: IssuerSetup = {
      ...setup,
      certificateName: input.fileName,
      certificateExpiresOn: facts.validUntil ?? input.expiresOn,
      certificateFingerprint: facts.fingerprint,
    }
    await deps.documents.put(tenantId, ISSUER_COLLECTION, entity.id, updated)
    return toSetupView(updated, today(deps.clock.now()))
  }
}

export function makeTestIssuer(deps: Pick<Deps, 'issuer' | 'clock'>) {
  return async function testIssuer() {
    const started = deps.clock.now().getTime()
    const check = await deps.issuer.check()
    if (!check.ok) {
      throw new ProviderError(deps.issuer.id, check.message ?? 'check failed')
    }
    return {
      protocol: check.message ?? 'OK',
      elapsedMs: deps.clock.now().getTime() - started,
    }
  }
}

export function makeInvoiceViews(deps: Pick<Deps, 'invoices'>) {
  return async function invoiceViews(
    tenantId: string,
    invoices: readonly Invoice[],
  ): Promise<InvoiceView[]> {
    const views: InvoiceView[] = []
    for (const invoice of invoices) {
      const client = await deps.invoices.findClient(tenantId, invoice.clientId)
      views.push({
        id: invoice.id,
        client: client?.name ?? '',
        amount: money(invoice.amount),
        status: invoice.status,
        number: invoice.number,
        competence: invoice.competence,
        issueOn: invoice.issueOn,
        recurring: invoice.templateId !== null,
        isExport: invoice.isExport,
        pdfUrl: invoice.pdfUrl,
      })
    }
    return views
  }
}

export function makeListInvoices(deps: Pick<Deps, 'entities' | 'invoices'>) {
  const views = makeInvoiceViews(deps)
  return async function listInvoices(
    tenantId: string,
    query: z.infer<typeof listInvoicesQuerySchema>,
  ): Promise<Page<InvoiceView>> {
    const entity = await company(deps, tenantId)
    const page = await deps.invoices.list(
      tenantId,
      {
        entityId: entity.id,
        status: query.status,
        competenceFrom: query.month,
        competenceTo: query.month,
      },
      { cursor: query.cursor, limit: query.limit },
    )
    return {
      items: await views(tenantId, page.items),
      nextCursor: page.nextCursor,
    }
  }
}

export function makeIssueInvoice(
  deps: Pick<
    Deps,
    'invoices' | 'documents' | 'issuer' | 'audit' | 'clock' | 'ids'
  > &
    Partial<Pick<Deps, 'alerts'>>,
) {
  const lifecycle = makeInvoiceLifecycle(deps)
  return async function issueInvoice(
    tenantId: string,
    invoiceId: string,
  ): Promise<Invoice> {
    const invoice = required(
      await deps.invoices.findById(tenantId, invoiceId),
      'Invoice',
    )
    if (invoice.status !== 'DRAFT') {
      throw new ValidationError('Only a draft invoice can be issued.')
    }
    const client = required(
      await deps.invoices.findClient(tenantId, invoice.clientId),
      'Invoice client',
    )
    const quote = invoice.isExport
      ? null
      : await issQuote(deps, tenantId, invoice.entityId, invoice.competence)
    const issued = await deps.issuer.issue(
      {
        tenantId,
        entityId: invoice.entityId,
        clientName: client.name,
        clientTaxId: client.taxId,
        serviceCode: invoice.serviceCode,
        description: invoice.description,
        amountCents: invoice.amount.cents,
        currency: invoice.amount.currency,
        brlAmountCents: brlOf(invoice).cents,
        export: invoice.isExport,
        issRatePercent: quote?.ratePercent ?? null,
      },
      `invoice:${invoice.id}`,
    )
    const updated: Invoice = {
      ...invoice,
      issuer: deps.issuer.id,
      externalId: issued.externalId,
      number: issued.number,
      status: issued.status,
      pdfUrl: issued.pdfUrl,
      xmlUrl: issued.xmlUrl,
    }
    await deps.invoices.save(updated)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'USER',
      action: 'invoice.issue',
      subjectId: invoice.id,
      rail: null,
      result: issued.status,
      details: { externalId: issued.externalId, issuer: deps.issuer.id },
      at: deps.clock.now(),
    })
    await lifecycle.storeFiles(updated)
    await emitAlert(deps.alerts, invoiceAlert(updated, client.name))
    return updated
  }
}

// An income with no invoice yet becomes a draft for the same payer, then is
// issued; the receipt points at it so it leaves the unbilled list.
export function makeInvoiceReceipt(
  deps: Pick<
    Deps,
    | 'entities'
    | 'accounts'
    | 'transactions'
    | 'invoices'
    | 'documents'
    | 'issuer'
    | 'audit'
    | 'clock'
    | 'ids'
  >,
) {
  const issue = makeIssueInvoice(deps)
  return async function invoiceReceipt(
    tenantId: string,
    transactionId: string,
  ): Promise<Invoice> {
    const entity = await company(deps, tenantId)
    const receipt = required(
      await deps.transactions.findById(tenantId, transactionId),
      'Transaction',
    )
    const account = await deps.accounts.findById(tenantId, receipt.accountId)
    if (account?.entityId !== entity.id || !receipt.amount.isPositive()) {
      throw new ValidationError('Only a company income can be invoiced.')
    }
    if (receipt.invoiceId !== null) {
      throw new ValidationError('This income already has an invoice.')
    }
    const setup = required(
      await deps.documents.get<IssuerSetup>(
        tenantId,
        ISSUER_COLLECTION,
        entity.id,
      ),
      'Issuer setup',
    )
    const client = await clientNamed(deps, entity, receipt.description)
    const day = today(deps.clock.now())
    const draft: Invoice = {
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      clientId: client.id,
      templateId: null,
      issuer: deps.issuer.id,
      externalId: null,
      number: null,
      status: 'DRAFT',
      amount: receipt.amount,
      fxRate: null,
      isExport: receipt.amount.currency !== 'BRL',
      competence: monthOf(receipt.bookedOn),
      issueOn: day,
      description: serviceCodeOf(setup.serviceCode).description,
      serviceCode: setup.serviceCode,
      pdfUrl: null,
      xmlUrl: null,
      createdAt: deps.clock.now(),
    }
    await deps.invoices.save(draft)
    const issued = await issue(tenantId, draft.id)
    await deps.transactions.save({ ...receipt, invoiceId: issued.id })
    return issued
  }
}

async function clientNamed(
  deps: Pick<Deps, 'invoices' | 'ids'>,
  entity: FinancialEntity,
  name: string,
) {
  const existing = await deps.invoices.findClientByName(
    entity.tenantId,
    entity.id,
    name,
  )
  if (existing) {
    return existing
  }
  const client = {
    id: deps.ids.next(),
    tenantId: entity.tenantId,
    entityId: entity.id,
    name,
    taxId: null,
    country: 'BR',
  }
  await deps.invoices.saveClient(client)
  return client
}
