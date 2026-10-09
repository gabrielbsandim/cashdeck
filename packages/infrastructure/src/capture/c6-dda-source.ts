import { type BillSource, type CapturedBill } from '@cashdeck/application'
import {
  billKindFor,
  decodePaymentCode,
  type BillKind,
  toLocalDate,
  validBrCode,
} from '@cashdeck/domain'
import { type Credentials } from '@/credentials/credential-resolver'
import { toCents } from '@/http/transport'
import { BankClients } from '@/rails/bank-client'
import { c6Call, c6Client } from '@/rails/c6-client'

// The Pix field names are unconfirmed (docs/providers.md); each candidate is
// kept only when its BR Code checksum holds.
const PIX_FIELDS = [
  'pix_qr_code',
  'pix_copy_paste',
  'pix_code',
  'qr_code',
  'emv',
] as const

type Bond = {
  amount?: number
  beneficiary_name?: string | null
  content?: string
  due_date?: string | null
} & Partial<Record<(typeof PIX_FIELDS)[number], unknown>>

function pixCodeOf(bond: Bond): string | null {
  for (const field of PIX_FIELDS) {
    const value = bond[field]
    const pixCode = typeof value === 'string' ? validBrCode(value) : null
    if (pixCode) {
      return pixCode
    }
  }
  return null
}

export type C6DdaSourceDeps = {
  credentials: Credentials
  clients?: BankClients
  now?: () => Date
}

export class C6DdaBillSource implements BillSource {
  readonly source = 'DDA' as const

  private readonly clients: BankClients

  constructor(private readonly deps: C6DdaSourceDeps) {
    this.clients = deps.clients ?? new BankClients()
  }

  async fetch(tenantId: string, entityId: string): Promise<CapturedBill[]> {
    const client = await c6Client(this.deps.credentials, this.clients, {
      tenantId,
      entityId,
    })
    const answer = await c6Call<{ items?: Bond[] }>(client, {
      method: 'GET',
      url: '/query',
    })
    if (!answer.ok) {
      throw new Error(answer.reason)
    }
    const today = toLocalDate((this.deps.now ?? (() => new Date()))())
    return (answer.data.items ?? [])
      .filter(bond => Boolean(bond.content))
      .map(bond => this.toCaptured(bond, today))
  }

  private toCaptured(bond: Bond, today: string): CapturedBill {
    const code = (bond.content ?? '').trim()
    const cents = toCents(bond.amount)
    return {
      externalId: `dda:${code}`,
      paymentCode: code,
      pixCode: pixCodeOf(bond),
      payee: bond.beneficiary_name ?? null,
      amountCents: cents > 0 ? cents : null,
      dueDate: bond.due_date ?? null,
      kind: kindOf(code, today),
    }
  }
}

function kindOf(code: string, today: string): BillKind {
  try {
    return billKindFor(decodePaymentCode(code, today))
  } catch {
    return 'BOLETO'
  }
}
