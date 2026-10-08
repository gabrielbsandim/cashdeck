import {
  type PaymentRail,
  type PaymentRequest,
  type ProviderCheck,
  type RailResult,
  type RailStatus,
  type RailStatusReader,
  type RailStatusScope,
} from '@cashdeck/application'
import { type BillKind, type EntityKind } from '@cashdeck/domain'
import { type Credentials } from '@/credentials/credential-resolver'
import { toDecimal } from '@/http/transport'
import { BankClients } from '@/rails/bank-client'
import { C6_PROVIDER, c6Call, c6Client } from '@/rails/c6-client'
import {
  decodePix,
  normalizePixKey,
  paymentDescription,
  pixPayloadOf,
  staticAmountMismatch,
} from '@/rails/pix'
import {
  checkWith,
  type Coverage,
  covers,
  failed,
  outcomeFrom,
  scopeOf,
  statusResult,
} from '@/rails/rail-support'

// The batch is approved by a person in C6 web banking, so it only serves the
// bank approval step and accepts BOLETO and PIX content, never tax guides.
const COVERAGE: Coverage = {
  entityKinds: ['PJ'],
  billKinds: ['BOLETO', 'PIX_KEY', 'PIX_QR'],
}

const ITEM_OUTCOME = {
  READ_DATA: 'PENDING_APPROVAL',
  PROCESSED: 'PENDING_APPROVAL',
  PROCESSING: 'PENDING_APPROVAL',
  SCHEDULED: 'SUBMITTED',
  ERROR: 'FAILED',
  DECODE_ERROR: 'FAILED',
  SCHEDULING_CANCELLED: 'FAILED',
} as const

const ITEM_FAILURES = new Set(['ERROR', 'DECODE_ERROR', 'SCHEDULING_CANCELLED'])

type GroupItem = {
  id?: string
  status?: string
  error_message?: string | null
}

export type C6EmpresasRailDeps = {
  credentials: Credentials
  clients?: BankClients
}

export class C6EmpresasRail implements PaymentRail, RailStatusReader {
  readonly id = 'C6_EMPRESAS' as const

  private readonly clients: BankClients

  constructor(private readonly deps: C6EmpresasRailDeps) {
    this.clients = deps.clients ?? new BankClients()
  }

  supports(kind: BillKind, entityKind: EntityKind): boolean {
    return covers(COVERAGE, kind, entityKind)
  }

  async pay(request: PaymentRequest): Promise<RailResult> {
    const { bill } = request
    const content = this.content(request)
    if (content === null) {
      return failed('PIX_AMOUNT_MISMATCH')
    }
    const client = await c6Client(
      this.deps.credentials,
      this.clients,
      scopeOf(bill),
    )
    const decoded = await c6Call<{ group_id?: string }>(client, {
      method: 'POST',
      url: '/decode',
      json: {
        items: [
          {
            content,
            amount: toDecimal(bill.amount.cents),
            description: paymentDescription(bill).slice(0, 100),
            transaction_date: bill.dueDate,
          },
        ],
      },
    })
    if (!decoded.ok) {
      return failed(decoded.reason)
    }
    const groupId = decoded.data.group_id ?? ''
    const items = await c6Call<{ items?: GroupItem[] }>(client, {
      method: 'GET',
      url: `/${groupId}/items`,
    })
    if (!items.ok) {
      return failed(items.reason)
    }
    const item = items.data.items?.[0] ?? {}
    if (ITEM_FAILURES.has(item.status ?? '')) {
      return failed(item.error_message ?? 'C6 could not read the payment.')
    }
    const submitted = await c6Call<unknown>(client, {
      method: 'POST',
      url: '/submit',
      json: { group_id: groupId, uploader_name: client.uploaderName },
    })
    if (!submitted.ok) {
      return failed(submitted.reason)
    }
    return {
      outcome: 'PENDING_APPROVAL',
      externalId: `${groupId}/${item.id ?? ''}`,
      reason: null,
    }
  }

  async status(
    externalId: string,
    scope: RailStatusScope,
  ): Promise<RailStatus> {
    const [groupId, itemId] = externalId.split('/')
    if (!groupId) {
      throw new Error(
        `${C6_PROVIDER} does not know the payment "${externalId}".`,
      )
    }
    const client = await c6Client(this.deps.credentials, this.clients, scope)
    const items = await c6Call<{ items?: GroupItem[] }>(client, {
      method: 'GET',
      url: `/${groupId}/items`,
    })
    if (!items.ok) {
      return statusResult('FAILED', externalId, { reason: items.reason })
    }
    const item = items.data.items?.find(candidate => candidate.id === itemId)
    return statusResult(
      outcomeFrom(ITEM_OUTCOME, item?.status, 'PENDING_APPROVAL'),
      externalId,
      { reason: item?.error_message ?? null },
    )
  }

  async check(): Promise<ProviderCheck> {
    return checkWith(C6_PROVIDER, async () => {
      const client = await c6Client(this.deps.credentials, this.clients, {})
      const answer = await c6Call<unknown>(client, {
        method: 'GET',
        url: '/query',
      })
      if (!answer.ok) {
        throw new Error(answer.reason)
      }
    })
  }

  private content(request: PaymentRequest): string | null {
    const { bill } = request
    const pix = pixPayloadOf(bill, request.method)
    if (pix) {
      const decoded = decodePix(pix)
      return staticAmountMismatch(decoded, bill) ? null : decoded.payload
    }
    if (bill.kind === 'PIX_KEY') {
      return normalizePixKey(bill.code ?? '')
    }
    return bill.code ?? ''
  }
}
