import { createFinancialEntity, type RailId } from '@cashdeck/domain'
import { type PaymentRail } from '@/ports/payment-rail'
import { type PaymentSettings } from '@/ports/repositories'
import {
  InMemoryAuditLog,
  InMemoryBillRepository,
  InMemoryEntityRepository,
  InMemoryIdempotencyStore,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  StaticPaymentSettings,
} from '@/testing/repositories'
import { FixedClock, SequentialIdGenerator } from '@/testing/system'

export const TENANT = 't1'
export const NOW = new Date('2026-10-08T12:00:00Z')
export const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
export const BOLETO_BARCODE = '00199160500000123450000002800012345678901217'
export const TAX_BARCODE = '85600000001500003282026102000000000000123000'
export const PIX_NO_AMOUNT =
  '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'

export const personal = createFinancialEntity({
  id: 'pf',
  tenantId: TENANT,
  kind: 'PF',
  name: 'Personal',
  taxId: '52998224725',
})

export const company = createFinancialEntity({
  id: 'pj',
  tenantId: TENANT,
  kind: 'PJ',
  name: 'Company',
  taxId: '11222333000181',
  taxRegime: 'SIMPLES_NACIONAL',
})

export function scenario(
  rails: PaymentRail[] = [],
  settings: Partial<PaymentSettings> = {},
) {
  return {
    bills: new InMemoryBillRepository(),
    payments: new InMemoryPaymentRepository(),
    entities: new InMemoryEntityRepository([personal, company]),
    payees: new InMemoryPayeeDirectory(),
    idempotency: new InMemoryIdempotencyStore(),
    audit: new InMemoryAuditLog(),
    settings: new StaticPaymentSettings({
      killSwitch: false,
      enabledRails: rails.map(rail => rail.id),
      dailyCapCents: {},
      confirmAboveCents: null,
      ...settings,
    }),
    rails: new Map<RailId, PaymentRail>(rails.map(rail => [rail.id, rail])),
    clock: new FixedClock(NOW),
    ids: new SequentialIdGenerator(),
  }
}
