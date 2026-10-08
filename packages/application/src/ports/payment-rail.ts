import {
  type AttemptOutcome,
  type Bill,
  type BillKind,
  type EntityKind,
  type RailId,
  type StepMode,
} from '@cashdeck/domain'

export type PaymentRequest = {
  bill: Bill
  mode: StepMode
  idempotencyKey: string
}

export type AssistedInstructions = {
  kind: BillKind
  copyCode: string | null
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
}
