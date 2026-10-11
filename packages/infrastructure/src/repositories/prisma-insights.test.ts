import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { type ChatAction } from '@cashdeck/application'
import { createCategoryRule } from '@cashdeck/domain'
import {
  PrismaCategoryRepository,
  PrismaChatRepository,
} from '@/repositories/prisma-insights'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const DELEGATES = [
  'category',
  'categoryRule',
  'chatThread',
  'chatMessage',
  'chatAttachment',
  'chatAction',
] as const
const METHODS = ['upsert', 'findFirst', 'findMany', 'create'] as const

type Delegate = Record<(typeof METHODS)[number], ReturnType<typeof vi.fn>>

function mockClient() {
  const db = Object.fromEntries(
    DELEGATES.map(name => [
      name,
      Object.fromEntries(METHODS.map(method => [method, vi.fn()])),
    ]),
  ) as Record<(typeof DELEGATES)[number], Delegate>
  const client = db as unknown as PrismaClient
  return {
    db,
    categories: new PrismaCategoryRepository(client),
    chat: new PrismaChatRepository(client),
  }
}

const category = {
  id: 'c1',
  tenantId: TENANT,
  key: 'fuel',
  name: 'Fuel',
  parentId: null,
  icon: 'fuel',
}

describe('PrismaCategoryRepository', () => {
  it('stores categories and rules per tenant', async () => {
    const { db, categories } = mockClient()
    db.category.findMany.mockResolvedValueOnce([category])
    expect(await categories.list(TENANT)).toEqual([category])
    expect(db.category.findMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT },
      orderBy: { name: 'asc' },
    })
    db.category.findFirst.mockResolvedValueOnce(null)
    expect(await categories.findById(TENANT, 'x')).toBeNull()
    await categories.save(category)
    expect(db.category.upsert.mock.calls[0]?.[0]).toEqual({
      where: { id: 'c1' },
      create: category,
      update: category,
    })
    const rule = createCategoryRule({
      id: 'r1',
      tenantId: TENANT,
      entityId: 'pf',
      pattern: 'Posto Azul',
      categoryId: 'c1',
      createdAt: NOW,
    })
    const credit = { ...rule, id: 'r2', direction: 'IN' }
    db.categoryRule.findMany.mockResolvedValueOnce([
      rule,
      credit,
      { ...rule, id: 'r3', direction: 'SIDEWAYS' },
    ])
    expect(await categories.listRules(TENANT)).toEqual([
      rule,
      credit,
      { ...rule, id: 'r3', direction: null },
    ])
    await categories.saveRule(rule)
    expect(db.categoryRule.upsert.mock.calls[0]?.[0].create).toEqual(rule)
  })
})

const thread = {
  id: 'th1',
  tenantId: TENANT,
  scope: 'PF' as const,
  title: null,
  createdAt: NOW,
  updatedAt: NOW,
}

const message = {
  id: 'm1',
  tenantId: TENANT,
  threadId: 'th1',
  role: 'assistant' as const,
  content: 'Hi',
  notice: null,
  tools: [{ name: 'list_bills', arguments: {}, ok: true }],
  createdAt: NOW,
}

const messageRow = {
  ...message,
  tools: undefined,
  toolCalls: message.tools,
}

const action: ChatAction = {
  id: 'a1',
  tenantId: TENANT,
  threadId: 'th1',
  messageId: 'm1',
  tool: 'PAY_BILL',
  status: 'PENDING',
  entity: 'PF',
  needsEntity: false,
  target: { billId: 'b1' },
  details: {
    payee: 'Energy',
    amount: { cents: 100, currency: 'BRL' },
    dueDate: '2026-10-20',
    fileName: null,
    pattern: null,
    category: null,
    payer: null,
  },
  result: null,
  error: null,
  createdAt: NOW,
  resolvedAt: null,
}

describe('PrismaChatRepository', () => {
  it('stores threads and pages them by activity', async () => {
    const { db, chat } = mockClient()
    await chat.saveThread(thread)
    expect(db.chatThread.upsert.mock.calls[0]?.[0].create).toEqual(thread)
    db.chatThread.findFirst
      .mockResolvedValueOnce(thread)
      .mockResolvedValueOnce(null)
    expect(await chat.findThread(TENANT, 'th1')).toEqual(thread)
    expect(await chat.findThread(TENANT, 'x')).toBeNull()
    db.chatThread.findMany.mockResolvedValueOnce([
      thread,
      { ...thread, id: 'th2' },
    ])
    const page = await chat.listThreads(TENANT, { limit: 1 })
    expect(page).toEqual({ items: [thread], nextCursor: '1' })
    expect(db.chatThread.findMany.mock.calls[0]?.[0]).toMatchObject({
      orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
      skip: 0,
      take: 2,
    })
  })

  it('stores messages with their tool trace, oldest first', async () => {
    const { db, chat } = mockClient()
    await chat.saveMessage(message)
    expect(db.chatMessage.upsert.mock.calls[0]?.[0].create).toEqual({
      id: 'm1',
      tenantId: TENANT,
      threadId: 'th1',
      role: 'assistant',
      content: 'Hi',
      notice: null,
      toolCalls: message.tools,
      createdAt: NOW,
    })
    db.chatMessage.findMany.mockResolvedValueOnce([messageRow])
    const page = await chat.listMessages(TENANT, 'th1', {
      cursor: '2',
      limit: 5,
    })
    expect(page).toEqual({ items: [message], nextCursor: null })
    expect(db.chatMessage.findMany.mock.calls[0]?.[0].skip).toBe(2)
    db.chatMessage.findMany.mockResolvedValueOnce([
      { ...messageRow, id: 'm2', toolCalls: null },
      messageRow,
    ])
    const recent = await chat.recentMessages(TENANT, 'th1', 2)
    expect(recent.map(m => [m.id, m.tools.length])).toEqual([
      ['m1', 1],
      ['m2', 0],
    ])
  })

  it('stores attachments and actions', async () => {
    const { db, chat } = mockClient()
    const attachment = {
      id: 'f1',
      tenantId: TENANT,
      threadId: 'th1',
      messageId: 'm1',
      fileName: 'bill.pdf',
      mimeType: 'application/pdf',
      size: 2,
      createdAt: NOW,
      bytes: new Uint8Array([1, 2]),
    }
    await chat.saveAttachment(attachment)
    expect(db.chatAttachment.create.mock.calls[0]?.[0].data.fileName).toBe(
      'bill.pdf',
    )
    db.chatAttachment.findFirst
      .mockResolvedValueOnce({ ...attachment, bytes: Buffer.from([1, 2]) })
      .mockResolvedValueOnce(null)
    expect((await chat.findAttachment(TENANT, 'f1'))?.bytes).toEqual(
      new Uint8Array([1, 2]),
    )
    expect(await chat.findAttachment(TENANT, 'x')).toBeNull()
    db.chatAttachment.findMany.mockResolvedValueOnce([])
    expect(await chat.listAttachments(TENANT, 'th1')).toEqual([])
    expect(
      db.chatAttachment.findMany.mock.calls[0]?.[0].select.bytes,
    ).toBeUndefined()

    await chat.saveAction(action)
    expect(
      db.chatAction.upsert.mock.calls[0]?.[0].create.result,
    ).toBeUndefined()
    const done = {
      ...action,
      status: 'CONFIRMED' as const,
      result: { billId: 'b1', invoiceId: null, ruleId: null, updated: null },
    }
    await chat.saveAction(done)
    expect(db.chatAction.upsert.mock.calls[1]?.[0].update.result).toEqual(
      done.result,
    )
    db.chatAction.findFirst
      .mockResolvedValueOnce(action)
      .mockResolvedValueOnce(null)
    expect(await chat.findAction(TENANT, 'a1')).toEqual(action)
    expect(await chat.findAction(TENANT, 'x')).toBeNull()
    db.chatAction.findMany.mockResolvedValueOnce([done])
    expect(await chat.listActions(TENANT, 'th1')).toEqual([done])
  })
})
