import {
  billKindFor,
  createBill,
  decodePaymentCode,
  type Bill,
  type BillKind,
  type LocalDate,
  Money,
  toLocalDate,
  ValidationError,
} from '@cashdeck/domain'
import { type CaptureBillInput } from '@/dtos/bill'
import { NotFoundError } from '@/errors/errors'
import {
  type BillRepository,
  type FinancialEntityRepository,
} from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'

export type CaptureBillDeps = {
  bills: BillRepository
  entities: FinancialEntityRepository
  clock: Clock
  ids: IdGenerator
}

export type CaptureBillResult = { bill: Bill; duplicate: boolean }

type ResolvedCode = {
  kind: BillKind
  code: string | null
  amount: Money | null
  dueDate: LocalDate | null
  payee: string | null
}

const EMPTY = { amount: null, dueDate: null, payee: null }

function resolveCode(input: CaptureBillInput, today: LocalDate): ResolvedCode {
  if (input.pixKey) {
    return { ...EMPTY, kind: 'PIX_KEY', code: input.pixKey }
  }
  if (!input.paymentCode) {
    return { ...EMPTY, kind: 'DARF_NO_BARCODE', code: null }
  }
  const decoded = decodePaymentCode(input.paymentCode, today)
  const kind = billKindFor(decoded)
  switch (decoded.type) {
    case 'PIX':
      return {
        kind,
        code: decoded.payload,
        amount: decoded.amount,
        dueDate: null,
        payee: decoded.merchantName,
      }
    case 'BOLETO':
      return {
        ...EMPTY,
        kind,
        code: decoded.barcode,
        amount: decoded.amount,
        dueDate: decoded.dueDate,
      }
    case 'ARRECADACAO':
      return { ...EMPTY, kind, code: decoded.barcode, amount: decoded.amount }
  }
}

function resolveAmount(resolved: ResolvedCode, input: CaptureBillInput): Money {
  if (resolved.amount) {
    return resolved.amount
  }
  if (!input.amountCents) {
    throw new ValidationError('This bill needs an amount.')
  }
  return Money.of(input.amountCents)
}

export function makeCaptureBill(deps: CaptureBillDeps) {
  return async function captureBill(
    tenantId: string,
    input: CaptureBillInput,
  ): Promise<CaptureBillResult> {
    const entity = await deps.entities.findById(tenantId, input.entityId)
    if (!entity) {
      throw new NotFoundError('Entity')
    }
    const now = deps.clock.now()
    const today = toLocalDate(now)
    const resolved = resolveCode(input, today)
    const existing = resolved.code
      ? await deps.bills.findByCode(tenantId, entity.id, resolved.code)
      : null
    if (existing) {
      return { bill: existing, duplicate: true }
    }
    const bill = createBill({
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      kind: resolved.kind,
      source: input.source,
      payee: input.payee ?? resolved.payee,
      amount: resolveAmount(resolved, input),
      dueDate: resolved.dueDate ?? input.dueDate ?? today,
      code: resolved.code,
      createdAt: now,
    })
    await deps.bills.save(bill)
    return { bill, duplicate: false }
  }
}
