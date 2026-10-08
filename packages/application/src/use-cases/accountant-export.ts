import {
  type Bill,
  type BillKind,
  type LocalDate,
  Money,
} from '@cashdeck/domain'
import {
  type ExportItemKind,
  type ExportPeriodQuery,
  type ExportPlanView,
  type ExportRecordView,
  type ExportUnit,
  type GenerateExportInput,
} from '@/dtos/accountant-export'
import { type AttachmentMeta } from '@/ports/records'
import { type ArchiveEntry } from '@/ports/services'
import { type Deps } from '@/use-cases/deps'
import { brlOf } from '@/use-cases/invoices'
import { PAYROLL_COLLECTION, type PayrollEntry } from '@/use-cases/payroll'
import {
  addMonths,
  allPages,
  firstDay,
  lastDay,
  monthOf,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'

export type ExportRecord = {
  id: string
  from: LocalDate
  to: LocalDate
  items: ExportItemKind[]
  sentTo: string | null
  sentOn: LocalDate
  createdAt: string
}

type Range = { from: LocalDate; to: LocalDate }

type ItemContents = {
  kind: ExportItemKind
  unit: ExportUnit
  count: number
  csv: string
  attachments: AttachmentMeta[]
}

export const EXPORT_COLLECTION = 'accountant-exports'

const TAX_KINDS: readonly BillKind[] = ['TAX_BARCODE', 'DARF_NO_BARCODE']
const encoder = new TextEncoder()

const cell = (value: string | number | null) => {
  const text = value === null ? '' : String(value)
  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

export function toCsv(
  header: readonly string[],
  rows: ReadonlyArray<ReadonlyArray<string | number | null>>,
) {
  return [header, ...rows].map(row => row.map(cell).join(',')).join('\n') + '\n'
}

const decimal = (cents: number) => (cents / 100).toFixed(2)

function monthsOf(range: Range): string[] {
  const months: string[] = []
  for (
    let month = monthOf(range.from);
    month <= monthOf(range.to);
    month = addMonths(month, 1)
  ) {
    months.push(month)
  }
  return months
}

export function exportRange(query: ExportPeriodQuery, day: LocalDate): Range {
  const month = monthOf(day)
  switch (query.period) {
    case 'LAST_MONTH': {
      const last = addMonths(month, -1)
      return { from: firstDay(last), to: lastDay(last) }
    }
    case 'LAST_QUARTER': {
      const offset = (Number(month.slice(5)) - 1) % 3
      const start = addMonths(month, -offset - 3)
      return { from: firstDay(start), to: lastDay(addMonths(start, 2)) }
    }
    case 'CUSTOM':
      return { from: query.from as LocalDate, to: query.to as LocalDate }
  }
}

const downloadPath = (id: string) => `/api/v1/accountant-export/${id}/download`

const toRecordView = (record: ExportRecord): ExportRecordView => ({
  id: record.id,
  month: firstDay(monthOf(record.from)),
  sentOn: record.sentOn,
  to: record.sentTo,
  downloadPath: downloadPath(record.id),
})

type ExportDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'invoices'
  | 'bills'
  | 'attachments'
  | 'documents'
  | 'archives'
  | 'clock'
  | 'ids'
>

export function makeAccountantExport(deps: ExportDeps) {
  async function statements(
    tenantId: string,
    entityId: string,
    range: Range,
  ): Promise<ItemContents> {
    const accounts = await deps.accounts.listByEntity(tenantId, entityId)
    const lines = []
    for (const account of accounts) {
      const rows = await deps.transactions.all(tenantId, {
        accountIds: [account.id],
        from: range.from,
        to: range.to,
      })
      lines.push(
        ...rows.map(row => [
          account.name,
          row.bookedOn,
          row.description,
          decimal(row.amount.cents),
        ]),
      )
    }
    return {
      kind: 'STATEMENTS',
      unit: 'ACCOUNTS',
      count: accounts.length,
      csv: toCsv(['account', 'date', 'description', 'amount'], lines),
      attachments: [],
    }
  }

  async function invoices(
    tenantId: string,
    entityId: string,
    range: Range,
  ): Promise<ItemContents> {
    const rows = await deps.invoices.all(tenantId, {
      entityId,
      competenceFrom: monthOf(range.from),
      competenceTo: monthOf(range.to),
    })
    const lines = []
    for (const invoice of rows) {
      const client = await deps.invoices.findClient(tenantId, invoice.clientId)
      lines.push([
        invoice.number,
        invoice.status,
        invoice.competence,
        invoice.issueOn,
        client?.name ?? null,
        invoice.serviceCode,
        decimal(invoice.amount.cents),
        invoice.amount.currency,
        decimal(brlOf(invoice).cents),
        invoice.isExport ? 'yes' : 'no',
      ])
    }
    return {
      kind: 'INVOICES',
      unit: 'DOCUMENTS',
      count: rows.length,
      csv: toCsv(
        [
          'number',
          'status',
          'competence',
          'issued_on',
          'client',
          'service_code',
          'amount',
          'currency',
          'amount_brl',
          'export',
        ],
        lines,
      ),
      attachments: [],
    }
  }

  async function bills(
    tenantId: string,
    entityId: string,
    range: Range,
    kind: 'TAX_GUIDES' | 'EXPENSES',
  ): Promise<ItemContents> {
    const all = await allPages(page =>
      deps.bills.list(tenantId, { entityId }, page),
    )
    const isTax = (bill: Bill) => TAX_KINDS.includes(bill.kind)
    const rows = all.filter(
      bill =>
        bill.dueDate >= range.from &&
        bill.dueDate <= range.to &&
        isTax(bill) === (kind === 'TAX_GUIDES'),
    )
    const attachments: AttachmentMeta[] = []
    for (const bill of rows) {
      attachments.push(...(await deps.attachments.list(tenantId, bill.id)))
    }
    return {
      kind,
      unit: 'DOCUMENTS',
      count: rows.length,
      csv: toCsv(
        ['due_date', 'payee', 'kind', 'status', 'amount', 'paid_at'],
        rows.map(bill => [
          bill.dueDate,
          bill.payee,
          bill.kind,
          bill.status,
          decimal(bill.amount.cents),
          bill.paidAt?.toISOString() ?? null,
        ]),
      ),
      attachments,
    }
  }

  async function payroll(
    tenantId: string,
    range: Range,
  ): Promise<ItemContents> {
    const months = new Set(monthsOf(range))
    const entries = (
      await deps.documents.list<PayrollEntry>(tenantId, PAYROLL_COLLECTION)
    )
      .filter(entry => months.has(entry.month))
      .sort((a, b) => a.month.localeCompare(b.month))
    return {
      kind: 'PAYROLL',
      unit: 'MONTHS',
      count: entries.length,
      csv: toCsv(
        ['month', 'pro_labore', 'salaries', 'fgts'],
        entries.map(entry => [
          entry.month,
          decimal(entry.proLaboreCents),
          decimal(entry.salariesCents),
          decimal(entry.fgtsCents),
        ]),
      ),
      attachments: [],
    }
  }

  // Invoiced revenue against the bank receipts linked to those invoices.
  async function reconciliation(
    tenantId: string,
    entityId: string,
    range: Range,
  ): Promise<ItemContents> {
    const months = monthsOf(range)
    const issued = await deps.invoices.all(tenantId, {
      entityId,
      status: 'ISSUED',
      competenceFrom: months[0],
      competenceTo: months.at(-1),
    })
    const accounts = await deps.accounts.listByEntity(tenantId, entityId)
    const received = await deps.transactions.all(tenantId, {
      accountIds: accounts.map(account => account.id),
    })
    const lines = months.map(month => {
      const ofMonth = issued.filter(invoice => invoice.competence === month)
      const ids = new Set(ofMonth.map(invoice => invoice.id))
      const invoiced = ofMonth.reduce(
        (sum, invoice) => sum.add(brlOf(invoice)),
        Money.zero(),
      )
      const paid = received
        .filter(row => row.invoiceId !== null && ids.has(row.invoiceId))
        .reduce((sum, row) => sum + row.amount.cents, 0)
      return [
        month,
        ofMonth.length,
        decimal(invoiced.cents),
        decimal(paid),
        decimal(invoiced.cents - paid),
      ]
    })
    return {
      kind: 'RECONCILIATION',
      unit: 'MONTHS',
      count: months.length,
      csv: toCsv(['month', 'invoices', 'invoiced', 'received', 'gap'], lines),
      attachments: [],
    }
  }

  async function contents(
    tenantId: string,
    range: Range,
    kind: ExportItemKind,
  ): Promise<ItemContents> {
    const company = await requireEntity(deps.entities, tenantId, 'PJ')
    switch (kind) {
      case 'STATEMENTS':
        return statements(tenantId, company.id, range)
      case 'INVOICES':
        return invoices(tenantId, company.id, range)
      case 'TAX_GUIDES':
      case 'EXPENSES':
        return bills(tenantId, company.id, range, kind)
      case 'PAYROLL':
        return payroll(tenantId, range)
      case 'RECONCILIATION':
        return reconciliation(tenantId, company.id, range)
    }
  }

  const ALL_KINDS: readonly ExportItemKind[] = [
    'STATEMENTS',
    'INVOICES',
    'TAX_GUIDES',
    'EXPENSES',
    'PAYROLL',
    'RECONCILIATION',
  ]

  async function plan(
    tenantId: string,
    query: ExportPeriodQuery,
  ): Promise<ExportPlanView> {
    const range = exportRange(query, today(deps.clock.now()))
    const items = []
    for (const kind of ALL_KINDS) {
      const item = await contents(tenantId, range, kind)
      items.push({
        kind,
        count: item.count,
        unit: item.unit,
        files: 1 + item.attachments.length,
        bytes:
          encoder.encode(item.csv).length +
          item.attachments.reduce((sum, file) => sum + file.size, 0),
        selectedByDefault: kind !== 'RECONCILIATION',
      })
    }
    return { ...range, items }
  }

  async function generate(
    tenantId: string,
    input: GenerateExportInput,
  ): Promise<ExportRecordView> {
    const day = today(deps.clock.now())
    const range = exportRange(input, day)
    const record: ExportRecord = {
      id: deps.ids.next(),
      ...range,
      items: [...new Set(input.items)],
      sentTo: input.sentTo ?? null,
      sentOn: day,
      createdAt: deps.clock.now().toISOString(),
    }
    await deps.documents.put(tenantId, EXPORT_COLLECTION, record.id, record)
    return toRecordView(record)
  }

  async function history(tenantId: string): Promise<ExportRecordView[]> {
    const records = await deps.documents.list<ExportRecord>(
      tenantId,
      EXPORT_COLLECTION,
    )
    return records
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
      .map(toRecordView)
  }

  async function attachmentEntries(
    tenantId: string,
    folder: string,
    metas: readonly AttachmentMeta[],
  ): Promise<ArchiveEntry[]> {
    const entries: ArchiveEntry[] = []
    for (const meta of metas) {
      const file = await deps.attachments.find(tenantId, meta.id)
      if (file) {
        entries.push({
          name: `${folder}/${meta.id}-${meta.fileName}`,
          content: file.bytes,
        })
      }
    }
    return entries
  }

  async function download(tenantId: string, id: string) {
    const record = required(
      await deps.documents.get<ExportRecord>(tenantId, EXPORT_COLLECTION, id),
      'Export',
    )
    const entries: ArchiveEntry[] = []
    for (const kind of record.items) {
      const item = await contents(tenantId, record, kind)
      const folder = kind.toLowerCase().replaceAll('_', '-')
      entries.push(
        { name: `${folder}.csv`, content: item.csv },
        ...(await attachmentEntries(tenantId, folder, item.attachments)),
      )
    }
    return {
      fileName: `cashdeck-${record.from}-${record.to}.zip`,
      bytes: deps.archives.zip(entries),
    }
  }

  return { plan, generate, history, download }
}
