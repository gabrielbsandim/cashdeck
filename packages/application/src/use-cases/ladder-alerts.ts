import { type AlertType, type BillStatus } from '@cashdeck/domain'
import { type AlertEmitter, type AlertInput } from '@/ports/alerts'
import { assistedAlert, billAlert, RAIL_NAMES } from '@/use-cases/alert-events'
import {
  type LadderOptions,
  type LadderRun,
} from '@/use-cases/run-payment-ladder'

type RunLadder = (
  tenantId: string,
  billId: string,
  options?: LadderOptions,
) => Promise<LadderRun>

const OUTCOME_ALERTS: Partial<
  Record<BillStatus, Exclude<AlertType, 'PAYMENT_ASSISTED'>>
> = {
  NEEDS_CONFIRMATION: 'PAYMENT_NEEDS_CONFIRMATION',
  PAID: 'PAYMENT_PAID',
  AWAITING_BANK_APPROVAL: 'APPROVAL_PENDING',
}

// What a finished run tells the user. A run that did nothing (already paid,
// still waiting on a rail) tells nothing.
export function ladderAlerts(run: LadderRun): AlertInput[] {
  const { bill, attempts } = run
  if (attempts.length === 0 && bill.status !== 'NEEDS_CONFIRMATION') {
    return []
  }
  const failure = attempts.find(attempt => attempt.outcome === 'FAILED')
  if (bill.status === 'ASSISTED') {
    return [assistedAlert(bill, failure?.reason ?? null)]
  }
  const alerts: AlertInput[] = []
  if (failure) {
    alerts.push(
      billAlert(
        'PAYMENT_MOVED_DOWN',
        bill,
        { rail: RAIL_NAMES[failure.rail], reason: failure.reason ?? '' },
        `PAYMENT_MOVED_DOWN:${bill.id}:${failure.id}`,
      ),
    )
  }
  const type = OUTCOME_ALERTS[bill.status]
  if (type) {
    alerts.push(billAlert(type, bill))
  }
  return alerts
}

// Wraps the ladder so its internals stay untouched by alerting.
export function withLadderAlerts(
  runLadder: RunLadder,
  alerts: AlertEmitter,
): RunLadder {
  return async (tenantId, billId, options) => {
    const run = await runLadder(tenantId, billId, options)
    for (const alert of ladderAlerts(run)) {
      await alerts.emit(alert)
    }
    return run
  }
}
