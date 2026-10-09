import { describe, expect, it } from 'vitest'
import { Money } from '@cashdeck/domain'
import { type ChatAction, type ChatScope } from '@/ports/chat'
import {
  account,
  bill,
  fullDeps,
  transaction,
} from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { ensureCategories } from '@/use-cases/categorization'
import { makeChatTools, type Proposal } from '@/use-cases/chat/tools'

async function seeded() {
  const deps = fullDeps()
  await deps.accounts.save(
    account({ id: 'pf-1', entityId: 'pf', name: 'Checking' }),
  )
  await deps.accounts.save(
    account({
      id: 'pf-card',
      entityId: 'pf',
      type: 'CREDIT_CARD',
      balance: Money.of(-30000),
    }),
  )
  await deps.accounts.save(
    account({
      id: 'pf-inv',
      entityId: 'pf',
      type: 'INVESTMENT',
      balance: Money.of(500000),
    }),
  )
  await deps.accounts.save(account({ id: 'pj-1', entityId: 'pj' }))
  const categories = await ensureCategories(deps, TENANT)
  const id = (key: string) =>
    categories.find(category => category.key === key)?.id as string
  const rows = [
    transaction({
      id: 'm1',
      accountId: 'pf-1',
      description: 'Mercado Sol',
      amount: Money.of(-10000),
      bookedOn: '2026-10-05',
      categoryId: id('groceries'),
      categorizedBy: 'RULE',
      categoryConfidence: 1,
      note: 'weekly',
    }),
    transaction({
      id: 'm2',
      accountId: 'pf-1',
      description: 'MERCADO SOL',
      amount: Money.of(-8000),
      bookedOn: '2026-09-05',
      categoryId: id('groceries'),
    }),
    transaction({
      id: 'salary',
      accountId: 'pf-1',
      description: 'Salary',
      amount: Money.of(700000),
      bookedOn: '2026-10-01',
    }),
    transaction({
      id: 'move',
      accountId: 'pf-1',
      description: 'To company',
      amount: Money.of(-1000),
      bookedOn: '2026-10-02',
      transferGroupId: 'g1',
    }),
    transaction({
      id: 'fee',
      accountId: 'pf-1',
      description: 'Old fee',
      amount: Money.of(-300),
      bookedOn: '2026-09-10',
      categoryId: 'retired-category',
    }),
    transaction({
      id: 'pix',
      accountId: 'pf-1',
      description: 'PIX 123',
      amount: Money.of(-500),
      bookedOn: '2026-10-03',
    }),
    transaction({
      id: 'income',
      accountId: 'pj-1',
      description: 'Client Inc',
      amount: Money.of(900000),
      bookedOn: '2026-10-04',
    }),
    transaction({
      id: 'billed',
      accountId: 'pj-1',
      description: 'Client Inc',
      amount: Money.of(900000),
      bookedOn: '2026-09-04',
      invoiceId: 'inv1',
    }),
  ]
  for (const row of rows) {
    await deps.transactions.save(row)
  }
  await deps.bills.save(bill({ id: 'b-pf', entityId: 'pf', payee: 'Energy' }))
  await deps.bills.save(bill({ id: 'b-pj', entityId: 'pj', payee: 'Tax' }))
  await deps.bills.save(
    bill({ id: 'b-paid', entityId: 'pf', status: 'PAID', payee: null }),
  )
  return { deps, id }
}

async function toolsFor(scope: ChatScope) {
  const { deps, id } = await seeded()
  const proposals: Proposal[] = []
  const tools = makeChatTools(deps)({
    tenantId: TENANT,
    threadId: 'th1',
    scope,
    propose: async proposal => {
      proposals.push(proposal)
      return { id: `act-${proposals.length}` } as ChatAction
    },
  })
  const run = (name: string, args: Record<string, unknown> = {}) => {
    const tool = tools.find(candidate => candidate.name === name)
    if (!tool) {
      throw new Error(`no tool ${name}`)
    }
    return tool.run(args) as Promise<Record<string, unknown>>
  }
  return { deps, id, proposals, run, tools }
}

describe('chat read tools', () => {
  it('queries transactions in scope with filters', async () => {
    const { run } = await toolsFor('PF')
    const recent = await run('query_transactions', {})
    expect(recent).toMatchObject({ count: 5, total: '6882.00' })
    const out = await run('query_transactions', {
      direction: 'out',
      from: '2026-09-01',
      limit: 1,
    })
    expect(out).toMatchObject({ count: 5 })
    expect(out.items).toHaveLength(1)
    const groceries = await run('query_transactions', {
      category: 'groceries',
      from: '2026-09-01',
    })
    expect(groceries).toMatchObject({ count: 2, total: '-180.00' })
    expect((groceries.items as unknown[])[0]).toEqual({
      id: 'm1',
      date: '2026-10-05',
      description: 'Mercado Sol',
      amount: '-100.00',
      currency: 'BRL',
      category: 'Groceries',
      entity: 'PF',
      note: 'weekly',
      transfer: false,
    })
    const income = await run('query_transactions', { direction: 'in' })
    expect(income).toMatchObject({ count: 1 })
    await expect(
      run('query_transactions', { category: 'Gadgets' }),
    ).rejects.toThrow('Unknown category')
  })

  it('summarizes and compares periods without transfers', async () => {
    const { run } = await toolsFor('PF')
    const summary = await run('summarize_period', {
      from: '2026-10-01',
      to: '2026-10-31',
    })
    expect(summary).toEqual({
      from: '2026-10-01',
      to: '2026-10-31',
      count: 3,
      income: '7000.00',
      expenses: '105.00',
      net: '6895.00',
      topCategories: [
        { category: 'Groceries', spent: '100.00' },
        { category: 'Uncategorized', spent: '5.00' },
      ],
    })
    const compared = await run('compare_categories', {
      from: '2026-10-01',
      to: '2026-10-31',
      compareFrom: '2026-09-01',
      compareTo: '2026-09-30',
    })
    expect(compared).toEqual([
      {
        category: 'Groceries',
        spent: '100.00',
        comparedSpent: '80.00',
        change: '20.00',
      },
      {
        category: 'Uncategorized',
        spent: '5.00',
        comparedSpent: '0.00',
        change: '5.00',
      },
      {
        category: 'retired-category',
        spent: '0.00',
        comparedSpent: '3.00',
        change: '-3.00',
      },
    ])
  })

  it('lists bills and balances for the scope only', async () => {
    const personal = await toolsFor('PF')
    const bills = (await personal.run('list_bills', {})) as unknown as Array<
      Record<string, unknown>
    >
    expect(bills.map(b => b.id)).toEqual(['b-paid', 'b-pf'])
    const open = (await personal.run('list_bills', {
      status: 'OPEN',
    })) as unknown as unknown[]
    expect(open).toHaveLength(1)
    const worth = await personal.run('net_worth_snapshot')
    expect(worth).toMatchObject({
      available: true,
      cash: '100.00',
      investments: '5000.00',
      creditCards: '-300.00',
      total: '4800.00',
    })
    const everything = await toolsFor('ALL')
    const all = (await everything.run('list_bills')) as unknown as unknown[]
    expect(all).toHaveLength(3)
  })

  it('says when there is no balance to report', async () => {
    const deps = fullDeps()
    const tools = makeChatTools(deps)({
      tenantId: TENANT,
      threadId: 'th1',
      scope: 'PJ',
      propose: async () => ({}) as ChatAction,
    })
    const snapshot = tools.find(tool => tool.name === 'net_worth_snapshot')
    expect(await snapshot?.run({})).toEqual({ available: false })
  })

  it('explains a charge by id or by text', async () => {
    const { run } = await toolsFor('PF')
    const byId = await run('explain_charge', { transactionId: 'm1' })
    expect(byId).toMatchObject({
      categorizedBy: 'RULE',
      confidence: 1,
      sameMerchant: {
        count: 2,
        average: '-90.00',
        firstSeen: '2026-09-05',
      },
    })
    const byText = await run('explain_charge', { search: 'pix' })
    expect(byText).toMatchObject({
      transaction: { id: 'pix' },
      sameMerchant: { count: 0, average: '0.00', firstSeen: null },
    })
    await expect(
      run('explain_charge', { transactionId: 'income' }),
    ).rejects.toThrow('Transaction was not found.')
    await expect(run('explain_charge', {})).rejects.toThrow(
      'Give a transactionId or a search text.',
    )
  })
})

describe('chat side-effect tools', () => {
  it('only proposes, with the target the server resolved', async () => {
    const { deps, proposals, run, id } = await toolsFor('PF')
    await deps.chat.saveAttachment({
      id: 'att1',
      tenantId: TENANT,
      threadId: 'th1',
      messageId: 'msg1',
      fileName: 'bill.pdf',
      mimeType: 'application/pdf',
      size: 3,
      createdAt: NOW,
      bytes: new Uint8Array([1, 2, 3]),
    })
    await deps.chat.saveAttachment({
      id: 'att2',
      tenantId: TENANT,
      threadId: 'other',
      messageId: 'msg2',
      fileName: 'x.pdf',
      mimeType: 'application/pdf',
      size: 3,
      createdAt: NOW,
      bytes: new Uint8Array([1]),
    })
    expect(
      await run('create_bill_from_attachment', { attachmentId: 'att1' }),
    ).toMatchObject({ status: 'PENDING_CONFIRMATION', actionId: 'act-1' })
    await expect(
      run('create_bill_from_attachment', { attachmentId: 'att2' }),
    ).rejects.toThrow('Attachment was not found.')
    await run('pay_bill', { billId: 'b-pf' })
    await expect(run('pay_bill', { billId: 'b-pj' })).rejects.toThrow(
      'Bill was not found.',
    )
    await expect(run('pay_bill', { billId: 'b-paid' })).rejects.toThrow(
      'already settled',
    )
    await run('create_categorization_rule', {
      pattern: 'Mercado Sol',
      category: 'Groceries',
    })
    await expect(
      run('create_categorization_rule', { pattern: '123', category: 'Fuel' }),
    ).rejects.toThrow('The pattern needs a merchant name.')
    expect(proposals).toEqual([
      {
        tool: 'CREATE_BILL_FROM_ATTACHMENT',
        entity: 'PF',
        needsEntity: false,
        target: { attachmentId: 'att1' },
        details: { fileName: 'bill.pdf' },
      },
      {
        tool: 'PAY_BILL',
        entity: 'PF',
        needsEntity: false,
        target: { billId: 'b-pf' },
        details: {
          payee: 'Energy',
          amount: { cents: 12345, currency: 'BRL' },
          dueDate: '2026-10-20',
        },
      },
      {
        tool: 'CREATE_CATEGORY_RULE',
        entity: 'PF',
        needsEntity: false,
        target: { categoryId: id('groceries'), pattern: 'mercado sol' },
        details: { pattern: 'mercado sol', category: 'Groceries' },
      },
    ])
  })

  it('asks for the entity in a consolidated chat and invoices only company income', async () => {
    const { deps, proposals, run } = await toolsFor('ALL')
    await deps.chat.saveAttachment({
      id: 'att1',
      tenantId: TENANT,
      threadId: 'th1',
      messageId: 'msg1',
      fileName: 'bill.pdf',
      mimeType: 'application/pdf',
      size: 3,
      createdAt: NOW,
      bytes: new Uint8Array([1, 2, 3]),
    })
    await run('create_bill_from_attachment', { attachmentId: 'att1' })
    await run('pay_bill', { billId: 'b-paid' }).catch(() => null)
    await run('draft_invoice', { transactionId: 'income' })
    await expect(
      run('draft_invoice', { transactionId: 'billed' }),
    ).rejects.toThrow('Only a company income')
    await expect(
      run('draft_invoice', { transactionId: 'salary' }),
    ).rejects.toThrow('Only a company income')
    await expect(
      run('draft_invoice', { transactionId: 'gone' }),
    ).rejects.toThrow('Transaction was not found.')
    expect(proposals.map(p => [p.tool, p.entity, p.needsEntity])).toEqual([
      ['CREATE_BILL_FROM_ATTACHMENT', null, true],
      ['DRAFT_INVOICE', 'PJ', false],
    ])
    expect(proposals[1]?.details).toEqual({
      payer: 'Client Inc',
      amount: { cents: 900000, currency: 'BRL' },
      dueDate: '2026-10-04',
    })
    const personal = await toolsFor('PF')
    await expect(
      personal.run('draft_invoice', { transactionId: 'income' }),
    ).rejects.toThrow('Transaction was not found.')
  })
})
