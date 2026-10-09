import { describe, expect, it } from 'vitest'
import {
  billKindFor,
  canTransition,
  createBill,
  isSettled,
  markBillPaid,
  markBillUnpaid,
  transitionBill,
} from '@/bills/bill'
import { decodePaymentCode } from '@/codes/payment-code'
import { Money } from '@/money/money'
import { InvalidTransitionError } from '@/shared/domain-error'

const PIX =
  '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'

const input = {
  id: 'b1',
  tenantId: 't1',
  entityId: 'e1',
  kind: 'BOLETO' as const,
  source: 'MANUAL' as const,
  amount: Money.of(1000),
  dueDate: '2026-10-20',
  code: ' 123 ',
  createdAt: new Date('2026-10-08T12:00:00Z'),
}

describe('createBill', () => {
  it('opens a bill with a trimmed code and payee', () => {
    const bill = createBill({ ...input, payee: '  Utility  ' })
    expect(bill.status).toBe('OPEN')
    expect(bill.code).toBe('123')
    expect(bill.payee).toBe('Utility')
    expect(createBill(input).payee).toBeNull()
  })

  it('allows a DARF without a barcode only', () => {
    expect(
      createBill({ ...input, kind: 'DARF_NO_BARCODE', code: null }).code,
    ).toBeNull()
    expect(() => createBill({ ...input, code: ' ' })).toThrow(
      'A BOLETO bill needs its payment code.',
    )
    expect(() => createBill({ ...input, code: undefined })).toThrow(
      'payment code',
    )
  })

  it('keeps the BR Code of a boleto com Pix and of a Pix QR bill', () => {
    expect(createBill(input).pixCode).toBeNull()
    expect(createBill({ ...input, pixCode: ` ${PIX} ` }).pixCode).toBe(PIX)
    expect(createBill({ ...input, kind: 'PIX_QR', code: PIX }).pixCode).toBe(
      PIX,
    )
    expect(() =>
      createBill({ ...input, pixCode: `${PIX.slice(0, -1)}0` }),
    ).toThrow('checksum')
  })

  it('rejects non positive amounts', () => {
    expect(() => createBill({ ...input, amount: Money.zero() })).toThrow(
      'positive',
    )
  })
})

describe('billKindFor', () => {
  it('maps decoded codes to bill kinds', () => {
    const pix =
      '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'
    expect(billKindFor(decodePaymentCode(pix, '2026-10-08'))).toBe('PIX_QR')
    expect(
      billKindFor(
        decodePaymentCode(
          '85600000001500003282026102000000000000123000',
          '2026-10-08',
        ),
      ),
    ).toBe('TAX_BARCODE')
    expect(
      billKindFor(
        decodePaymentCode(
          '83820000000999000552026102000000000000456000',
          '2026-10-08',
        ),
      ),
    ).toBe('BOLETO')
    expect(
      billKindFor(
        decodePaymentCode(
          '00199160500000123450000002800012345678901217',
          '2026-10-08',
        ),
      ),
    ).toBe('BOLETO')
  })
})

describe('bill transitions', () => {
  it('follows the transition table', () => {
    const bill = createBill(input)
    expect(transitionBill(bill, 'OPEN')).toBe(bill)
    expect(transitionBill(bill, 'PROCESSING').status).toBe('PROCESSING')
    expect(canTransition('PAID', 'OPEN')).toBe(false)
    const cancelled = transitionBill(bill, 'CANCELLED')
    expect(() => transitionBill(cancelled, 'OPEN')).toThrow(
      InvalidTransitionError,
    )
    expect(isSettled(cancelled)).toBe(true)
    expect(isSettled(bill)).toBe(false)
  })

  it('records who paid and when', () => {
    const at = new Date('2026-10-20T13:00:00Z')
    const paid = markBillPaid(createBill(input), 'USER', at)
    expect(paid).toMatchObject({ status: 'PAID', paidBy: 'USER', paidAt: at })
    expect(isSettled(paid)).toBe(true)
  })

  it('takes back only a payment the user declared', () => {
    const at = new Date('2026-10-20T13:00:00Z')
    const bill = createBill(input)
    const reopened = markBillUnpaid(markBillPaid(bill, 'USER', at))
    expect(reopened).toMatchObject({
      status: 'OPEN',
      paidAt: null,
      paidBy: null,
    })
    expect(() => markBillUnpaid(markBillPaid(bill, 'RAIL', at))).toThrow(
      InvalidTransitionError,
    )
    expect(() => markBillUnpaid(markBillPaid(bill, 'STATEMENT', at))).toThrow(
      InvalidTransitionError,
    )
    expect(() => markBillUnpaid(bill)).toThrow(InvalidTransitionError)
  })
})
