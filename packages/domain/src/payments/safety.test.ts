import { describe, expect, it } from 'vitest'
import { type Bill, createBill } from '@/bills/bill'
import { crc16, encodeBrCode } from '@/codes/br-code'
import { Money } from '@/money/money'
import {
  attemptHistory,
  committedCentsOn,
  inFlightAttempt,
  latestAttempts,
  type PaymentAttempt,
} from '@/payments/payment-plan'
import {
  normalizeName,
  normalizePixKey,
  recipientKeys,
} from '@/payments/recipient'
import {
  fundingFor,
  fundingKey,
  fundingShortfall,
  isFunded,
  type ReserveFunding,
} from '@/payments/reserve-funding'
import {
  approvalCutoff,
  approvalExpired,
  assertCutoff,
  deviatesFromHistory,
} from '@/payments/safety'

const BOLETO_BARCODE = '00199160500000123450000002800012345678901217'
const TAX_BARCODE = '85600000001500003282026102000000000000123000'
const STATIC_PIX = encodeBrCode({
  key: 'Supplier@Example.com',
  merchantName: 'Supplier',
  merchantCity: 'Sao Paulo',
})

function dynamicPix(): string {
  const account = '0014br.gov.bcb.pix2520pix.example.com/qr/1'
  const body =
    '000201010212' +
    `26${account.length}${account}` +
    '52040000530398654041.005802BR5912Loja Açaí  X6004City6304'
  return body + crc16(body)
}

function bill(overrides: Partial<Bill> = {}): Bill {
  return {
    ...createBill({
      id: 'b1',
      tenantId: 't1',
      entityId: 'pf',
      kind: 'BOLETO',
      source: 'MANUAL',
      payee: 'Supplier',
      amount: Money.of(12345),
      dueDate: '2026-10-20',
      code: BOLETO_BARCODE,
      createdAt: new Date(0),
    }),
    ...overrides,
  }
}

const attempt = (
  key: string,
  outcome: PaymentAttempt['outcome'],
  at: string,
  cents = 100,
): PaymentAttempt => ({
  id: `${key}:${outcome}`,
  billId: 'b1',
  stepIndex: 0,
  rail: 'ASAAS',
  mode: 'AUTOMATIC',
  method: 'PIX',
  amount: Money.of(cents),
  outcome,
  reason: null,
  externalId: null,
  idempotencyKey: key,
  at: new Date(at),
})

describe('recipientKeys', () => {
  it('keys a Pix bill by the normalised key', () => {
    expect(
      recipientKeys(bill({ kind: 'PIX_KEY', code: '123.456.789-09' })),
    ).toEqual(['pix:12345678909'])
    expect(
      recipientKeys(bill({ kind: 'PIX_QR', code: STATIC_PIX, pixCode: null })),
    ).toEqual(['pix:supplier@example.com'])
  })

  it('keys a dynamic code by the merchant it names', () => {
    expect(
      recipientKeys(
        bill({ kind: 'PIX_QR', code: null, pixCode: dynamicPix() }),
      ),
    ).toEqual(['pix-merchant:LOJA ACAI X:CITY'])
  })

  it('names both recipients of a bolepix', () => {
    expect(recipientKeys(bill({ pixCode: STATIC_PIX }))).toEqual([
      'pix:supplier@example.com',
      'boleto:001:SUPPLIER',
    ])
  })

  it('keys an unnamed boleto by its whole code', () => {
    expect(recipientKeys(bill({ payee: null }))).toEqual([
      `boleto:001:code:${BOLETO_BARCODE}`,
    ])
  })

  it('keys a collection barcode by its segment and collector', () => {
    expect(
      recipientKeys(bill({ kind: 'TAX_BARCODE', code: TAX_BARCODE })),
    ).toEqual(['collector:5:0328'])
  })

  it('falls back to the kind and payee without a usable code', () => {
    expect(
      recipientKeys(bill({ kind: 'DARF_NO_BARCODE', code: null })),
    ).toEqual(['darf_no_barcode:SUPPLIER'])
    expect(
      recipientKeys(bill({ kind: 'BOLETO', code: STATIC_PIX, payee: null })),
    ).toEqual(['boleto:b1'])
    expect(recipientKeys(bill({ kind: 'PIX_KEY', code: null }))).toEqual([
      'pix_key:SUPPLIER',
    ])
  })

  it('gives an unreadable code a key of its own', () => {
    expect(recipientKeys(bill({ code: '123' }))).toEqual(['unreadable:b1'])
  })
})

describe('normalizers', () => {
  it('normalises keys and names', () => {
    expect(normalizePixKey(' +55 (11) 99999-0000 ')).toBe('+5511999990000')
    expect(normalizePixKey('ABC-def 12')).toBe('abc-def12')
    expect(normalizeName('  José   da  Silva ')).toBe('JOSE DA SILVA')
  })
})

describe('deviatesFromHistory', () => {
  it('compares with the median of the latest paid amounts', () => {
    expect(deviatesFromHistory(10_000, [], 30)).toBe(false)
    expect(deviatesFromHistory(10_000, [1], null)).toBe(false)
    expect(deviatesFromHistory(13_000, [10_000], 30)).toBe(false)
    expect(deviatesFromHistory(13_001, [10_000], 30)).toBe(true)
    expect(deviatesFromHistory(6_000, [10_000, 9_000, 50_000, 1], 30)).toBe(
      true,
    )
    expect(deviatesFromHistory(9_000, [8_000, 10_000], 30)).toBe(false)
  })
})

describe('approval cutoff', () => {
  it('reads the cutoff in Sao Paulo time', () => {
    expect(approvalCutoff('2026-10-20', '16:00').toISOString()).toBe(
      '2026-10-20T19:00:00.000Z',
    )
    expect(
      approvalExpired('2026-10-20', '16:00', new Date('2026-10-20T19:00:00Z')),
    ).toBe(false)
    expect(
      approvalExpired('2026-10-20', '16:00', new Date('2026-10-20T19:00:01Z')),
    ).toBe(true)
    expect(assertCutoff('23:59')).toBe('23:59')
    expect(() => assertCutoff('24:00')).toThrow('HH:MM')
  })
})

describe('attempt history', () => {
  it('keeps the last row of each idempotency key', () => {
    const rows = [
      attempt('a', 'IN_FLIGHT', '2026-10-08T12:00:00Z'),
      attempt('b', 'IN_FLIGHT', '2026-10-08T12:00:00Z'),
      attempt('a', 'SUBMITTED', '2026-10-08T12:00:01Z'),
    ]
    expect(latestAttempts(rows).map(row => row.id)).toEqual([
      'a:SUBMITTED',
      'b:IN_FLIGHT',
    ])
    expect(inFlightAttempt(rows)?.idempotencyKey).toBe('b')
    expect(attemptHistory(rows).map(row => row.id)).toEqual([
      'b:IN_FLIGHT',
      'a:SUBMITTED',
    ])
    expect(inFlightAttempt(rows.slice(0, 1).concat(rows[2]!))).toBeNull()
  })

  it('counts each payment once, on the day it was first tried', () => {
    const rows = [
      attempt('a', 'IN_FLIGHT', '2026-10-08T12:00:00Z', 100),
      attempt('a', 'PAID', '2026-10-09T12:00:00Z', 100),
      attempt('b', 'IN_FLIGHT', '2026-10-08T12:00:00Z', 200),
      attempt('b', 'FAILED', '2026-10-08T12:00:01Z', 200),
      attempt('c', 'PENDING_APPROVAL', '2026-10-08T12:00:00Z', 400),
      attempt('d', 'SUBMITTED', '2026-10-09T12:00:00Z', 800),
    ]
    expect(committedCentsOn(rows, '2026-10-08')).toBe(500)
    expect(committedCentsOn(rows, '2026-10-09')).toBe(800)
  })
})

describe('reserve funding', () => {
  const round = (
    billIds: string[],
    status: ReserveFunding['status'],
  ): ReserveFunding => ({
    id: status,
    tenantId: 't1',
    entityId: 'pf',
    day: '2026-10-08',
    round: 1,
    billIds,
    billsTotal: Money.of(100),
    available: null,
    amount: Money.of(100),
    status,
    reason: null,
    externalId: null,
    idempotencyKey: fundingKey('pf', '2026-10-08', 1),
    at: new Date(0),
  })

  it('sizes the shortfall and finds the round of a bill', () => {
    expect(fundingKey('pf', '2026-10-08', 2)).toBe('reserve:pf:2026-10-08:2')
    expect(fundingShortfall(1000, 300)).toBe(700)
    expect(fundingShortfall(1000, -50)).toBe(1000)
    expect(fundingShortfall(1000, 5000)).toBe(0)
    expect(isFunded('SUBMITTED')).toBe(true)
    expect(isFunded('NOT_NEEDED')).toBe(true)
    expect(isFunded('IN_FLIGHT')).toBe(false)
    const rounds = [round(['b1'], 'FAILED'), round(['b1', 'b2'], 'PAID')]
    expect(fundingFor(rounds, 'b1')?.status).toBe('PAID')
    expect(fundingFor(rounds, 'b3')).toBeNull()
  })
})
