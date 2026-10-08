import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { generateExportSchema } from '@/dtos/accountant-export'
import { saveRailCredentialsSchema } from '@/dtos/rails'
import { NotFoundError } from '@/errors/errors'
import { transaction } from '@/testing/deps.test-helpers'
import {
  InMemoryTransactionRepository,
  InMemoryTransferRepository,
} from '@/testing/records'
import { InMemoryEntityRepository } from '@/testing/repositories'
import { TENANT } from '@/testing/scenario.test-helpers'
import {
  FakeCertificateInspector,
  FakeMailboxAuthorizer,
} from '@/testing/services'
import {
  decodeUpload,
  requireEntity,
  requireEntityById,
} from '@/use-cases/shared'

describe('record fakes', () => {
  it('inserts only transactions not stored yet', async () => {
    const repo = new InMemoryTransactionRepository()
    await repo.save(transaction({ id: 'a', accountId: 'x', externalId: 'e1' }))
    await repo.save(transaction({ id: 'b', accountId: 'x' }))
    const inserted = await repo.saveNew([
      transaction({ id: 'c', accountId: 'x', externalId: 'e1' }),
      transaction({ id: 'd', accountId: 'y', externalId: 'e1' }),
      transaction({ id: 'e', accountId: 'x' }),
    ])
    expect(inserted).toBe(2)
    const first = await repo.list(TENANT, {}, { limit: 3 })
    const rest = await repo.list(
      TENANT,
      {},
      { cursor: first.nextCursor, limit: 3 },
    )
    expect([first.items.length, rest.items.length, rest.nextCursor]).toEqual([
      3,
      1,
      null,
    ])
  })

  it('lists transfers newest first', async () => {
    const repo = new InMemoryTransferRepository()
    const transfer = (id: string, at: string) => ({
      id,
      tenantId: TENANT,
      kind: 'PRO_LABORE' as const,
      amount: Money.of(1),
      at: new Date(at),
      rail: 'PIX',
      fromAccountId: 'a',
      toAccountId: 'b',
      document: null,
    })
    await repo.save(transfer('old', '2026-10-01T00:00:00Z'))
    await repo.save(transfer('new', '2026-10-05T00:00:00Z'))
    const list = await repo.list(TENANT, {
      from: new Date('2026-10-01T00:00:00Z'),
      to: new Date('2026-11-01T00:00:00Z'),
    })
    expect(list.map(row => row.id)).toEqual(['new', 'old'])
  })

  it('finds no entity of a missing kind', async () => {
    const entities = new InMemoryEntityRepository()
    expect(await entities.findByKind(TENANT, 'PJ')).toBeNull()
    await expect(requireEntity(entities, TENANT, 'PJ')).rejects.toThrow(
      NotFoundError,
    )
    await expect(requireEntityById(entities, TENANT, 'pj')).rejects.toThrow(
      NotFoundError,
    )
  })
})

describe('service fakes', () => {
  it('refuses an empty certificate and a bad authorization code', async () => {
    expect(() =>
      new FakeCertificateInspector().inspect({
        fileName: 'a.pem',
        bytes: new Uint8Array(),
      }),
    ).toThrow(ValidationError)
    await expect(new FakeMailboxAuthorizer().exchange('bad')).rejects.toThrow(
      ValidationError,
    )
  })
})

describe('uploads and schemas', () => {
  it('decodes base64 within the size limit', () => {
    expect(decodeUpload(btoa('hi'))).toEqual(new Uint8Array([104, 105]))
    expect(() => decodeUpload('%%%')).toThrow('not valid base64')
    expect(() => decodeUpload('')).toThrow('empty')
    expect(() => decodeUpload(btoa('x'.repeat(5 * 1024 * 1024 + 1)))).toThrow(
      '5 MB',
    )
  })

  it('needs a custom range in order and at least one credential', () => {
    const base = { items: ['INVOICES'] }
    expect(
      generateExportSchema.safeParse({ ...base, period: 'LAST_MONTH' }).success,
    ).toBe(true)
    expect(
      generateExportSchema.safeParse({ ...base, period: 'CUSTOM' }).success,
    ).toBe(false)
    expect(
      generateExportSchema.safeParse({
        ...base,
        period: 'CUSTOM',
        from: '2026-02-01',
        to: '2026-01-01',
      }).success,
    ).toBe(false)
    expect(
      generateExportSchema.safeParse({
        ...base,
        period: 'CUSTOM',
        from: '2026-01-01',
        to: '2026-02-01',
      }).success,
    ).toBe(true)
    expect(saveRailCredentialsSchema.safeParse({}).success).toBe(false)
    expect(
      saveRailCredentialsSchema.safeParse({ apiKey: 'abcd' }).success,
    ).toBe(true)
  })
})
