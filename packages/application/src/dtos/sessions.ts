import { type DeviceSession, SESSION_PLATFORMS } from '@cashdeck/domain'
import { z } from 'zod'

export const createSessionSchema = z.object({
  deviceName: z.string().trim().min(1).max(80),
  platform: z.enum(SESSION_PLATFORMS),
})

export type CreateSessionInput = z.infer<typeof createSessionSchema>

export const sessionViewSchema = z.object({
  id: z.string(),
  deviceName: z.string(),
  platform: z.enum(SESSION_PLATFORMS),
  createdAt: z.string(),
  lastUsedAt: z.string(),
  expiresAt: z.string(),
  current: z.boolean(),
})

export type SessionView = z.infer<typeof sessionViewSchema>

export const createdSessionSchema = z.object({
  token: z.string(),
  expiresAt: z.string(),
  session: sessionViewSchema,
})

export type CreatedSession = z.infer<typeof createdSessionSchema>

export const toSessionView = (
  session: DeviceSession,
  currentId: string | null,
): SessionView => ({
  id: session.id,
  deviceName: session.deviceName,
  platform: session.platform,
  createdAt: session.createdAt.toISOString(),
  lastUsedAt: session.lastUsedAt.toISOString(),
  expiresAt: session.expiresAt.toISOString(),
  current: session.id === currentId,
})
