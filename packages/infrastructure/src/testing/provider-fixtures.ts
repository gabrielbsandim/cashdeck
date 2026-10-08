import { type PaymentRequest } from '@cashdeck/application'
import {
  type Bill,
  type BillKind,
  crc16,
  encodeBrCode,
  Money,
} from '@cashdeck/domain'
import { CredentialResolver } from '@/credentials/credential-resolver'

export const TENANT = 'tenant-1'
export const ENTITY = 'entity-1'
export const TODAY = '2026-10-08'

export const BOLETO_LINE = '00190000090280001234256789012178916050000012345'
export const TAX_BARCODE = '85600000001500003282026102000000000000123000'

export const STATIC_PIX = encodeBrCode({
  key: '123e4567-e12b-12d1-a456-426655440000',
  merchantName: 'Energia Exemplo',
  merchantCity: 'SAO PAULO',
  amount: Money.of(12345),
  txid: 'FATURA1',
})

const LOCATION = '0014br.gov.bcb.pix2525pix.example.com/qr/v2/abc'
const DYNAMIC_BODY =
  '000201010212' +
  `26${LOCATION.length}${LOCATION}` +
  '52040000530398654041.005802BR5905Store6004City6304'
export const DYNAMIC_PIX = DYNAMIC_BODY + crc16(DYNAMIC_BODY)

export function bill(
  overrides: Partial<Bill> & { pixCode?: string | null } = {},
): Bill {
  return {
    id: 'bill-1',
    tenantId: TENANT,
    entityId: ENTITY,
    kind: 'BOLETO' as BillKind,
    status: 'OPEN',
    source: 'MANUAL',
    payee: 'Energia Exemplo',
    amount: Money.of(12345),
    dueDate: TODAY,
    code: BOLETO_LINE,
    createdAt: new Date('2026-10-01T12:00:00Z'),
    paidAt: null,
    paidBy: null,
    ...overrides,
  } as Bill
}

export function payment(
  overrides: Partial<Bill> & { pixCode?: string | null } = {},
): PaymentRequest {
  return {
    bill: bill(overrides),
    mode: 'AUTOMATIC',
    method: overrides.pixCode ? 'PIX' : 'BOLETO',
    idempotencyKey: 'bill-1:0',
  }
}

export function credentials(env: Record<string, string>): CredentialResolver {
  return new CredentialResolver({ env, tenantId: TENANT })
}
