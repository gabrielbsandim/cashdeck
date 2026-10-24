import { describe, expect, it } from 'vitest'
import { Money, ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { account, bill, fullDeps } from '@/testing/deps.test-helpers'
import { NOW, TENANT } from '@/testing/scenario.test-helpers'
import { makeDocuments, type ReceiptCopy } from '@/use-cases/documents'
import { makeRecordTransfer } from '@/use-cases/finance'

const text = (bytes: Uint8Array) => new TextDecoder().decode(bytes)

const copy: ReceiptCopy = {
  locale: 'en',
  billKind: {
    BOLETO: 'Boleto',
    PIX_KEY: 'Pix to a key',
    PIX_QR: 'Pix copy and paste',
    TAX_BARCODE: 'Tax guide',
    DARF_NO_BARCODE: 'DARF',
  },
  receipt: {
    payment: 'Payment receipt',
    transfer: 'Transfer receipt',
    paidOn: 'Paid on',
    madeOn: 'Made on',
    to: 'To',
    from: 'From',
    details: 'Details',
    name: 'Name',
    key: 'Pix key',
    code: 'Code',
    kind: 'Type',
    dueDate: 'Due date',
    paidBy: 'Paid through',
    manual: 'Marked as paid',
    transaction: 'Transaction ID',
    account: 'Account',
    reference: 'Reference',
    footer: 'Generated on',
    transferKind: {
      PROFIT_DISTRIBUTION: 'Profit distribution',
      PRO_LABORE: 'Pro-labore',
    },
  },
}

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
    const file = await documents.receiptPdf(TENANT, 'b1', copy)
    expect(file.fileName).toBe('receipt-b1.pdf')
    const rendered = text(file.bytes)
    expect(rendered).toContain('R$123.45')
    expect(rendered).toContain('Paid through: Asaas')
    expect(rendered).toContain('Code: code-b1')
    expect(rendered).toContain('Due date: 10/20/26')
    expect(rendered).toContain('Transaction ID: 1\n')
  })

  it('renders a bill marked paid by hand from the bill itself', async () => {
    const { deps, documents } = await setup()
    await deps.bills.save(
      bill({
        id: 'b2',
        kind: 'PIX_KEY',
        code: '+5511900000000',
        status: 'PAID',
        paidAt: new Date('2026-10-23T23:06:00Z'),
        payee: null,
      }),
    )
    await deps.bills.save(
      bill({ id: 'b4', kind: 'PIX_QR', status: 'PAID', paidAt: NOW }),
    )
    const rendered = text(
      (await documents.receiptPdf(TENANT, 'b2', copy)).bytes,
    )
    expect(rendered).toContain('Paid on 10/23/26, 8:06 PM')
    expect(rendered).toContain('Paid through: Marked as paid')
    expect(rendered).toContain('Pix key: +5511900000000')
    expect(rendered).not.toContain('Name:')
    await deps.bills.save(
      bill({ id: 'b5', code: null, status: 'PAID', paidAt: NOW }),
    )
    for (const id of ['b4', 'b5']) {
      const shown = text((await documents.receiptPdf(TENANT, id, copy)).bytes)
      expect(shown).not.toContain('Code:')
    }
  })

  it('refuses an unpaid or missing bill', async () => {
    const { deps, documents } = await setup()
    await deps.bills.save(bill({ id: 'b3' }))
    await expect(documents.receiptPdf(TENANT, 'b3', copy)).rejects.toThrow(
      ValidationError,
    )
    await expect(documents.receiptPdf(TENANT, 'x', copy)).rejects.toThrow(
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
    const first = await documents.transferPdf(TENANT, plain.id, copy)
    expect(first.fileName).toBe(`transfer-${plain.id}.pdf`)
    expect(text(first.bytes)).toContain('Account: Operating')
    expect(text(first.bytes)).toContain('Type: Pro-labore')
    expect(text(first.bytes)).not.toContain('Reference:')
    expect(
      text((await documents.transferPdf(TENANT, referenced.id, copy)).bytes),
    ).toContain('Reference: E123')
  })
})
