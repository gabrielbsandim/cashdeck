import { describe, expect, it } from 'vitest'
import { Money, type PaymentAttempt } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { base64, bill, fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeReceipts } from '@/use-cases/receipts'

const attempt = (overrides: Partial<PaymentAttempt>): PaymentAttempt => ({
  id: 'a1',
  billId: 'b1',
  stepIndex: 0,
  rail: 'ASAAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(12345),
  outcome: 'PAID',
  reason: null,
  externalId: 'pix:1',
  idempotencyKey: 'b1:0:PIX',
  at: NOW,
  ...overrides,
})

describe('receipts', () => {
  it('shows the rail proof and the attachments of a paid bill', async () => {
    const deps = fullDeps()
    await deps.bills.save(
      bill({
        id: 'b1',
        status: 'PAID',
        paidAt: new Date('2026-10-09T10:00:00Z'),
      }),
    )
    await deps.payments.addAttempt(
      TENANT,
      attempt({ id: 'a0', outcome: 'FAILED' }),
    )
    await deps.payments.addAttempt(TENANT, attempt({}))
    const receipts = makeReceipts(deps)
    const added = await receipts.addAttachment(TENANT, 'b1', {
      fileName: 'proof.pdf',
      mimeType: 'application/pdf',
      base64: base64('proof'),
    })
    expect(added).toEqual({
      id: added.id,
      fileName: 'proof.pdf',
      mimeType: 'application/pdf',
      bytes: 5,
    })
    const receipt = await receipts.receipt(TENANT, 'b1')
    expect(receipt.proof).toEqual({
      rail: 'ASAAS',
      amount: { cents: 12345, currency: 'BRL' },
      paidAt: '2026-10-09T10:00:00.000Z',
      payer: 'Personal',
      receiver: 'Supplier',
      transactionId: 'pix:1',
      authentication: null,
    })
    expect(receipt.attachments).toEqual([added])
    const file = await receipts.attachment(TENANT, 'b1', added.id)
    expect(new TextDecoder().decode(file.bytes)).toBe('proof')
    await expect(
      receipts.attachment(TENANT, 'other', added.id),
    ).rejects.toThrow(NotFoundError)
    await expect(receipts.attachment(TENANT, 'b1', 'nope')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('has no proof when the user paid, and falls back to the attempt time', async () => {
    const deps = fullDeps()
    await deps.bills.save(bill({ id: 'b1', payee: null }))
    const receipts = makeReceipts(deps)
    expect((await receipts.receipt(TENANT, 'b1')).proof).toBeNull()
    await deps.payments.addAttempt(TENANT, attempt({}))
    expect((await receipts.receipt(TENANT, 'b1')).proof).toMatchObject({
      paidAt: NOW.toISOString(),
      receiver: '',
    })
    await expect(receipts.receipt(TENANT, 'nope')).rejects.toThrow(
      NotFoundError,
    )
  })
})
