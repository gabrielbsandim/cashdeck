import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { account, bill, fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeDocuments } from '@/use-cases/documents'
import { makeRecordTransfer } from '@/use-cases/finance'

const text = (bytes: Uint8Array) => new TextDecoder().decode(bytes)

async function setup() {
  const deps = fullDeps()
  await deps.institutions.save({
    id: 'inst',
    tenantId: TENANT,
    name: 'Bank',
    manual: false,
  })
  await deps.accounts.save(account({ id: 'pj-1', name: 'Operating' }))
  await deps.accounts.save(
    account({ id: 'pf-1', entityId: 'pf', name: 'Checking' }),
  )
  return { deps, documents: makeDocuments(deps) }
}

describe('documents', () => {
  it('renders the receipt of a bill paid through a rail', async () => {
    const { deps, documents } = await setup()
    await deps.bills.save(bill({ id: 'b1', status: 'PAID', paidAt: NOW }))
    await deps.payments.addAttempt(TENANT, {
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
    })
    const file = await documents.receiptPdf(TENANT, 'b1')
    expect(file.fileName).toBe('receipt-b1.pdf')
    expect(text(file.bytes)).toContain('Amount: BRL 123.45')
    expect(text(file.bytes)).toContain('Transaction: pix:1')
  })

  it('renders a bill marked paid by hand from the bill itself', async () => {
    const { deps, documents } = await setup()
    await deps.bills.save(
      bill({ id: 'b2', status: 'PAID', paidAt: NOW, payee: null }),
    )
    const rendered = text((await documents.receiptPdf(TENANT, 'b2')).bytes)
    expect(rendered).toContain('Rail: MANUAL')
    expect(rendered).toContain('Payee: BOLETO')
  })

  it('refuses an unpaid or missing bill', async () => {
    const { deps, documents } = await setup()
    await deps.bills.save(bill({ id: 'b3' }))
    await expect(documents.receiptPdf(TENANT, 'b3')).rejects.toThrow(
      ValidationError,
    )
    await expect(documents.receiptPdf(TENANT, 'x')).rejects.toThrow(
      NotFoundError,
    )
  })

  it('renders a transfer with and without its reference', async () => {
    const { deps, documents } = await setup()
    const record = makeRecordTransfer(deps)
    const plain = await record(TENANT, {
      kind: 'PRO_LABORE',
      amountCents: 1000,
      fromAccountId: 'pj-1',
      toAccountId: 'pf-1',
      rail: 'PIX',
    })
    const referenced = await record(TENANT, {
      kind: 'PROFIT_DISTRIBUTION',
      amountCents: 2000,
      fromAccountId: 'pj-1',
      toAccountId: 'pf-1',
      rail: 'TED',
      document: 'E123',
    })
    const first = await documents.transferPdf(TENANT, plain.id)
    expect(first.fileName).toBe(`transfer-${plain.id}.pdf`)
    expect(text(first.bytes)).toContain('From: Company (PJ), Operating')
    expect(
      text((await documents.transferPdf(TENANT, referenced.id)).bytes),
    ).toContain('Reference: E123')
  })
})
