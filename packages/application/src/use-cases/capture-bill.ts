import {
  billKindFor,
  createBill,
  decodePaymentCode,
  type Bill,
  type BillKind,
  type LocalDate,
  Money,
  toLocalDate,
  validBrCode,
  ValidationError,
} from '@cashdeck/domain'
import { type CaptureBillInput } from '@/dtos/bill'
import { AmountRequiredError, NotFoundError } from '@/errors/errors'
import { type AlertEmitter } from '@/ports/alerts'
import { type PixCharge, type PixLocationResolver } from '@/ports/providers'
import { type AuditLog, type BillRepository } from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'
import {
  completesHalf,
  type IncomingBill,
  sameLocation,
  withMissingHalf,
} from '@/use-cases/bill-pairing'
import {
  type BuildPaymentPlanDeps,
  makeBuildPaymentPlan,
} from '@/use-cases/build-payment-plan'
import { billAlert, emitAlert } from '@/use-cases/alert-events'

export type CaptureBillDeps = BuildPaymentPlanDeps & {
  bills: BillRepository
  audit: AuditLog
  clock: Clock
  ids: IdGenerator
  pixLocations?: PixLocationResolver
  alerts?: AlertEmitter
}

export type CaptureBillResult = { bill: Bill; duplicate: boolean }

export type PixDropReason =
  | 'INVALID_PIX_CODE'
  | 'AMOUNT_MISMATCH'
  | 'CHARGE_AMOUNT_MISMATCH'

type ResolvedCode = {
  kind: BillKind
  code: string | null
  pixCode: string | null
  location: string | null
  amount: Money | null
  dueDate: LocalDate | null
  payee: string | null
}

type Resolution = { resolved: ResolvedCode; dropped: PixDropReason | null }

const EMPTY = {
  amount: null,
  dueDate: null,
  payee: null,
  pixCode: null,
  location: null,
}

function decodeCode(raw: string, today: LocalDate): ResolvedCode {
  const decoded = decodePaymentCode(raw, today)
  const kind = billKindFor(decoded)
  switch (decoded.type) {
    case 'PIX':
      return {
        kind,
        code: decoded.payload,
        pixCode: decoded.payload,
        location: decoded.url,
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

// A boleto com Pix carries both codes. A Pix half that does not validate or
// disagrees with the barcode is dropped: the barcode alone still pays the bill.
function withPixCode(
  barcode: ResolvedCode,
  raw: string,
  today: LocalDate,
): Resolution {
  const payload = validBrCode(raw)
  if (payload === null) {
    return { resolved: barcode, dropped: 'INVALID_PIX_CODE' }
  }
  const pix = decodeCode(payload, today)
  if (barcode.amount && pix.amount && !barcode.amount.equals(pix.amount)) {
    return { resolved: barcode, dropped: 'AMOUNT_MISMATCH' }
  }
  return {
    resolved: {
      ...barcode,
      pixCode: pix.pixCode,
      location: pix.location,
      payee: pix.payee,
    },
    dropped: null,
  }
}

function resolveCode(input: CaptureBillInput, today: LocalDate): Resolution {
  if (input.pixKey) {
    return {
      resolved: { ...EMPTY, kind: 'PIX_KEY', code: input.pixKey },
      dropped: null,
    }
  }
  const primary = input.paymentCode ?? input.pixCode
  if (!primary) {
    return {
      resolved: { ...EMPTY, kind: 'DARF_NO_BARCODE', code: null },
      dropped: null,
    }
  }
  const resolved = decodeCode(primary, today)
  if (!input.paymentCode || !input.pixCode) {
    return { resolved, dropped: null }
  }
  if (resolved.kind !== 'PIX_QR') {
    return withPixCode(resolved, input.pixCode, today)
  }
  if (validBrCode(input.pixCode) !== resolved.pixCode) {
    throw new ValidationError('pixCode must be a Pix code next to a barcode.')
  }
  return { resolved, dropped: null }
}

// A dynamic code whose charge asks for another amount than the barcode would
// pay the wrong value by Pix, so the barcode wins. Read on every dynamic code.
function checkCharge(
  resolution: Resolution,
  charge: PixCharge | null,
): Resolution {
  const { resolved } = resolution
  const barcodeAmount = resolved.kind === 'PIX_QR' ? null : resolved.amount
  if (
    !barcodeAmount ||
    !charge?.amount ||
    barcodeAmount.equals(charge.amount)
  ) {
    return resolution
  }
  return {
    resolved: { ...resolved, pixCode: null, location: null },
    dropped: 'CHARGE_AMOUNT_MISMATCH',
  }
}

function clientAmount(input: CaptureBillInput): Money | null {
  return input.amountCents ? Money.of(input.amountCents) : null
}

export function makeCaptureBill(deps: CaptureBillDeps) {
  const buildPlan = makeBuildPaymentPlan(deps)

  async function chargeFor(resolved: ResolvedCode): Promise<PixCharge | null> {
    if (!resolved.location || !deps.pixLocations) {
      return null
    }
    try {
      return await deps.pixLocations.resolve(resolved.location)
    } catch {
      return null
    }
  }

  async function findExact(
    tenantId: string,
    entityId: string,
    incoming: IncomingBill,
  ): Promise<Bill | null> {
    const byCode = incoming.code
      ? await deps.bills.findByCode(tenantId, entityId, incoming.code)
      : null
    if (byCode || !incoming.pixCode) {
      return byCode
    }
    return deps.bills.findByPixCode(tenantId, entityId, incoming.pixCode)
  }

  async function findPair(
    tenantId: string,
    entityId: string,
    incoming: IncomingBill,
  ): Promise<Bill | null> {
    if (!incoming.amount) {
      return null
    }
    const candidates = await deps.bills.listUnsettledByAmount(
      tenantId,
      entityId,
      incoming.amount,
    )
    return (
      candidates.find(stored => sameLocation(stored, incoming)) ??
      candidates.find(stored => completesHalf(stored, incoming)) ??
      null
    )
  }

  async function audit(
    tenantId: string,
    bill: Bill,
    action: string,
    result: string,
  ): Promise<void> {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'SYSTEM',
      action,
      subjectId: bill.id,
      rail: null,
      result,
      details: { kind: bill.kind, source: bill.source },
      at: deps.clock.now(),
    })
  }

  // A bill that has started paying keeps its codes; the capture is a duplicate.
  async function merge(
    tenantId: string,
    stored: Bill,
    incoming: IncomingBill,
  ): Promise<CaptureBillResult> {
    const merged = withMissingHalf(stored, incoming)
    if (!merged || stored.status !== 'OPEN') {
      return { bill: stored, duplicate: true }
    }
    const attempts = await deps.payments.listAttempts(tenantId, stored.id)
    if (attempts.length > 0) {
      return { bill: stored, duplicate: true }
    }
    await deps.bills.save(merged)
    await buildPlan(tenantId, merged)
    await audit(tenantId, merged, 'bill.codes_merged', merged.kind)
    return { bill: merged, duplicate: true }
  }

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
    const decoded = resolveCode(input, today)
    const charge = await chargeFor(decoded.resolved)
    const { resolved, dropped } = checkCharge(decoded, charge)
    const incoming: IncomingBill = {
      ...resolved,
      amount: resolved.amount ?? charge?.amount ?? clientAmount(input),
      dueDate: resolved.dueDate ?? charge?.dueDate ?? input.dueDate ?? null,
      payee: input.payee ?? charge?.payee ?? resolved.payee,
    }
    const existing =
      (await findExact(tenantId, entity.id, incoming)) ??
      (await findPair(tenantId, entity.id, incoming))
    if (existing) {
      return merge(tenantId, existing, incoming)
    }
    if (!incoming.amount) {
      throw new AmountRequiredError({
        field: 'amountCents',
        kind: incoming.kind,
        payee: incoming.payee,
      })
    }
    const bill = createBill({
      id: deps.ids.next(),
      tenantId,
      entityId: entity.id,
      kind: incoming.kind,
      source: input.source,
      payee: incoming.payee,
      amount: incoming.amount,
      dueDate: incoming.dueDate ?? today,
      code: incoming.code,
      pixCode: incoming.pixCode,
      createdAt: now,
    })
    await deps.bills.save(bill)
    await buildPlan(tenantId, bill)
    if (dropped) {
      await audit(tenantId, bill, 'bill.pix_code_dropped', dropped)
    }
    await emitAlert(deps.alerts, billAlert('BILL_CAPTURED', bill))
    return { bill, duplicate: false }
  }
}
