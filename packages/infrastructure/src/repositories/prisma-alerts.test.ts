import { type PrismaClient } from '@prisma/client'
import { describe, expect, it, vi } from 'vitest'
import { type Alert } from '@cashdeck/domain'
import { createPrismaAlertStores } from '@/repositories/prisma-alerts'

const TENANT = 't1'
const NOW = new Date('2026-10-08T12:00:00.000Z')

const alert: Alert = {
  id: 'a1',
  tenantId: TENANT,
  type: 'PAYMENT_PAID',
  entityId: 'pf',
  billId: 'b1',
  invoiceId: null,
  title: 'Conta paga',
  body: 'Supplier',
  data: { payee: 'Supplier' },
  dedupeKey: 'PAYMENT_PAID:b1',
  createdAt: NOW,
  readAt: null,
}

function mockClient() {
  const delegate = () => ({
    createMany: vi.fn(),
    findFirst: vi.fn(),
    findMany: vi.fn(),
    updateMany: vi.fn(),
    count: vi.fn(),
    upsert: vi.fn(),
    deleteMany: vi.fn(),
  })
  const db = { alert: delegate(), deviceToken: delegate() }
  return { db, stores: createPrismaAlertStores(db as unknown as PrismaClient) }
}

describe('prisma alerts', () => {
  it('adds once per dedupe key', async () => {
    const { db, stores } = mockClient()
    db.alert.createMany
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 })
    expect(await stores.alertStore.add(alert)).toBe(true)
    expect(await stores.alertStore.add(alert)).toBe(false)
    expect(db.alert.createMany.mock.calls[0]?.[0]).toEqual({
      data: [alert],
      skipDuplicates: true,
    })
  })

  it('finds, pages and filters unread', async () => {
    const { db, stores } = mockClient()
    db.alert.findFirst.mockResolvedValueOnce(alert).mockResolvedValueOnce(null)
    expect(await stores.alertStore.findById(TENANT, 'a1')).toEqual(alert)
    expect(await stores.alertStore.findById(TENANT, 'x')).toBeNull()
    db.alert.findMany
      .mockResolvedValueOnce([alert, { ...alert, id: 'a2' }])
      .mockResolvedValueOnce([alert])
    expect(
      await stores.alertStore.list(TENANT, { unreadOnly: true }, { limit: 1 }),
    ).toEqual({ items: [alert], nextCursor: '1' })
    expect(db.alert.findMany.mock.calls[0]?.[0]).toMatchObject({
      where: { tenantId: TENANT, readAt: null },
      skip: 0,
      take: 2,
    })
    expect(
      await stores.alertStore.list(TENANT, {}, { limit: 5, cursor: '5' }),
    ).toEqual({ items: [alert], nextCursor: null })
    expect(db.alert.findMany.mock.calls[1]?.[0]).toMatchObject({
      where: { tenantId: TENANT, readAt: undefined },
      skip: 5,
    })
  })

  it('marks read and counts unread', async () => {
    const { db, stores } = mockClient()
    db.alert.updateMany.mockResolvedValue({ count: 3 })
    db.alert.count.mockResolvedValueOnce(4)
    await stores.alertStore.markRead(TENANT, 'a1', NOW)
    expect(db.alert.updateMany.mock.calls[0]?.[0]).toEqual({
      where: { tenantId: TENANT, id: 'a1', readAt: null },
      data: { readAt: NOW },
    })
    expect(await stores.alertStore.markAllRead(TENANT, NOW)).toBe(3)
    expect(await stores.alertStore.unreadCount(TENANT)).toBe(4)
  })

  it('registers, lists and removes device tokens', async () => {
    const { db, stores } = mockClient()
    const device = {
      tenantId: TENANT,
      token: 'device-1',
      platform: 'ANDROID' as const,
      createdAt: NOW,
      lastSeenAt: NOW,
    }
    await stores.devices.register(device)
    expect(db.deviceToken.upsert.mock.calls[0]?.[0]).toEqual({
      where: { token: 'device-1' },
      create: device,
      update: device,
    })
    db.deviceToken.findMany.mockResolvedValueOnce([device])
    expect(await stores.devices.list(TENANT)).toEqual([device])
    db.deviceToken.deleteMany
      .mockResolvedValueOnce({ count: 1 })
      .mockResolvedValueOnce({ count: 0 })
    expect(await stores.devices.remove(TENANT, 'device-1')).toBe(true)
    expect(await stores.devices.remove(TENANT, 'device-1')).toBe(false)
  })
})
