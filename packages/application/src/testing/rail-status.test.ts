import { describe, expect, it } from 'vitest'
import { FakeRailStatusReader } from '@/testing/rail-status'

describe('FakeRailStatusReader', () => {
  it('reports scripted statuses and defaults to submitted', async () => {
    const scope = { tenantId: 't', entityId: 'e' }
    const paid = {
      outcome: 'PAID' as const,
      externalId: 'pix:1',
      endToEndId: 'E123',
      settledAt: '2026-10-08T12:00:00Z',
    }
    const reader = new FakeRailStatusReader('ASAAS').willReport('pix:1', paid)
    expect(await reader.status('pix:1', scope)).toBe(paid)
    expect((await reader.status('pix:2', scope)).outcome).toBe('SUBMITTED')
    expect(reader.asked).toEqual(['pix:1', 'pix:2'])
  })
})
