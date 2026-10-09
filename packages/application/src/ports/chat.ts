import { type EntityKind } from '@cashdeck/domain'
import { type Page, type PageRequest } from '@/ports/repositories'

export const CHAT_SCOPES = ['PF', 'PJ', 'ALL'] as const
export type ChatScope = (typeof CHAT_SCOPES)[number]

export type ChatThread = {
  id: string
  tenantId: string
  scope: ChatScope
  title: string | null
  createdAt: Date
  updatedAt: Date
}

export const CHAT_ROLES = ['user', 'assistant'] as const
export type ChatRole = (typeof CHAT_ROLES)[number]

export const CHAT_NOTICES = [
  'ROUND_LIMIT',
  'TIME_BUDGET',
  'EMPTY',
  'ERROR',
] as const
export type ChatNotice = (typeof CHAT_NOTICES)[number]

export type ToolTrace = {
  name: string
  arguments: Record<string, unknown>
  ok: boolean
}

export type ChatMessage = {
  id: string
  tenantId: string
  threadId: string
  role: ChatRole
  content: string
  notice: ChatNotice | null
  tools: ToolTrace[]
  createdAt: Date
}

export type ChatAttachmentMeta = {
  id: string
  tenantId: string
  threadId: string
  messageId: string
  fileName: string
  mimeType: string
  size: number
  createdAt: Date
}

export type ChatAttachment = ChatAttachmentMeta & { bytes: Uint8Array }

export const CHAT_ACTION_TOOLS = [
  'CREATE_BILL_FROM_ATTACHMENT',
  'PAY_BILL',
  'CREATE_CATEGORY_RULE',
  'DRAFT_INVOICE',
] as const
export type ChatActionTool = (typeof CHAT_ACTION_TOOLS)[number]

export const CHAT_ACTION_STATUSES = [
  'PENDING',
  'CONFIRMED',
  'CANCELLED',
  'FAILED',
  'EXPIRED',
] as const
export type ChatActionStatus = (typeof CHAT_ACTION_STATUSES)[number]

// What the confirmation card shows; every field is optional per tool.
export type ChatActionDetails = {
  payee: string | null
  amount: { cents: number; currency: string } | null
  dueDate: string | null
  fileName: string | null
  pattern: string | null
  category: string | null
  payer: string | null
}

export type ChatActionResult = {
  billId: string | null
  invoiceId: string | null
  ruleId: string | null
  updated: number | null
}

export type ChatAction = {
  id: string
  tenantId: string
  threadId: string
  messageId: string
  tool: ChatActionTool
  status: ChatActionStatus
  entity: EntityKind | null
  needsEntity: boolean
  // Ids the server resolved when proposing; the model never sees them change.
  target: Record<string, string>
  details: ChatActionDetails
  result: ChatActionResult | null
  error: string | null
  createdAt: Date
  resolvedAt: Date | null
}

export interface ChatRepository {
  saveThread(thread: ChatThread): Promise<void>
  findThread(tenantId: string, id: string): Promise<ChatThread | null>
  listThreads(tenantId: string, page: PageRequest): Promise<Page<ChatThread>>
  saveMessage(message: ChatMessage): Promise<void>
  // Oldest first.
  listMessages(
    tenantId: string,
    threadId: string,
    page: PageRequest,
  ): Promise<Page<ChatMessage>>
  // The newest [limit] messages, oldest first.
  recentMessages(
    tenantId: string,
    threadId: string,
    limit: number,
  ): Promise<ChatMessage[]>
  saveAttachment(attachment: ChatAttachment): Promise<void>
  findAttachment(tenantId: string, id: string): Promise<ChatAttachment | null>
  listAttachments(
    tenantId: string,
    threadId: string,
  ): Promise<ChatAttachmentMeta[]>
  saveAction(action: ChatAction): Promise<void>
  findAction(tenantId: string, id: string): Promise<ChatAction | null>
  listActions(tenantId: string, threadId: string): Promise<ChatAction[]>
}
