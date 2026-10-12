import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { createDeviceSession } from '@cashdeck/domain'
import { RandomSessionTokens } from '@/crypto/random-session-tokens'
import { PrismaDeviceSessionRepository } from '@/repositories/prisma-sessions'

const TENANT = 't1'
const NOW = new Date('2026-10-11T12:00:00.000Z')

const session = createDeviceSession({
  id: 's1',
  tenantId: TENANT,
  tokenHash: 'abc',
  deviceName: 'Pixel',
  platform: 'ANDROID',
  now: NOW,
})

function mockClient() {
  const deviceSession = {
    findFirst: vi.fn(),
    findMany: vi.fn(),
    upsert: vi.fn(),
  }
  const db = { deviceSession } as unknown as PrismaClient
  return { deviceSession, repo: new PrismaDeviceSessionRepository(db) }
}

describe('prisma device sessions', () => {
  it('finds by token hash and by id within the tenant', async () => {
    const { deviceSession, repo } = mockClient()
    deviceSession.findFirst
      .mockResolvedValueOnce(session)
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(session)
    expect(await repo.findByTokenHash(TENANT, 'abc')).toEqual(session)
    expect(await repo.findByTokenHash(TENANT, 'nope')).toBeNull()
    expect(await repo.findById(TENANT, 's1')).toEqual(session)
    expect(deviceSession.findFirst.mock.calls.map(call => call[0])).toEqual([
      { where: { tenantId: TENANT, tokenHash: 'abc' } },
      { where: { tenantId: TENANT, tokenHash: 'nope' } },
      { where: { tenantId: TENANT, id: 's1' } },
    ])
  })

  it('lists only live sessions, most recently used first', async () => {
    const { deviceSession, repo } = mockClient()
    deviceSession.findMany.mockResolvedValueOnce([session])
    expect(await repo.listActive(TENANT, NOW)).toEqual([session])
    expect(deviceSession.findMany).toHaveBeenCalledWith({
      where: { tenantId: TENANT, revokedAt: null, expiresAt: { gt: NOW } },
      orderBy: { lastUsedAt: 'desc' },
    })
  })

  it('upserts by id', async () => {
    const { deviceSession, repo } = mockClient()
    await repo.save(session)
    expect(deviceSession.upsert).toHaveBeenCalledWith({
      where: { id: 's1' },
      create: session,
      update: session,
    })
  })
})

describe('random session tokens', () => {
  it('issues 32 random bytes as base64url and hashes them with sha256', () => {
    const tokens = new RandomSessionTokens()
    const token = tokens.issue()
    expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/)
    expect(tokens.issue()).not.toBe(token)
    expect(tokens.hash('abc')).toBe(
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    )
  })
})
