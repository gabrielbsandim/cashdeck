import {
  type Account,
  addDays,
  BILL_STATUSES,
  type Category,
  type EntityKind,
  isSettled,
  Money,
  normalizeDescription,
  type Transaction,
  ValidationError,
} from '@cashdeck/domain'
import { z } from 'zod'
import { NotFoundError } from '@/errors/errors'
import {
  type ChatAction,
  type ChatActionDetails,
  type ChatScope,
} from '@/ports/chat'
import { type LlmToolParameter } from '@/ports/llm-provider'
import { allPages, required, today } from '@/use-cases/shared'
import { type AgentTool } from '@/use-cases/chat/agent'
import { sanitize } from '@/use-cases/chat/hardening'
import { ensureCategories } from '@/use-cases/categorization'
import { type Deps } from '@/use-cases/deps'
import { isoDate } from '@/dtos/common'

export type Proposal = Pick<
  ChatAction,
  'tool' | 'entity' | 'needsEntity' | 'target'
> & { details: Partial<ChatActionDetails> }

// Everything here comes from the server: the thread decides the scope, so a
// tool argument can narrow a query but never widen it.
export type ToolContext = {
  tenantId: string
  threadId: string
  scope: ChatScope
  propose(proposal: Proposal): Promise<ChatAction>
}

type ToolDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'transactions'
  | 'categories'
  | 'bills'
  | 'chat'
  | 'clock'
  | 'ids'
>

const DEFAULT_DAYS = 30
const MAX_ROWS = 50
const UNCATEGORIZED = 'Uncategorized'

const text = (description: string): LlmToolParameter => ({
  type: 'string',
  description,
})
const day = (description: string) => text(`${description}, YYYY-MM-DD`)

const object = (
  properties: Record<string, LlmToolParameter>,
  required: string[] = [],
): LlmToolParameter => ({ type: 'object', properties, required })

export const scopeKind = (scope: ChatScope): EntityKind | null =>
  scope === 'ALL' ? null : scope

const decimal = (money: Money) => money.toDecimal()

const pendingReply = (action: ChatAction) => ({
  status: 'PENDING_CONFIRMATION',
  actionId: action.id,
  instruction:
    'Nothing was done yet. Tell the user to review and confirm the card shown in the app.',
})

type Lookup = {
  accounts: Account[]
  kindOf: Map<string, EntityKind>
  categories: Category[]
  categoryName(id: string | null): string
}

export function makeChatTools(deps: ToolDeps) {
  async function allowedEntities(
    ctx: ToolContext,
  ): Promise<Map<string, EntityKind>> {
    const entities = await deps.entities.list(ctx.tenantId)
    const kind = scopeKind(ctx.scope)
    return new Map(
      entities
        .filter(entity => kind === null || entity.kind === kind)
        .map(entity => [entity.id, entity.kind]),
    )
  }

  async function lookup(ctx: ToolContext): Promise<Lookup> {
    const allowed = await allowedEntities(ctx)
    const accounts = (await deps.accounts.list(ctx.tenantId)).filter(account =>
      allowed.has(account.entityId),
    )
    const kindOf = new Map(
      accounts.map(account => [
        account.id,
        allowed.get(account.entityId) as EntityKind,
      ]),
    )
    const categories = await ensureCategories(deps, ctx.tenantId)
    const names = new Map(categories.map(c => [c.id, c.name]))
    return {
      accounts,
      kindOf,
      categories,
      categoryName: id => (id === null ? UNCATEGORIZED : (names.get(id) ?? id)),
    }
  }

  function findCategory(found: Lookup, name: string): Category {
    const wanted = name.trim().toLowerCase()
    const match = found.categories.find(
      category =>
        category.name.toLowerCase() === wanted ||
        category.key?.toLowerCase() === wanted,
    )
    if (!match) {
      throw new ValidationError(
        `Unknown category. Use one of: ${found.categories.map(c => c.name).join(', ')}.`,
      )
    }
    return match
  }

  function row(found: Lookup, tx: Transaction) {
    return {
      id: tx.id,
      date: tx.bookedOn,
      description: sanitize(tx.description, 200),
      amount: decimal(tx.amount),
      currency: tx.amount.currency,
      category: found.categoryName(tx.categoryId),
      entity: found.kindOf.get(tx.accountId),
      note: tx.note && sanitize(tx.note, 200),
      transfer: tx.transferGroupId !== null,
    }
  }

  async function transactionsIn(
    ctx: ToolContext,
    found: Lookup,
    range: { from?: string; to?: string; search?: string },
  ): Promise<Transaction[]> {
    const to = range.to ?? today(deps.clock.now())
    return deps.transactions.all(ctx.tenantId, {
      accountIds: found.accounts.map(account => account.id),
      from: range.from ?? addDays(to, -DEFAULT_DAYS),
      to,
      search: range.search,
    })
  }

  function spendByCategory(found: Lookup, transactions: Transaction[]) {
    const totals = new Map<string, number>()
    for (const tx of transactions) {
      if (!tx.amount.isNegative() || tx.transferGroupId !== null) {
        continue
      }
      const name = found.categoryName(tx.categoryId)
      totals.set(name, (totals.get(name) ?? 0) - tx.amount.cents)
    }
    return totals
  }

  const queryArgs = z.object({
    from: isoDate.optional(),
    to: isoDate.optional(),
    search: z.string().trim().min(1).max(100).optional(),
    category: z.string().trim().min(1).optional(),
    direction: z.enum(['in', 'out']).optional(),
    limit: z.number().int().min(1).max(MAX_ROWS).default(20),
  })

  function queryTransactions(ctx: ToolContext): AgentTool {
    return {
      name: 'query_transactions',
      description:
        'List transactions, newest first. Defaults to the last 30 days. Filter by text, category name or direction (in for income, out for expenses).',
      parameters: object({
        from: day('First day'),
        to: day('Last day'),
        search: text('Text in the description or note'),
        category: text('Category name'),
        direction: { type: 'string', enum: ['in', 'out'] },
        limit: { type: 'number', description: 'At most 50' },
      }),
      async run(raw) {
        const args = queryArgs.parse(raw)
        const found = await lookup(ctx)
        const category = args.category
          ? findCategory(found, args.category).id
          : undefined
        const sign = { in: 1, out: -1 }
        const rows = (await transactionsIn(ctx, found, args)).filter(
          tx =>
            (!category || tx.categoryId === category) &&
            (!args.direction ||
              Math.sign(tx.amount.cents) === sign[args.direction]),
        )
        const total = rows.reduce((sum, tx) => sum + tx.amount.cents, 0)
        return {
          count: rows.length,
          total: decimal(Money.of(total)),
          items: rows.slice(0, args.limit).map(tx => row(found, tx)),
        }
      },
    }
  }

  const periodArgs = z.object({ from: isoDate, to: isoDate })

  function summarizePeriod(ctx: ToolContext): AgentTool {
    return {
      name: 'summarize_period',
      description:
        'Income, expenses, net and the top expense categories between two days. Transfers between the user entities are left out.',
      parameters: object({ from: day('First day'), to: day('Last day') }, [
        'from',
        'to',
      ]),
      async run(raw) {
        const args = periodArgs.parse(raw)
        const found = await lookup(ctx)
        const moved = (await transactionsIn(ctx, found, args)).filter(
          tx => tx.transferGroupId === null,
        )
        const income = moved
          .filter(tx => tx.amount.isPositive())
          .reduce((sum, tx) => sum + tx.amount.cents, 0)
        const expenses = moved
          .filter(tx => tx.amount.isNegative())
          .reduce((sum, tx) => sum - tx.amount.cents, 0)
        const top = [...spendByCategory(found, moved).entries()]
          .sort((a, b) => b[1] - a[1])
          .slice(0, 8)
          .map(([category, cents]) => ({
            category,
            spent: decimal(Money.of(cents)),
          }))
        return {
          from: args.from,
          to: args.to,
          count: moved.length,
          income: decimal(Money.of(income)),
          expenses: decimal(Money.of(expenses)),
          net: decimal(Money.of(income - expenses)),
          topCategories: top,
        }
      },
    }
  }

  const compareArgs = z.object({
    from: isoDate,
    to: isoDate,
    compareFrom: isoDate,
    compareTo: isoDate,
  })

  function compareCategories(ctx: ToolContext): AgentTool {
    return {
      name: 'compare_categories',
      description:
        'Spending per category in one period against another, with the change, largest change first.',
      parameters: object(
        {
          from: day('First day of the period'),
          to: day('Last day of the period'),
          compareFrom: day('First day of the period to compare with'),
          compareTo: day('Last day of the period to compare with'),
        },
        ['from', 'to', 'compareFrom', 'compareTo'],
      ),
      async run(raw) {
        const args = compareArgs.parse(raw)
        const found = await lookup(ctx)
        const current = spendByCategory(
          found,
          await transactionsIn(ctx, found, args),
        )
        const previous = spendByCategory(
          found,
          await transactionsIn(ctx, found, {
            from: args.compareFrom,
            to: args.compareTo,
          }),
        )
        const names = new Set([...current.keys(), ...previous.keys()])
        return [...names]
          .map(category => {
            const now = current.get(category) ?? 0
            const before = previous.get(category) ?? 0
            return { category, now, before, change: now - before }
          })
          .sort((a, b) => Math.abs(b.change) - Math.abs(a.change))
          .map(item => ({
            category: item.category,
            spent: decimal(Money.of(item.now)),
            comparedSpent: decimal(Money.of(item.before)),
            change: decimal(Money.of(item.change)),
          }))
      },
    }
  }

  const billArgs = z.object({ status: z.enum(BILL_STATUSES).optional() })

  async function billsInScope(ctx: ToolContext, status?: string) {
    const allowed = await allowedEntities(ctx)
    const bills = await allPages(page =>
      deps.bills.list(
        ctx.tenantId,
        { status: status as (typeof BILL_STATUSES)[number] | undefined },
        page,
      ),
    )
    return {
      allowed,
      bills: bills.filter(bill => allowed.has(bill.entityId)),
    }
  }

  function listBills(ctx: ToolContext): AgentTool {
    return {
      name: 'list_bills',
      description: 'Bills to pay, by due date, optionally by status.',
      parameters: object({
        status: { type: 'string', enum: [...BILL_STATUSES] },
      }),
      async run(raw) {
        const args = billArgs.parse(raw)
        const { allowed, bills } = await billsInScope(ctx, args.status)
        return bills.slice(0, MAX_ROWS).map(bill => ({
          id: bill.id,
          payee: bill.payee && sanitize(bill.payee, 120),
          amount: decimal(bill.amount),
          currency: bill.amount.currency,
          dueDate: bill.dueDate,
          status: bill.status,
          kind: bill.kind,
          entity: allowed.get(bill.entityId),
        }))
      },
    }
  }

  function netWorthSnapshot(ctx: ToolContext): AgentTool {
    return {
      name: 'net_worth_snapshot',
      description:
        'Current balances: cash, investments, credit card debt and the total, per account.',
      parameters: object({}),
      async run() {
        const found = await lookup(ctx)
        const brl = found.accounts.filter(a => a.balance.currency === 'BRL')
        if (brl.length === 0) {
          return { available: false }
        }
        const sumOf = (types: readonly string[]) =>
          brl
            .filter(account => types.includes(account.type))
            .reduce((sum, account) => sum + account.balance.cents, 0)
        const cash = sumOf(['CHECKING', 'SAVINGS', 'WALLET'])
        const investments = sumOf(['INVESTMENT'])
        const cards = sumOf(['CREDIT_CARD'])
        return {
          available: true,
          cash: decimal(Money.of(cash)),
          investments: decimal(Money.of(investments)),
          creditCards: decimal(Money.of(cards)),
          total: decimal(Money.of(cash + investments + cards)),
          accounts: found.accounts.map(account => ({
            name: sanitize(account.name, 80),
            type: account.type,
            balance: decimal(account.balance),
            currency: account.balance.currency,
            entity: found.kindOf.get(account.id),
          })),
        }
      },
    }
  }

  const explainArgs = z
    .object({
      transactionId: z.string().min(1).optional(),
      search: z.string().trim().min(1).max(100).optional(),
    })
    .refine(args => args.transactionId || args.search, {
      message: 'Give a transactionId or a search text.',
    })

  function explainCharge(ctx: ToolContext): AgentTool {
    return {
      name: 'explain_charge',
      description:
        'Explain one charge: its category, who set it, and how often the same merchant appeared in the last year with the amounts.',
      parameters: object({
        transactionId: text('Id from query_transactions'),
        search: text('Text of the charge when the id is unknown'),
      }),
      async run(raw) {
        const args = explainArgs.parse(raw)
        const found = await lookup(ctx)
        const end = today(deps.clock.now())
        const year = await transactionsIn(ctx, found, {
          from: addDays(end, -365),
          to: end,
        })
        const target = args.transactionId
          ? year.find(tx => tx.id === args.transactionId)
          : (
              await transactionsIn(ctx, found, {
                from: addDays(end, -365),
                to: end,
                search: args.search,
              })
            )[0]
        if (!target) {
          throw new NotFoundError('Transaction')
        }
        const merchant = normalizeDescription(target.description)
        const same = year.filter(
          tx =>
            merchant !== '' &&
            normalizeDescription(tx.description) === merchant,
        )
        const total = same.reduce((sum, tx) => sum + tx.amount.cents, 0)
        return {
          transaction: row(found, target),
          categorizedBy: target.categorizedBy,
          confidence: target.categoryConfidence,
          sameMerchant: {
            count: same.length,
            average: decimal(
              Money.of(same.length ? Math.round(total / same.length) : 0),
            ),
            firstSeen: same.at(-1)?.bookedOn ?? null,
            recent: same.slice(0, 5).map(tx => ({
              date: tx.bookedOn,
              amount: decimal(tx.amount),
            })),
          },
        }
      },
    }
  }

  const attachmentArgs = z.object({ attachmentId: z.string().min(1) })

  function createBillFromAttachment(ctx: ToolContext): AgentTool {
    return {
      name: 'create_bill_from_attachment',
      description:
        'Propose saving a bill (boleto, tax guide or Pix charge) read from a file the user attached in this chat. The user must confirm in the app.',
      parameters: object(
        { attachmentId: text('Id of the attachment in this chat') },
        ['attachmentId'],
      ),
      async run(raw) {
        const args = attachmentArgs.parse(raw)
        const attachment = await deps.chat.findAttachment(
          ctx.tenantId,
          args.attachmentId,
        )
        if (attachment?.threadId !== ctx.threadId) {
          throw new NotFoundError('Attachment')
        }
        const entity = scopeKind(ctx.scope)
        const action = await ctx.propose({
          tool: 'CREATE_BILL_FROM_ATTACHMENT',
          entity,
          needsEntity: entity === null,
          target: { attachmentId: attachment.id },
          details: { fileName: sanitize(attachment.fileName, 120) },
        })
        return pendingReply(action)
      },
    }
  }

  const payArgs = z.object({ billId: z.string().min(1) })

  function payBill(ctx: ToolContext): AgentTool {
    return {
      name: 'pay_bill',
      description:
        'Propose paying an open bill now through the payment ladder. Bills are otherwise paid automatically on their due date. The user must confirm in the app.',
      parameters: object({ billId: text('Id from list_bills') }, ['billId']),
      async run(raw) {
        const args = payArgs.parse(raw)
        const allowed = await allowedEntities(ctx)
        const bill = required(
          await deps.bills.findById(ctx.tenantId, args.billId),
          'Bill',
        )
        const entity = allowed.get(bill.entityId)
        if (!entity) {
          throw new NotFoundError('Bill')
        }
        if (isSettled(bill)) {
          throw new ValidationError('This bill is already settled.')
        }
        const action = await ctx.propose({
          tool: 'PAY_BILL',
          entity,
          needsEntity: false,
          target: { billId: bill.id },
          details: {
            payee: bill.payee && sanitize(bill.payee, 120),
            amount: bill.amount.toJSON(),
            dueDate: bill.dueDate,
          },
        })
        return pendingReply(action)
      },
    }
  }

  const ruleArgs = z.object({
    pattern: z.string().trim().min(1).max(100),
    category: z.string().trim().min(1),
  })

  function createCategoryRule(ctx: ToolContext): AgentTool {
    return {
      name: 'create_categorization_rule',
      description:
        'Propose a rule that puts every transaction whose description contains the merchant words in a category, now and in future syncs. The user must confirm in the app.',
      parameters: object(
        {
          pattern: text('Merchant words, such as the store name'),
          category: text('Category name'),
        },
        ['pattern', 'category'],
      ),
      async run(raw) {
        const args = ruleArgs.parse(raw)
        const pattern = normalizeDescription(args.pattern)
        if (pattern === '') {
          throw new ValidationError('The pattern needs a merchant name.')
        }
        const category = findCategory(await lookup(ctx), args.category)
        const action = await ctx.propose({
          tool: 'CREATE_CATEGORY_RULE',
          entity: scopeKind(ctx.scope),
          needsEntity: false,
          target: { categoryId: category.id, pattern },
          details: { pattern, category: category.name },
        })
        return pendingReply(action)
      },
    }
  }

  const invoiceArgs = z.object({ transactionId: z.string().min(1) })

  function draftInvoice(ctx: ToolContext): AgentTool {
    return {
      name: 'draft_invoice',
      description:
        'Propose issuing a service invoice (NFS-e) for a company income that has none yet. The user must confirm in the app.',
      parameters: object({ transactionId: text('Id of the company income') }, [
        'transactionId',
      ]),
      async run(raw) {
        const args = invoiceArgs.parse(raw)
        const found = await lookup(ctx)
        const tx = await deps.transactions.findById(
          ctx.tenantId,
          args.transactionId,
        )
        if (!tx || !found.kindOf.has(tx.accountId)) {
          throw new NotFoundError('Transaction')
        }
        const companyIncome =
          found.kindOf.get(tx.accountId) === 'PJ' && tx.amount.isPositive()
        if (!companyIncome || tx.invoiceId !== null) {
          throw new ValidationError(
            'Only a company income without an invoice can be invoiced.',
          )
        }
        const action = await ctx.propose({
          tool: 'DRAFT_INVOICE',
          entity: 'PJ',
          needsEntity: false,
          target: { transactionId: tx.id },
          details: {
            payer: sanitize(tx.description, 120),
            amount: tx.amount.toJSON(),
            dueDate: tx.bookedOn,
          },
        })
        return pendingReply(action)
      },
    }
  }

  return function toolsFor(ctx: ToolContext): AgentTool[] {
    return [
      queryTransactions(ctx),
      summarizePeriod(ctx),
      compareCategories(ctx),
      listBills(ctx),
      netWorthSnapshot(ctx),
      explainCharge(ctx),
      createBillFromAttachment(ctx),
      payBill(ctx),
      createCategoryRule(ctx),
      draftInvoice(ctx),
    ]
  }
}
