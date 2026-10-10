import { type EntityKind, type FinancialEntity } from '@cashdeck/domain'
import { type CaptureSourcesView } from '@/dtos/capture'
import { AmountRequiredError, NotConfiguredSource } from '@/errors/errors'
import { type CapturedBill } from '@/ports/providers'
import { amountRequiredAlert, emitAlert } from '@/use-cases/alert-events'
import { type Deps } from '@/use-cases/deps'
import { makeCaptureBill } from '@/use-cases/capture-bill'
import { credentialName, putCredential } from '@/use-cases/credentials'
import { required, requireEntity, requireEntityById } from '@/use-cases/shared'

export type Mailbox = {
  id: string
  entityId: string
  address: string
  provider: string
  lastReadAt: string | null
  billsFound: number
  emailsScanned: number
}

export type DdaEnrollment = {
  entityId: string
  bank: string
  lastBatchAt: string | null
  boletos: number
  enabled: boolean
}

export const MAILBOX_COLLECTION = 'mailboxes'
export const DDA_COLLECTION = 'dda'
const FIRST_READ_DAYS = 30
const DAY_MS = 86_400_000

const DDA_BANKS: Record<EntityKind, string> = {
  PF: 'Polp Super DDA',
  PJ: 'C6 Empresas',
}

// The Gmail adapter reads one refresh token per entity.
export function mailboxSecretName(entityId: string): string {
  return credentialName('GMAIL_REFRESH_TOKEN', entityId)
}

type CaptureDeps = Pick<
  Deps,
  | 'entities'
  | 'documents'
  | 'secrets'
  | 'vault'
  | 'billSources'
  | 'mailboxAuthorizer'
  | 'bills'
  | 'audit'
  | 'pixLocations'
  | 'payments'
  | 'settings'
  | 'rails'
  | 'clock'
  | 'ids'
> &
  Partial<Pick<Deps, 'alerts'>>

export function makeCaptureSources(deps: CaptureDeps) {
  const capture = makeCaptureBill(deps)

  async function sources(tenantId: string): Promise<CaptureSourcesView> {
    const entities = await deps.entities.list(tenantId)
    const kinds = new Map(entities.map(entity => [entity.id, entity.kind]))
    const mailboxes = await deps.documents.list<Mailbox>(
      tenantId,
      MAILBOX_COLLECTION,
    )
    const stored = await deps.documents.list<DdaEnrollment>(
      tenantId,
      DDA_COLLECTION,
    )
    const company = entities.find(entity => entity.kind === 'PJ')
    const hasCompanyEntry = stored.some(row => row.entityId === company?.id)
    const dda =
      company && !hasCompanyEntry ? [...stored, enrollment(company)] : stored
    return {
      mailboxes: mailboxes.map(mailbox => ({
        id: mailbox.id,
        address: mailbox.address,
        owner: kinds.get(mailbox.entityId) ?? 'PF',
        lastReadAt: mailbox.lastReadAt,
        billsFound: mailbox.billsFound,
        emailsScanned: mailbox.emailsScanned,
      })),
      dda: dda.map(row => ({
        owner: kinds.get(row.entityId) ?? 'PJ',
        bank: row.bank,
        lastBatchAt: row.lastBatchAt,
        boletos: row.boletos,
        enabled: row.enabled,
      })),
    }
  }

  function enrollment(entity: FinancialEntity): DdaEnrollment {
    return {
      entityId: entity.id,
      bank: DDA_BANKS[entity.kind],
      lastBatchAt: null,
      boletos: 0,
      enabled: false,
    }
  }

  async function startMailbox(
    tenantId: string,
    kind: EntityKind,
    state: string,
  ) {
    await requireEntity(deps.entities, tenantId, kind)
    return { url: deps.mailboxAuthorizer.authorizationUrl(state) }
  }

  async function completeMailbox(
    tenantId: string,
    kind: EntityKind,
    code: string,
  ): Promise<Mailbox> {
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const authorized = await deps.mailboxAuthorizer.exchange(code)
    const all = await deps.documents.list<Mailbox>(tenantId, MAILBOX_COLLECTION)
    const owned = all.filter(mailbox => mailbox.entityId === entity.id)
    const existing = owned.find(
      mailbox => mailbox.address === authorized.address,
    )
    for (const replaced of owned.filter(mailbox => mailbox !== existing)) {
      await deps.documents.delete(tenantId, MAILBOX_COLLECTION, replaced.id)
    }
    const mailbox: Mailbox = existing ?? {
      id: deps.ids.next(),
      entityId: entity.id,
      address: authorized.address,
      provider: deps.mailboxAuthorizer.provider,
      lastReadAt: null,
      billsFound: 0,
      emailsScanned: 0,
    }
    await putCredential(
      deps,
      tenantId,
      mailboxSecretName(entity.id),
      authorized.refreshToken,
    )
    await deps.documents.put(tenantId, MAILBOX_COLLECTION, mailbox.id, mailbox)
    return mailbox
  }

  async function captureAllFrom(
    tenantId: string,
    entityId: string,
    sourceName: 'GMAIL' | 'DDA',
    since: Date,
  ): Promise<{ fetched: number; created: number }> {
    const source = deps.billSources.get(sourceName)
    if (!source) {
      throw new NotConfiguredSource(sourceName)
    }
    const entity = await requireEntityById(deps.entities, tenantId, entityId)
    const fetched = await source.fetch(tenantId, entityId, since, {
      taxId: entity.taxId.value,
    })
    let created = 0
    for (const found of fetched) {
      created += (await captureOne(tenantId, entityId, sourceName, found))
        ? 1
        : 0
    }
    return { fetched: fetched.length, created }
  }

  // A bill the reader could not decode is skipped; the rest still land.
  async function captureOne(
    tenantId: string,
    entityId: string,
    source: 'GMAIL' | 'DDA',
    found: CapturedBill,
  ): Promise<boolean> {
    if (!found.paymentCode && !found.pixCode) {
      return false
    }
    try {
      const result = await capture(tenantId, {
        entityId,
        source,
        paymentCode: found.paymentCode ?? undefined,
        pixCode: found.pixCode ?? undefined,
        amountCents: found.amountCents ?? undefined,
        dueDate: found.dueDate ?? undefined,
        payee: found.payee ?? undefined,
      })
      return !result.duplicate
    } catch (error) {
      const skipped = error instanceof AmountRequiredError
      await emitAlert(
        deps.alerts,
        skipped ? amountRequiredAlert(tenantId, entityId, source, found) : null,
      )
      return false
    }
  }

  function sinceOf(last: string | null): Date {
    const now = deps.clock.now().getTime()
    return last ? new Date(last) : new Date(now - FIRST_READ_DAYS * DAY_MS)
  }

  // The read starts its window at the run start, so mail that lands mid-run is
  // picked up by the next one instead of falling between the two.
  async function readOne(tenantId: string, mailbox: Mailbox) {
    const startedAt = deps.clock.now().toISOString()
    const result = await captureAllFrom(
      tenantId,
      mailbox.entityId,
      'GMAIL',
      sinceOf(mailbox.lastReadAt),
    )
    await deps.documents.put(tenantId, MAILBOX_COLLECTION, mailbox.id, {
      ...mailbox,
      lastReadAt: startedAt,
      billsFound: mailbox.billsFound + result.created,
      emailsScanned: mailbox.emailsScanned + result.fetched,
    })
    return result.created
  }

  async function readMailbox(tenantId: string, mailboxId: string) {
    const mailbox = required(
      await deps.documents.get<Mailbox>(
        tenantId,
        MAILBOX_COLLECTION,
        mailboxId,
      ),
      'Mailbox',
    )
    await readOne(tenantId, mailbox)
    return sources(tenantId)
  }

  async function disconnect(tenantId: string, mailboxId: string) {
    const mailbox = required(
      await deps.documents.get<Mailbox>(
        tenantId,
        MAILBOX_COLLECTION,
        mailboxId,
      ),
      'Mailbox',
    )
    await deps.secrets.delete(tenantId, mailboxSecretName(mailbox.entityId))
    await deps.documents.delete(tenantId, MAILBOX_COLLECTION, mailboxId)
    return sources(tenantId)
  }

  async function setDda(tenantId: string, kind: EntityKind, enabled: boolean) {
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const current =
      (await deps.documents.get<DdaEnrollment>(
        tenantId,
        DDA_COLLECTION,
        entity.id,
      )) ?? enrollment(entity)
    await deps.documents.put(tenantId, DDA_COLLECTION, entity.id, {
      ...current,
      enabled,
    })
    return sources(tenantId)
  }

  async function readDda(tenantId: string, row: DdaEnrollment) {
    const startedAt = deps.clock.now().toISOString()
    const result = await captureAllFrom(
      tenantId,
      row.entityId,
      'DDA',
      sinceOf(row.lastBatchAt),
    )
    await deps.documents.put(tenantId, DDA_COLLECTION, row.entityId, {
      ...row,
      lastBatchAt: startedAt,
      boletos: row.boletos + result.created,
    })
    return result.created
  }

  async function captureAll(tenantId: string) {
    const failures: Array<{ source: string; reason: string }> = []
    let created = 0
    const mailboxes = await deps.documents.list<Mailbox>(
      tenantId,
      MAILBOX_COLLECTION,
    )
    for (const mailbox of mailboxes) {
      try {
        created += await readOne(tenantId, mailbox)
      } catch (error) {
        failures.push({ source: mailbox.id, reason: String(error) })
      }
    }
    const dda = await deps.documents.list<DdaEnrollment>(
      tenantId,
      DDA_COLLECTION,
    )
    for (const row of dda.filter(candidate => candidate.enabled)) {
      try {
        created += await readDda(tenantId, row)
      } catch (error) {
        failures.push({ source: `dda:${row.entityId}`, reason: String(error) })
      }
    }
    return { created, failures }
  }

  return {
    sources,
    startMailbox,
    completeMailbox,
    readMailbox,
    disconnect,
    setDda,
    captureAll,
  }
}
