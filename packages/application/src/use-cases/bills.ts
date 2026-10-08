import { type Bill, type EntityKind, markBillPaid } from '@cashdeck/domain'
import {
  type BillDetailView,
  type BillView,
  toBillDetailView,
  toBillView,
} from '@/dtos/bill'
import { NotFoundError } from '@/errors/errors'
import {
  type AuditLog,
  type BillFilter,
  type BillRepository,
  type FinancialEntityRepository,
  type Page,
  type PageRequest,
  type PaymentRepository,
} from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'

async function entityKindOf(
  entities: FinancialEntityRepository,
  tenantId: string,
  entityId: string,
): Promise<EntityKind> {
  const entity = await entities.findById(tenantId, entityId)
  if (!entity) {
    throw new NotFoundError('Entity')
  }
  return entity.kind
}

export function makeDescribeBill(deps: {
  entities: FinancialEntityRepository
}) {
  return async function describeBill(
    tenantId: string,
    bill: Bill,
  ): Promise<BillView> {
    return toBillView(
      bill,
      await entityKindOf(deps.entities, tenantId, bill.entityId),
    )
  }
}

export function makeGetBill(deps: {
  bills: BillRepository
  payments: PaymentRepository
  entities: FinancialEntityRepository
}) {
  return async function getBill(
    tenantId: string,
    billId: string,
  ): Promise<BillDetailView> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    const [entityKind, plan, attempts] = await Promise.all([
      entityKindOf(deps.entities, tenantId, bill.entityId),
      deps.payments.findPlan(tenantId, billId),
      deps.payments.listAttempts(tenantId, billId),
    ])
    return toBillDetailView(bill, entityKind, plan, attempts)
  }
}

export function makeListBills(deps: {
  bills: BillRepository
  entities: FinancialEntityRepository
}) {
  return async function listBills(
    tenantId: string,
    filter: BillFilter,
    page: PageRequest,
  ): Promise<Page<BillView>> {
    const found = await deps.bills.list(tenantId, filter, page)
    const kinds = new Map<string, EntityKind>()
    const items: BillView[] = []
    for (const bill of found.items) {
      const kind =
        kinds.get(bill.entityId) ??
        (await entityKindOf(deps.entities, tenantId, bill.entityId))
      kinds.set(bill.entityId, kind)
      items.push(toBillView(bill, kind))
    }
    return { items, nextCursor: found.nextCursor }
  }
}

export function makeMarkBillPaid(deps: {
  bills: BillRepository
  audit: AuditLog
  clock: Clock
  ids: IdGenerator
}) {
  return async function markPaid(
    tenantId: string,
    billId: string,
    proof: string | null = null,
  ): Promise<Bill> {
    const bill = await deps.bills.findById(tenantId, billId)
    if (!bill) {
      throw new NotFoundError('Bill')
    }
    if (bill.status === 'PAID') {
      return bill
    }
    const at = deps.clock.now()
    const paid = markBillPaid(bill, 'USER', at)
    await deps.bills.save(paid)
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId,
      actor: 'USER',
      action: 'bill.marked_paid',
      subjectId: bill.id,
      rail: null,
      result: 'PAID',
      details: { proof },
      at,
    })
    return paid
  }
}
