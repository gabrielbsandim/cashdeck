import {
  type AttemptOutcome,
  type Bill,
  type BillKind,
  type EntityKind,
  type PaymentMethod,
  type RailId,
  type StepMode,
} from '@cashdeck/domain'
import { type ProviderCheck } from '@/ports/providers'

export type PaymentRequest = {
  bill: Bill
  mode: StepMode
  // PIX pays bill.pixCode (or the Pix key); BOLETO pays the barcode in bill.code.
  method: PaymentMethod
  idempotencyKey: string
}

export type AssistedInstructions = {
  kind: BillKind
  copyCode: string | null
  pixCode: string | null
  amountCents: number
  dueDate: string
}

export type RailResult = {
  outcome: AttemptOutcome
  externalId?: string | null
  reason?: string | null
  instructions?: AssistedInstructions
}

export interface PaymentRail {
  readonly id: RailId
  supports(kind: BillKind, entityKind: EntityKind): boolean
  pay(request: PaymentRequest): Promise<RailResult>
  check(): Promise<ProviderCheck>
}
