import {
  type Bill,
  type FundingStatus,
  fundingFor,
  fundingKey,
  fundingShortfall,
  isFunded,
  Money,
  type ReserveFunding,
  toLocalDate,
} from '@cashdeck/domain'
import { type FundingResult, type ReserveFunder } from '@/ports/reserve-funder'
import {
  type Actor,
  type AuditLog,
  type FundingRepository,
  SYSTEM_ACTOR,
} from '@/ports/repositories'
import { type Clock, type IdGenerator } from '@/ports/system'
import { failureReason } from '@/use-cases/payment-guards'

export type ReserveFundingDeps = {
  fundings: FundingRepository
  funder: ReserveFunder
  audit: AuditLog
  clock: Clock
  ids: IdGenerator
}

export type FundingSummary = { rounds: number; fundedCents: number }

export const RESERVE_FUNDING_FAILED = 'RESERVE_FUNDING_FAILED'

type Balance = { cents: number } | { reason: string }

function roundStatus(available: Balance, shortfall: number): FundingStatus {
  if ('reason' in available) {
    return 'FAILED'
  }
  return shortfall === 0 ? 'NOT_NEEDED' : 'IN_FLIGHT'
}

const sum = (bills: readonly Bill[]) =>
  bills.reduce((total, bill) => total + bill.amount.cents, 0)

// Moves the reserve into the paying account before it pays: one round per
// entity sized to the shortfall of the bills it names, never a second time.
export function makeReserveFunding(deps: ReserveFundingDeps) {
  async function audit(round: ReserveFunding, actor: Actor): Promise<void> {
    await deps.audit.record({
      id: deps.ids.next(),
      tenantId: round.tenantId,
      actor: actor.kind,
      actorId: actor.id,
      requestId: actor.requestId,
      action: 'reserve.funding',
      subjectId: round.id,
      rail: 'MERCADO_PAGO_PAYOUTS',
      result: round.status,
      details: {
        day: round.day,
        round: round.round,
        billIds: round.billIds,
        billsTotalCents: round.billsTotal.cents,
        availableCents: round.available?.cents ?? null,
        amountCents: round.amount.cents,
        idempotencyKey: round.idempotencyKey,
        externalId: round.externalId,
        reason: round.reason,
      },
      at: round.at,
    })
  }

  async function send(round: ReserveFunding): Promise<FundingResult> {
    try {
      return await deps.funder.fund({
        tenantId: round.tenantId,
        entityId: round.entityId,
        amountCents: round.amount.cents,
        idempotencyKey: round.idempotencyKey,
        description: `Cashdeck bills ${round.day}`,
      })
    } catch (error) {
      return {
        outcome: 'FAILED',
        externalId: null,
        reason: failureReason(error),
      }
    }
  }

  // An in-flight round is sent again with the same key, which the payout API
  // answers with the first transfer instead of making a second one.
  async function submit(
    round: ReserveFunding,
    actor: Actor,
  ): Promise<ReserveFunding> {
    const result = await send(round)
    const next: ReserveFunding = {
      ...round,
      status: result.outcome,
      externalId: result.externalId,
      reason: result.reason,
      at: deps.clock.now(),
    }
    await deps.fundings.update(next)
    await audit(next, actor)
    return next
  }

  async function balance(tenantId: string, entityId: string): Promise<Balance> {
    try {
      return { cents: await deps.funder.availableCents({ tenantId, entityId }) }
    } catch (error) {
      return { reason: failureReason(error) }
    }
  }

  async function openRound(
    tenantId: string,
    entityId: string,
    bills: readonly Bill[],
    rounds: readonly ReserveFunding[],
    actor: Actor,
  ): Promise<ReserveFunding> {
    const day = toLocalDate(deps.clock.now())
    const number = Math.max(0, ...rounds.map(round => round.round)) + 1
    const total = sum(bills)
    const available = await balance(tenantId, entityId)
    const shortfall =
      'cents' in available ? fundingShortfall(total, available.cents) : 0
    const status = roundStatus(available, shortfall)
    const round: ReserveFunding = {
      id: deps.ids.next(),
      tenantId,
      entityId,
      day,
      round: number,
      billIds: bills.map(bill => bill.id),
      billsTotal: Money.of(total),
      available: 'cents' in available ? Money.of(available.cents) : null,
      amount: Money.of(shortfall),
      status,
      reason: 'reason' in available ? available.reason : null,
      externalId: null,
      idempotencyKey: fundingKey(entityId, day, number),
      at: deps.clock.now(),
    }
    await deps.fundings.create(round)
    if (status !== 'IN_FLIGHT') {
      await audit(round, actor)
      return round
    }
    return submit(round, actor)
  }

  async function fundEntity(
    tenantId: string,
    entityId: string,
    bills: readonly Bill[],
    actor: Actor,
  ): Promise<ReserveFunding[]> {
    const day = toLocalDate(deps.clock.now())
    const rounds = await deps.fundings.listByDay(tenantId, entityId, day)
    const touched: ReserveFunding[] = []
    for (const stuck of rounds.filter(round => round.status === 'IN_FLIGHT')) {
      touched.push(await submit(stuck, actor))
    }
    const fresh = bills.filter(bill => fundingFor(rounds, bill.id) === null)
    if (fresh.length > 0) {
      touched.push(await openRound(tenantId, entityId, fresh, rounds, actor))
    }
    return touched
  }

  async function fundDue(
    tenantId: string,
    bills: readonly Bill[],
    actor: Actor = SYSTEM_ACTOR,
  ): Promise<FundingSummary> {
    const entityIds = [...new Set(bills.map(bill => bill.entityId))]
    const summary: FundingSummary = { rounds: 0, fundedCents: 0 }
    for (const entityId of entityIds) {
      const own = bills.filter(bill => bill.entityId === entityId)
      for (const round of await fundEntity(tenantId, entityId, own, actor)) {
        summary.rounds += 1
        summary.fundedCents += isFunded(round.status) ? round.amount.cents : 0
      }
    }
    return summary
  }

  // The ladder asks right before the paying rail: a bill no round named yet
  // gets a round of its own, so a bill confirmed later in the day is covered.
  async function ensureFunded(
    tenantId: string,
    bill: Bill,
    actor: Actor,
  ): Promise<string | null> {
    try {
      const day = toLocalDate(deps.clock.now())
      const rounds = await deps.fundings.listByDay(tenantId, bill.entityId, day)
      const found = fundingFor(rounds, bill.id)
      const round =
        found ??
        (await openRound(tenantId, bill.entityId, [bill], rounds, actor))
      const settled =
        round.status === 'IN_FLIGHT' ? await submit(round, actor) : round
      return isFunded(settled.status) ? null : RESERVE_FUNDING_FAILED
    } catch {
      return RESERVE_FUNDING_FAILED
    }
  }

  return { fundDue, ensureFunded }
}
