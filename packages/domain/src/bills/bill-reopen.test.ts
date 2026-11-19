import { describe, expect, it } from 'vitest'
import {
  canTransition,
  createBill,
  markBillPaid,
  reopenAssisted,
  transitionBill,
} from '@/bills/bill'
import { Money } from '@/money/money'
import { InvalidTransitionError } from '@/shared/domain-error'

const open = () =>
  createBill({
    id: 'b1',
    tenantId: 't1',
    entityId: 'e1',
    kind: 'BOLETO',
    source: 'MANUAL',
    amount: Money.of(1000),
    dueDate: '2026-10-20',
    code: '123',
    createdAt: new Date('2026-10-08T12:00:00Z'),
  })

describe('reopenAssisted', () => {
  it('puts an assisted bill back to open and leaves the table alone', () => {
    const assisted = transitionBill(open(), 'ASSISTED')
    expect(reopenAssisted(assisted)).toEqual({ ...assisted, status: 'OPEN' })
    expect(canTransition('ASSISTED', 'OPEN')).toBe(false)
  })

  it('refuses a bill in any other status', () => {
    expect(() => reopenAssisted(open())).toThrow(InvalidTransitionError)
    const paid = markBillPaid(open(), 'USER', new Date('2026-10-20T13:00:00Z'))
    expect(() => reopenAssisted(paid)).toThrow(InvalidTransitionError)
  })
})
