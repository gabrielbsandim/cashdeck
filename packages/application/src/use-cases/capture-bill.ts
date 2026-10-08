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
import { type BillRepository } from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'
import {
  type BuildPaymentPlanDeps,
  makeBuildPaymentPlan,
} from '@/use-cases/build-payment-plan'

export type CaptureBillDeps = BuildPaymentPlanDeps & {
  bills: BillRepository
  clock: Clock
  ids: IdGenerator
}

export type CaptureBillResult = { bill: Bill; duplicate: boolean }

type ResolvedCode = {
  kind: BillKind
  code: string | null
  pixCode: string | null
  amount: Money | null
  dueDate: LocalDate | null
  payee: string | null
}

const EMPTY = { amount: null, dueDate: null, payee: null, pixCode: null }

function decodeCode(raw: string, today: LocalDate): ResolvedCode {
  const decoded = decodePaymentCode(raw, today)
  const kind = billKindFor(decoded)
  switch (decoded.type) {
    case 'PIX':
      return {
        kind,
        code: decoded.payload,
        pixCode: decoded.payload,
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

// A boleto com Pix carries both codes; they must describe the same payment.
function withPixCode(
  barcode: ResolvedCode,
  raw: string,
  today: LocalDate,
): ResolvedCode {
  const pix = decodeCode(raw, today)
  if (barcode.kind === 'PIX_QR' || pix.kind !== 'PIX_QR') {
    throw new ValidationError('pixCode must be a Pix code next to a barcode.')
  }
  if (barcode.amount && pix.amount && !barcode.amount.equals(pix.amount)) {
    throw new ValidationError('The Pix code and the barcode amounts differ.')
  }
  return {
    ...barcode,
    pixCode: pix.pixCode,
    payee: pix.payee,
  }
}

function resolveCode(input: CaptureBillInput, today: LocalDate): ResolvedCode {
  if (input.pixKey) {
    return { ...EMPTY, kind: 'PIX_KEY', code: input.pixKey }
  }
  const primary = input.paymentCode ?? input.pixCode
  if (!primary) {
    return { ...EMPTY, kind: 'DARF_NO_BARCODE', code: null }
  }
  const resolved = decodeCode(primary, today)
  if (!input.paymentCode || !input.pixCode) {
    return resolved
  }
  return withPixCode(resolved, input.pixCode, today)
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
  const buildPlan = makeBuildPaymentPlan(deps)

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
      pixCode: resolved.pixCode,
      createdAt: now,
    })
    await deps.bills.save(bill)
    await buildPlan(tenantId, bill)
    return { bill, duplicate: false }
  }
}
