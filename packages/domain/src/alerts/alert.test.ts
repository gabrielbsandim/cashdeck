import { describe, expect, it } from 'vitest'
import { type Alert, isAlertType, markAlertRead } from '@/alerts/alert'

const alert: Alert = {
  id: 'a1',
  tenantId: 't1',
  type: 'BILL_DUE_SOON',
  entityId: 'pf',
  billId: 'b1',
  invoiceId: null,
  title: 'Conta vence amanhã',
  body: 'Supplier',
  data: {},
  dedupeKey: 'due-soon:b1',
  createdAt: new Date('2026-10-08T12:00:00Z'),
  readAt: null,
}

describe('alerts', () => {
  it('knows its types', () => {
    expect(isAlertType('PAYMENT_PAID')).toBe(true)
    expect(isAlertType('SOMETHING_ELSE')).toBe(false)
  })

  it('keeps the first read time', () => {
    const first = new Date('2026-10-08T13:00:00Z')
    const read = markAlertRead(alert, first)
    expect(read.readAt).toEqual(first)
    expect(markAlertRead(read, new Date('2026-10-09T13:00:00Z'))).toBe(read)
  })
})
