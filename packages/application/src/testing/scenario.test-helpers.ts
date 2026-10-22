import {
  type Bill,
  crc16,
  createFinancialEntity,
  type RailId,
  recipientKeys,
} from '@cashdeck/domain'
import { type PaymentRail } from '@/ports/payment-rail'
import { type RailStatusReader } from '@/ports/rail-status'
import { type PayeeDirectory, type PaymentSettings } from '@/ports/repositories'
import { InMemoryAlertRepository } from '@/testing/alerts'
import { FakeReserveFunder } from '@/testing/providers'
import {
  InMemoryAuditLog,
  InMemoryBillRepository,
  InMemoryEntityRepository,
  InMemoryFundingRepository,
  InMemoryIdempotencyStore,
  InMemoryPayeeDirectory,
  InMemoryPaymentRepository,
  StaticPaymentSettings,
} from '@/testing/repositories'
import {
  InMemoryDocumentStore,
  InMemoryInstitutionRepository,
} from '@/testing/records'
import { FixedClock, SequentialIdGenerator } from '@/testing/system'

export const TENANT = 't1'
export const NOW = new Date('2026-10-08T12:00:00Z')
export const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
export const BOLETO_BARCODE = '00199160500000123450000002800012345678901217'
export const TAX_BARCODE = '85600000001500003282026102000000000000123000'
export const PIX_NO_AMOUNT =
  '00020126580014br.gov.bcb.pix0136123e4567-e12b-12d1-a456-4266554400005204000053039865802BR5913Fulano de Tal6008BRASILIA62070503***63041D3D'

// A dynamic BR Code: the amount lives behind the location, not in the code.
export function dynamicPix(location: string, city = 'SAO PAULO'): string {
  const account = `0014br.gov.bcb.pix25${String(location.length).padStart(2, '0')}${location}`
  const tail = `5802BR5918Fornecedor Exemplo60${String(city.length).padStart(2, '0')}${city}62070503***6304`
  const body = `000201010212${`26${account.length}${account}`}520400005303986${tail}`
  return body + crc16(body)
}

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
  const bills = new InMemoryBillRepository()
  return {
    bills,
    alertStore: new InMemoryAlertRepository(),
    payments: new InMemoryPaymentRepository(bills),
    fundings: new InMemoryFundingRepository(),
    funder: new FakeReserveFunder(),
    railStatus: new Map<RailId, RailStatusReader>(),
    entities: new InMemoryEntityRepository([personal, company]),
    payees: new InMemoryPayeeDirectory(),
    idempotency: new InMemoryIdempotencyStore(),
    audit: new InMemoryAuditLog(),
    settings: new StaticPaymentSettings({
      killSwitch: false,
      enabledRails: rails.map(rail => rail.id),
      dailyCapCents: {},
      confirmAboveCents: null,
      entityDailyCapCents: null,
      paymentCapCents: null,
      maxDeviationPercent: null,
      approvalCutoff: '16:00',
      ...settings,
    }),
    rails: new Map<RailId, PaymentRail>(rails.map(rail => [rail.id, rail])),
    documents: new InMemoryDocumentStore(),
    institutions: new InMemoryInstitutionRepository(),
    clock: new FixedClock(NOW),
    ids: new SequentialIdGenerator(),
  }
}

// Marks every recipient of the bill as already confirmed.
export async function trust(payees: PayeeDirectory, bill: Bill): Promise<void> {
  for (const key of recipientKeys(bill)) {
    await payees.remember(bill.tenantId, bill.entityId, key)
  }
}
