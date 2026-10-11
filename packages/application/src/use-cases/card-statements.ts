import {
  createTransaction,
  installmentSuffix,
  type EntityKind,
  Money,
  ValidationError,
} from '@cashdeck/domain'
import { type z } from 'zod'
import {
  type CardStatementView,
  type importStatementSchema,
  type statementBillSchema,
  type StatementPostView,
  type statementPostSchema,
  statementReadingSchema,
} from '@/dtos/card-statements'
import { money } from '@/dtos/common'
import { type LlmToolParameter } from '@/ports/llm-provider'
import { type Deps } from '@/use-cases/deps'
import { makeCaptureBill } from '@/use-cases/capture-bill'
import { confirmPreview, pairMovements } from '@/use-cases/preview-feed'
import { cardClosedAlert, emitAlert } from '@/use-cases/alert-events'
import {
  decodeUpload,
  required,
  requireEntity,
  requireEntityById,
} from '@/use-cases/shared'

export type StoredStatement = {
  id: string
  entityId: string
  card: string
  issuer: string
  closing: string
  due: string
  currency: string
  rate: number
  iofBps: number
  paymentCode: string | null
  // What the bill asks, in cents; absent on statements stored before it was read.
  totalCents?: number
  lines: Array<{
    id: string
    merchant: string
    date: string
    amountCents: number
    needsReview: boolean
  }>
  billId: string | null
  // Absent on statements stored before lines could be posted.
  accountId?: string | null
  createdAt: string
}

const COLLECTION = 'card-statements'
export const STATEMENT_ID_PREFIX = 'statement:'
const RATE_SCALE = 10_000

const text = (description: string): LlmToolParameter => ({
  type: 'string',
  description,
})

const READING_SCHEMA: LlmToolParameter = {
  type: 'object',
  properties: {
    card: text('Card name and last digits as printed'),
    issuer: text('Card issuer'),
    closing: text('Closing date, YYYY-MM-DD'),
    due: text('Due date, YYYY-MM-DD'),
    currency: text('ISO 4217 currency of the line amounts'),
    rate: { type: 'number', description: 'BRL per unit of the currency' },
    iofPercent: { type: 'number', description: 'IOF rate in percent' },
    paymentCode: text('Boleto digitable line, or empty'),
    total: { type: 'number', description: 'Total due on this bill, in BRL' },
    lines: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          merchant: text(
            'Merchant as printed, with an installment such as (02/04)',
          ),
          date: text('Purchase date, YYYY-MM-DD'),
          amount: {
            type: 'number',
            description:
              'Amount, positive purchase, negative payment or refund',
          },
          uncertain: { type: 'boolean', description: 'Unsure about this line' },
        },
        required: ['merchant', 'date', 'amount', 'uncertain'],
      },
    },
  },
  required: [
    'card',
    'issuer',
    'closing',
    'due',
    'currency',
    'rate',
    'iofPercent',
    'total',
    'lines',
  ],
}

const SYSTEM = [
  'You read credit card statements for a personal finance app.',
  'Return only what the document shows. Never invent lines.',
  'Mark a line uncertain when any of its fields is hard to read.',
].join(' ')

type StatementDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'documents'
  | 'llm'
  | 'bills'
  | 'cardBills'
  | 'audit'
  | 'pixLocations'
  | 'payments'
  | 'settings'
  | 'rails'
  | 'clock'
  | 'ids'
> &
  Partial<Pick<Deps, 'alerts'>>

export function makeCardStatements(deps: StatementDeps) {
  const capture = makeCaptureBill(deps)

  async function view(tenantId: string, statement: StoredStatement) {
    const entity = await requireEntityById(
      deps.entities,
      tenantId,
      statement.entityId,
    )
    return toView(statement, entity.kind)
  }

  async function read(
    tenantId: string,
    input: z.infer<typeof importStatementSchema>,
  ): Promise<CardStatementView> {
    const entity = await requireEntity(deps.entities, tenantId, input.entity)
    decodeUpload(input.base64)
    const reply = await deps.llm.chat({
      system: SYSTEM,
      messages: [
        {
          role: 'user',
          content: 'Read this card statement.',
          attachments: [{ mimeType: input.mimeType, dataBase64: input.base64 }],
        },
      ],
      tools: [],
      maxInputTokens: 60_000,
      maxOutputTokens: 8_000,
      temperature: 0,
      responseSchema: READING_SCHEMA,
    })
    const parsed = statementReadingSchema.safeParse(reply.object)
    if (!parsed.success) {
      throw new ValidationError('The statement could not be read.')
    }
    const reading = parsed.data
    const statement: StoredStatement = {
      id: deps.ids.next(),
      entityId: entity.id,
      card: reading.card,
      issuer: reading.issuer,
      closing: reading.closing,
      due: reading.due,
      currency: reading.currency,
      rate: Math.round(reading.rate * RATE_SCALE),
      iofBps: Math.round(reading.iofPercent * 100),
      paymentCode: reading.paymentCode || null,
      totalCents: Math.round(reading.total * 100),
      lines: reading.lines.map(line => ({
        id: deps.ids.next(),
        merchant: line.merchant,
        date: line.date,
        amountCents: Math.round(line.amount * 100),
        needsReview: line.uncertain,
      })),
      billId: null,
      accountId: null,
      createdAt: deps.clock.now().toISOString(),
    }
    await deps.documents.put(tenantId, COLLECTION, statement.id, statement)
    await emitAlert(deps.alerts, cardClosedAlert(tenantId, statement))
    return toView(statement, entity.kind)
  }

  async function latest(tenantId: string): Promise<CardStatementView | null> {
    const all = await deps.documents.list<StoredStatement>(tenantId, COLLECTION)
    const open = all
      .filter(statement => statement.billId === null)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    return open[0] ? view(tenantId, open[0]) : null
  }

  async function find(tenantId: string, id: string): Promise<StoredStatement> {
    return required(
      await deps.documents.get<StoredStatement>(tenantId, COLLECTION, id),
      'Card statement',
    )
  }

  async function get(tenantId: string, id: string): Promise<CardStatementView> {
    return view(tenantId, await find(tenantId, id))
  }

  async function createBill(
    tenantId: string,
    id: string,
    input: z.infer<typeof statementBillSchema>,
  ) {
    const statement = await find(tenantId, id)
    if (statement.billId !== null) {
      throw new ValidationError('This statement already has a bill.')
    }
    const totals = statementTotals(statement, new Set(input.lineIds))
    const paymentCode = input.paymentCode ?? statement.paymentCode ?? undefined
    if (!paymentCode && !input.pixKey) {
      throw new ValidationError('Send the payment code or the Pix key.')
    }
    const { bill } = await capture(tenantId, {
      entityId: statement.entityId,
      source: 'MANUAL',
      paymentCode: input.pixKey ? undefined : paymentCode,
      pixKey: input.pixKey,
      amountCents: totals.total.cents,
      dueDate: statement.due,
      payee: `${statement.issuer} ${statement.card}`,
    })
    await deps.documents.put(tenantId, COLLECTION, id, {
      ...statement,
      billId: bill.id,
    })
    return {
      billId: bill.id,
      foreign: money(totals.foreign),
      subtotal: money(totals.subtotal),
      iof: money(totals.iof),
      total: money(totals.total),
    }
  }

  // Each line confirms the preview a notification left for it, or lands as a
  // new charge; previews no line matched are handed back for review.
  async function post(
    tenantId: string,
    id: string,
    input: z.infer<typeof statementPostSchema>,
  ): Promise<StatementPostView> {
    const statement = await find(tenantId, id)
    const account = required(
      await deps.accounts.findById(tenantId, input.accountId),
      'Account',
    )
    if (
      account.type !== 'CREDIT_CARD' ||
      account.entityId !== statement.entityId
    ) {
      throw new ValidationError(
        'Statement lines go to a card account of the same entity.',
      )
    }
    const selected = new Set(input.lineIds)
    const lines = keyedLines(statement).filter(({ line }) =>
      selected.has(line.id),
    )
    if (lines.length === 0) {
      throw new ValidationError('Pick at least one line of the statement.')
    }
    const incoming = lines.map(({ line, key }) => {
      const split = installmentSuffix(line.merchant)
      const description = split?.description ?? line.merchant
      return createTransaction({
        id: deps.ids.next(),
        tenantId,
        accountId: account.id,
        amount: Money.of(
          -Math.round((line.amountCents * statement.rate) / RATE_SCALE),
        ),
        // A later installment is charged on this bill, not on the purchase day.
        bookedOn: split && split.number > 1 ? statement.closing : line.date,
        description,
        externalId: key,
        merchant: description,
        installment: split && {
          number: split.number,
          count: split.count,
          purchaseOn: line.date,
        },
      })
    })
    const stored = await deps.transactions.all(tenantId, {
      accountIds: [account.id],
    })
    const previews = stored.filter(tx => tx.provisional)
    const known = new Set(
      stored.filter(tx => !tx.provisional).map(tx => tx.externalId),
    )
    const fresh = incoming.filter(tx => !known.has(tx.externalId))
    const pairs = pairMovements(fresh, previews)
    for (const [line, preview] of pairs) {
      await deps.transactions.save({
        ...confirmPreview(preview, line),
        installment: preview.installment ?? line.installment,
      })
    }
    const pairedLines = new Set(pairs.map(([line]) => line))
    const added = await deps.transactions.saveNew(
      fresh.filter(tx => !pairedLines.has(tx)),
    )
    const pairedPreviews = new Set(pairs.map(([, preview]) => preview))
    const unmatched = previews.filter(
      tx => !pairedPreviews.has(tx) && tx.bookedOn <= statement.closing,
    )
    await deps.cardBills.saveAll([
      {
        id: deps.ids.next(),
        tenantId,
        accountId: account.id,
        externalId: `${STATEMENT_ID_PREFIX}${statement.id}`,
        closesOn: statement.closing,
        dueOn: statement.due,
        total: Money.of(statement.totalCents ?? billedCents(statement)),
        minimum: null,
      },
    ])
    await deps.documents.put(tenantId, COLLECTION, id, {
      ...statement,
      accountId: account.id,
    })
    return {
      confirmed: pairs.length,
      added,
      unmatched: unmatched.map(tx => ({
        id: tx.id,
        description: tx.description,
        bookedOn: tx.bookedOn,
        amount: money(tx.amount),
      })),
    }
  }

  return { read, latest, get, createBill, post }
}

// The AI may name a merchant differently on a second read of the same PDF,
// so a line's key leaves it out and posting that PDF again stores nothing new.
function keyedLines(statement: StoredStatement) {
  const seen = new Map<string, number>()
  return statement.lines.map(line => {
    const base = `${STATEMENT_ID_PREFIX}${statement.closing}:${line.date}:${line.amountCents}`
    const count = (seen.get(base) ?? 0) + 1
    seen.set(base, count)
    return { line, key: `${base}:${count}` }
  })
}

const billedCents = (statement: StoredStatement) =>
  statementTotals(statement, new Set(statement.lines.map(line => line.id)))
    .total.cents

export function statementTotals(
  statement: StoredStatement,
  selected: Set<string>,
) {
  const picked = statement.lines.filter(line => selected.has(line.id))
  if (picked.length === 0) {
    throw new ValidationError('Pick at least one line of the statement.')
  }
  const foreignCents = picked.reduce((sum, line) => sum + line.amountCents, 0)
  const subtotal = Money.of(
    Math.round((foreignCents * statement.rate) / RATE_SCALE),
  )
  const iof = Money.of(
    Math.round((subtotal.cents * statement.iofBps) / RATE_SCALE),
  )
  return {
    foreign: Money.of(foreignCents, statement.currency),
    subtotal,
    iof,
    total: subtotal.add(iof),
  }
}

function toView(
  statement: StoredStatement,
  kind: EntityKind,
): CardStatementView {
  return {
    id: statement.id,
    entityKind: kind,
    card: statement.card,
    issuer: statement.issuer,
    closing: statement.closing,
    due: statement.due,
    rate: statement.rate,
    iofBps: statement.iofBps,
    paymentCode: statement.paymentCode,
    lines: statement.lines.map(line => ({
      id: line.id,
      merchant: line.merchant,
      date: line.date,
      amount: money(Money.of(line.amountCents, statement.currency)),
      needsReview: line.needsReview,
    })),
    billId: statement.billId,
    accountId: statement.accountId ?? null,
  }
}
