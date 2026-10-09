import {
  type ChatAction,
  type ChatAttachment,
  type ChatAttachmentMeta,
  type ChatMessage,
  type ChatRepository,
  type ChatThread,
} from '@/ports/chat'
import { type Page, type PageRequest } from '@/ports/repositories'

const key = (tenantId: string, id: string) => `${tenantId}:${id}`

function paginate<T>(rows: T[], page: PageRequest): Page<T> {
  const start = Number(page.cursor ?? 0)
  const items = rows.slice(start, start + page.limit)
  const end = start + items.length
  return { items, nextCursor: end < rows.length ? String(end) : null }
}

const byCreation = (
  a: { createdAt: Date; id: string },
  b: { createdAt: Date; id: string },
) => a.createdAt.getTime() - b.createdAt.getTime() || a.id.localeCompare(b.id)

export class InMemoryChatRepository implements ChatRepository {
  private readonly threads = new Map<string, ChatThread>()
  private readonly messages = new Map<string, ChatMessage>()
  private readonly attachments = new Map<string, ChatAttachment>()
  private readonly actions = new Map<string, ChatAction>()

  async saveThread(thread: ChatThread): Promise<void> {
    this.threads.set(key(thread.tenantId, thread.id), thread)
  }

  async findThread(tenantId: string, id: string): Promise<ChatThread | null> {
    return this.threads.get(key(tenantId, id)) ?? null
  }

  async listThreads(
    tenantId: string,
    page: PageRequest,
  ): Promise<Page<ChatThread>> {
    const rows = [...this.threads.values()]
      .filter(thread => thread.tenantId === tenantId)
      .sort(
        (a, b) =>
          b.updatedAt.getTime() - a.updatedAt.getTime() ||
          a.id.localeCompare(b.id),
      )
    return paginate(rows, page)
  }

  async saveMessage(message: ChatMessage): Promise<void> {
    this.messages.set(key(message.tenantId, message.id), message)
  }

  private messagesOf(tenantId: string, threadId: string): ChatMessage[] {
    return [...this.messages.values()]
      .filter(row => row.tenantId === tenantId && row.threadId === threadId)
      .sort(byCreation)
  }

  async listMessages(
    tenantId: string,
    threadId: string,
    page: PageRequest,
  ): Promise<Page<ChatMessage>> {
    return paginate(this.messagesOf(tenantId, threadId), page)
  }

  async recentMessages(
    tenantId: string,
    threadId: string,
    limit: number,
  ): Promise<ChatMessage[]> {
    return this.messagesOf(tenantId, threadId).slice(-limit)
  }

  async saveAttachment(attachment: ChatAttachment): Promise<void> {
    this.attachments.set(key(attachment.tenantId, attachment.id), attachment)
  }

  async findAttachment(
    tenantId: string,
    id: string,
  ): Promise<ChatAttachment | null> {
    return this.attachments.get(key(tenantId, id)) ?? null
  }

  async listAttachments(
    tenantId: string,
    threadId: string,
  ): Promise<ChatAttachmentMeta[]> {
    return [...this.attachments.values()]
      .filter(row => row.tenantId === tenantId && row.threadId === threadId)
      .sort(byCreation)
      .map(({ bytes: _bytes, ...meta }) => meta)
  }

  async saveAction(action: ChatAction): Promise<void> {
    this.actions.set(key(action.tenantId, action.id), action)
  }

  async findAction(tenantId: string, id: string): Promise<ChatAction | null> {
    return this.actions.get(key(tenantId, id)) ?? null
  }

  async listActions(tenantId: string, threadId: string): Promise<ChatAction[]> {
    return [...this.actions.values()]
      .filter(row => row.tenantId === tenantId && row.threadId === threadId)
      .sort(byCreation)
  }
}
