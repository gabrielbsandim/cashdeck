import { type Prisma, type PrismaClient } from '@prisma/client'
import {
  type CategoryRepository,
  type ChatAction,
  type ChatActionDetails,
  type ChatActionResult,
  type ChatActionStatus,
  type ChatActionTool,
  type ChatAttachment,
  type ChatAttachmentMeta,
  type ChatMessage,
  type ChatNotice,
  type ChatRepository,
  type ChatRole,
  type ChatScope,
  type ChatThread,
  type Page,
  type PageRequest,
  type ToolTrace,
} from '@cashdeck/application'
import { type Category, type CategoryRule } from '@cashdeck/domain'

const json = (value: unknown) => value as Prisma.InputJsonValue

async function paged<T, R>(
  page: PageRequest,
  load: (skip: number, take: number) => Promise<R[]>,
  map: (row: R) => T,
): Promise<Page<T>> {
  const skip = Number(page.cursor ?? 0)
  const rows = await load(skip, page.limit + 1)
  const items = rows.slice(0, page.limit).map(map)
  const hasMore = rows.length > page.limit
  return { items, nextCursor: hasMore ? String(skip + items.length) : null }
}

export class PrismaCategoryRepository implements CategoryRepository {
  constructor(private readonly db: PrismaClient) {}

  async list(tenantId: string): Promise<Category[]> {
    return this.db.category.findMany({
      where: { tenantId },
      orderBy: { name: 'asc' },
    })
  }

  async findById(tenantId: string, id: string): Promise<Category | null> {
    return this.db.category.findFirst({ where: { tenantId, id } })
  }

  async save(category: Category): Promise<void> {
    await this.db.category.upsert({
      where: { id: category.id },
      create: category,
      update: category,
    })
  }

  async listRules(tenantId: string): Promise<CategoryRule[]> {
    return this.db.categoryRule.findMany({
      where: { tenantId },
      orderBy: { createdAt: 'asc' },
    })
  }

  async saveRule(rule: CategoryRule): Promise<void> {
    await this.db.categoryRule.upsert({
      where: { id: rule.id },
      create: rule,
      update: rule,
    })
  }
}

type ThreadRow = {
  id: string
  tenantId: string
  scope: string
  title: string | null
  createdAt: Date
  updatedAt: Date
}

const threadFromRow = (row: ThreadRow): ChatThread => ({
  ...row,
  scope: row.scope as ChatScope,
})

type MessageRow = {
  id: string
  tenantId: string
  threadId: string
  role: string
  content: string
  notice: string | null
  toolCalls: unknown
  createdAt: Date
}

const messageFromRow = (row: MessageRow): ChatMessage => ({
  id: row.id,
  tenantId: row.tenantId,
  threadId: row.threadId,
  role: row.role as ChatRole,
  content: row.content,
  notice: row.notice as ChatNotice | null,
  tools: (row.toolCalls ?? []) as ToolTrace[],
  createdAt: row.createdAt,
})

const ATTACHMENT_META = {
  id: true,
  tenantId: true,
  threadId: true,
  messageId: true,
  fileName: true,
  mimeType: true,
  size: true,
  createdAt: true,
} as const

type ActionRow = Omit<
  ChatAction,
  'tool' | 'status' | 'target' | 'details' | 'result'
> & {
  tool: string
  status: string
  target: unknown
  details: unknown
  result: unknown
}

const actionFromRow = (row: ActionRow): ChatAction => ({
  ...row,
  tool: row.tool as ChatActionTool,
  status: row.status as ChatActionStatus,
  target: row.target as Record<string, string>,
  details: row.details as ChatActionDetails,
  result: row.result as ChatActionResult | null,
})

const OLDEST_FIRST = [{ createdAt: 'asc' as const }, { id: 'asc' as const }]

export class PrismaChatRepository implements ChatRepository {
  constructor(private readonly db: PrismaClient) {}

  async saveThread(thread: ChatThread): Promise<void> {
    await this.db.chatThread.upsert({
      where: { id: thread.id },
      create: thread,
      update: thread,
    })
  }

  async findThread(tenantId: string, id: string): Promise<ChatThread | null> {
    const row = await this.db.chatThread.findFirst({ where: { tenantId, id } })
    return row && threadFromRow(row)
  }

  async listThreads(
    tenantId: string,
    page: PageRequest,
  ): Promise<Page<ChatThread>> {
    return paged(
      page,
      (skip, take) =>
        this.db.chatThread.findMany({
          where: { tenantId },
          orderBy: [{ updatedAt: 'desc' }, { id: 'asc' }],
          skip,
          take,
        }),
      threadFromRow,
    )
  }

  async saveMessage(message: ChatMessage): Promise<void> {
    const { tools, ...row } = message
    const data = { ...row, toolCalls: json(tools) }
    await this.db.chatMessage.upsert({
      where: { id: message.id },
      create: data,
      update: data,
    })
  }

  async listMessages(
    tenantId: string,
    threadId: string,
    page: PageRequest,
  ): Promise<Page<ChatMessage>> {
    return paged(
      page,
      (skip, take) =>
        this.db.chatMessage.findMany({
          where: { tenantId, threadId },
          orderBy: OLDEST_FIRST,
          skip,
          take,
        }),
      messageFromRow,
    )
  }

  async recentMessages(
    tenantId: string,
    threadId: string,
    limit: number,
  ): Promise<ChatMessage[]> {
    const rows = await this.db.chatMessage.findMany({
      where: { tenantId, threadId },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit,
    })
    return rows.reverse().map(messageFromRow)
  }

  async saveAttachment(attachment: ChatAttachment): Promise<void> {
    await this.db.chatAttachment.create({
      data: { ...attachment, bytes: Uint8Array.from(attachment.bytes) },
    })
  }

  async findAttachment(
    tenantId: string,
    id: string,
  ): Promise<ChatAttachment | null> {
    const row = await this.db.chatAttachment.findFirst({
      where: { tenantId, id },
    })
    return row && { ...row, bytes: new Uint8Array(row.bytes) }
  }

  async listAttachments(
    tenantId: string,
    threadId: string,
  ): Promise<ChatAttachmentMeta[]> {
    return this.db.chatAttachment.findMany({
      where: { tenantId, threadId },
      select: ATTACHMENT_META,
      orderBy: OLDEST_FIRST,
    })
  }

  async saveAction(action: ChatAction): Promise<void> {
    const data = {
      ...action,
      target: json(action.target),
      details: json(action.details),
      result: action.result === null ? undefined : json(action.result),
    }
    await this.db.chatAction.upsert({
      where: { id: action.id },
      create: data,
      update: data,
    })
  }

  async findAction(tenantId: string, id: string): Promise<ChatAction | null> {
    const row = await this.db.chatAction.findFirst({ where: { tenantId, id } })
    return row && actionFromRow(row)
  }

  async listActions(tenantId: string, threadId: string): Promise<ChatAction[]> {
    const rows = await this.db.chatAction.findMany({
      where: { tenantId, threadId },
      orderBy: OLDEST_FIRST,
    })
    return rows.map(actionFromRow)
  }
}
