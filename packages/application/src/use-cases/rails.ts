import {
  type EntityKind,
  type FinancialEntity,
  RAIL_IDS,
  type RailId,
  ValidationError,
} from '@cashdeck/domain'
import { type z } from 'zod'
import {
  RAIL_KINDS,
  type RailCredentialsView,
  type RailKind,
  type RailViewStatus,
  type RailView,
  type saveRailCredentialsSchema,
} from '@/dtos/rails'
import { type Upload } from '@/dtos/common'
import { NotFoundError } from '@/errors/errors'
import { credentialName, putCredential } from '@/use-cases/credentials'
import { type Deps } from '@/use-cases/deps'
import {
  decodeUpload,
  required,
  requireEntity,
  today,
} from '@/use-cases/shared'

type CatalogEntry = {
  railId: RailId | null
  kind: RailKind
  step: 1 | 2 | 3
  institution: string
}

const entry = (
  railId: RailId | null,
  kind: RailKind,
  step: 1 | 2 | 3,
  institution: string,
): CatalogEntry => ({ railId, kind, step, institution })

// The default ladder of each entity, as docs/plan.md section 5 routes it.
const CATALOG: Record<EntityKind, readonly CatalogEntry[]> = {
  PF: [
    entry('MERCADO_PAGO_PAYOUTS', 'PIX_API', 1, 'Mercado Pago'),
    entry('ASAAS', 'PIX_API', 1, 'Asaas'),
    entry('ASAAS', 'BOLETO_API', 1, 'Asaas'),
    entry('ASAAS', 'RESERVE_FUNDING', 1, 'Asaas'),
    entry(null, 'BANK_APPROVAL', 2, ''),
    entry('ASSISTED', 'ASSISTED', 3, ''),
  ],
  PJ: [
    entry('INTER_EMPRESAS', 'PIX_API', 1, 'Inter Empresas'),
    entry('INTER_EMPRESAS', 'BOLETO_API', 1, 'Inter Empresas'),
    entry('INTER_EMPRESAS', 'TAX_API', 1, 'Inter Empresas'),
    entry('C6_EMPRESAS', 'BANK_APPROVAL', 2, 'C6 Empresas'),
    entry('ASSISTED', 'ASSISTED', 3, ''),
  ],
}

export type RailCredentialsMeta = {
  certificateName: string | null
  certificateValidUntil: string | null
  certificateFingerprint: string | null
  apiKeyHint: string | null
  hasClientCredentials: boolean
  lastTestAt: string | null
}

export type RailSecret = z.infer<typeof saveRailCredentialsSchema>

type CredentialField = keyof Omit<RailSecret, 'certificateValidUntil'>

// The credential names each adapter reads, per field of the upload form.
export const RAIL_CREDENTIAL_NAMES: Partial<
  Record<RailId, Partial<Record<CredentialField, string>>>
> = {
  MERCADO_PAGO_PAYOUTS: {
    apiKey: 'MERCADO_PAGO_ACCESS_TOKEN',
    privateKey: 'MERCADO_PAGO_SIGNING_KEY',
  },
  ASAAS: { apiKey: 'ASAAS_API_KEY' },
  INTER_EMPRESAS: {
    clientId: 'INTER_CLIENT_ID',
    clientSecret: 'INTER_CLIENT_SECRET',
    certificate: 'INTER_CERT',
    privateKey: 'INTER_KEY',
  },
  C6_EMPRESAS: {
    clientId: 'C6_CLIENT_ID',
    clientSecret: 'C6_CLIENT_SECRET',
    certificate: 'C6_CERT',
    privateKey: 'C6_KEY',
  },
}

export const RAIL_CREDENTIALS_COLLECTION = 'rail-credentials'

const railIdText = (railId: RailId | null) => railId ?? 'NONE'

function railViewId(owner: EntityKind, item: CatalogEntry): string {
  return `${owner}.${railIdText(item.railId)}.${item.kind}`
}

type CredentialMap = Partial<Record<CredentialField, string>>

function credentialFieldsOf(
  item: CatalogEntry | undefined,
): CredentialMap | null {
  if (!item?.railId || item.kind === 'RESERVE_FUNDING') {
    return null
  }
  return RAIL_CREDENTIAL_NAMES[item.railId] ?? null
}

const isConfigurable = (item: CatalogEntry) => credentialFieldsOf(item) !== null

// Each catalog rail has one owner, so the tenant-wide name, which `check()`
// reads, is safe to write too.
const secretNames = (entityId: string, credential: string) => [
  credentialName(credential, entityId),
  credential,
]

const pemOf = (upload: Upload) =>
  new TextDecoder().decode(decodeUpload(upload.base64))

function credentialValues(names: CredentialMap, input: RailSecret) {
  const fields = Object.entries(input).filter(
    ([field, value]) =>
      field !== 'certificateValidUntil' && value !== undefined,
  ) as Array<[CredentialField, string | Upload]>
  return fields.map(([field, value]) => {
    const name = names[field]
    if (!name) {
      throw new ValidationError(`This rail does not use ${field}.`)
    }
    return { name, value: typeof value === 'string' ? value : pemOf(value) }
  })
}

type RailRef = {
  entity: FinancialEntity
  item: CatalogEntry
  railId: RailId
  fields: CredentialMap
}

type RailDeps = Pick<
  Deps,
  | 'entities'
  | 'accounts'
  | 'documents'
  | 'secrets'
  | 'vault'
  | 'settings'
  | 'certificates'
  | 'rails'
  | 'clock'
>

export function makeRails(deps: RailDeps) {
  async function meta(tenantId: string, entityId: string, railId: RailId) {
    return deps.documents.get<RailCredentialsMeta>(
      tenantId,
      RAIL_CREDENTIALS_COLLECTION,
      `${entityId}:${railId}`,
    )
  }

  async function statusOf(
    tenantId: string,
    entity: FinancialEntity,
    item: CatalogEntry,
  ): Promise<RailViewStatus> {
    if (item.railId === 'ASSISTED') {
      return 'ALWAYS'
    }
    if (item.railId === null) {
      return 'UNAVAILABLE'
    }
    const [stored, settings] = await Promise.all([
      meta(tenantId, entity.id, item.railId),
      deps.settings.get(tenantId, entity.id),
    ])
    const ready = stored !== null && settings.enabledRails.includes(item.railId)
    if (item.kind !== 'RESERVE_FUNDING') {
      return ready ? 'ACTIVE' : 'NEEDS_AUTHORIZATION'
    }
    const payout = 'MERCADO_PAGO_PAYOUTS'
    const payer = await meta(tenantId, entity.id, payout)
    const accounts = await deps.accounts.listByEntity(tenantId, entity.id)
    const funded =
      ready &&
      payer !== null &&
      settings.enabledRails.includes(payout) &&
      accounts.some(account => account.isReserve)
    return funded ? 'ACTIVE' : 'NEEDS_AUTHORIZATION'
  }

  async function view(
    tenantId: string,
    entity: FinancialEntity,
    item: CatalogEntry,
  ): Promise<RailView> {
    return {
      id: railViewId(entity.kind, item),
      railId: item.railId,
      kind: item.kind,
      owner: entity.kind,
      step: item.step,
      institution: item.institution,
      status: await statusOf(tenantId, entity, item),
      configurable: isConfigurable(item),
    }
  }

  async function resolve(tenantId: string, id: string): Promise<RailRef> {
    const [owner, railId, kind] = id.split('.')
    const known =
      (owner === 'PF' || owner === 'PJ') &&
      RAIL_KINDS.includes(kind as RailKind) &&
      [...RAIL_IDS, 'NONE'].includes(railId as RailId)
    const item = known
      ? CATALOG[owner as EntityKind].find(
          candidate =>
            railIdText(candidate.railId) === railId && candidate.kind === kind,
        )
      : undefined
    const fields = credentialFieldsOf(item)
    if (!item?.railId || !fields) {
      throw new NotFoundError('Rail')
    }
    const entity = await requireEntity(
      deps.entities,
      tenantId,
      owner as EntityKind,
    )
    return { entity, item, railId: item.railId, fields }
  }

  async function list(tenantId: string, kind: EntityKind): Promise<RailView[]> {
    const entity = await requireEntity(deps.entities, tenantId, kind)
    const views: RailView[] = []
    for (const item of CATALOG[kind]) {
      views.push(await view(tenantId, entity, item))
    }
    return views
  }

  async function setEnabled(
    tenantId: string,
    ref: RailRef,
    enabled: boolean,
  ): Promise<void> {
    const settings = await deps.settings.get(tenantId, ref.entity.id)
    const others = settings.enabledRails.filter(rail => rail !== ref.railId)
    await deps.settings.save(tenantId, ref.entity.id, {
      ...settings,
      enabledRails: enabled ? [...others, ref.railId] : others,
    })
  }

  async function authorize(tenantId: string, id: string): Promise<RailView> {
    const ref = await resolve(tenantId, id)
    if (!(await meta(tenantId, ref.entity.id, ref.railId))) {
      throw new ValidationError('Upload the rail credentials first.')
    }
    await setEnabled(tenantId, ref, true)
    return view(tenantId, ref.entity, ref.item)
  }

  async function credentials(
    tenantId: string,
    id: string,
  ): Promise<RailCredentialsView> {
    const ref = await resolve(tenantId, id)
    const stored = required(
      await meta(tenantId, ref.entity.id, ref.railId),
      'Rail credentials',
    )
    return {
      certificateName: stored.certificateName,
      certificateValidUntil: stored.certificateValidUntil,
      apiKeyHint: stored.apiKeyHint,
      lastTestAt: stored.lastTestAt,
    }
  }

  function certificateFacts(input: RailSecret) {
    if (!input.certificate) {
      return null
    }
    const facts = deps.certificates.inspect({
      fileName: input.certificate.fileName,
      bytes: decodeUpload(input.certificate.base64),
    })
    const validUntil = facts.validUntil ?? input.certificateValidUntil ?? null
    if (validUntil === null) {
      throw new ValidationError('Send certificateValidUntil for this file.')
    }
    return { ...facts, validUntil, fileName: input.certificate.fileName }
  }

  async function saveCredentials(
    tenantId: string,
    id: string,
    input: RailSecret,
  ): Promise<RailCredentialsView> {
    const ref = await resolve(tenantId, id)
    const values = credentialValues(ref.fields, input)
    const facts = certificateFacts(input)
    for (const { name, value } of values) {
      for (const secret of secretNames(ref.entity.id, name)) {
        await putCredential(deps, tenantId, secret, value)
      }
    }
    const previous = await meta(tenantId, ref.entity.id, ref.railId)
    const next: RailCredentialsMeta = {
      certificateName: facts?.fileName ?? previous?.certificateName ?? null,
      certificateValidUntil:
        facts?.validUntil ?? previous?.certificateValidUntil ?? null,
      certificateFingerprint:
        facts?.fingerprint ?? previous?.certificateFingerprint ?? null,
      apiKeyHint: input.apiKey?.slice(-4) ?? previous?.apiKeyHint ?? null,
      hasClientCredentials:
        Boolean(input.clientId && input.clientSecret) ||
        (previous?.hasClientCredentials ?? false),
      lastTestAt: previous?.lastTestAt ?? null,
    }
    await deps.documents.put(
      tenantId,
      RAIL_CREDENTIALS_COLLECTION,
      `${ref.entity.id}:${ref.railId}`,
      next,
    )
    return credentials(tenantId, id)
  }

  async function test(tenantId: string, id: string) {
    const ref = await resolve(tenantId, id)
    const stored = required(
      await meta(tenantId, ref.entity.id, ref.railId),
      'Rail credentials',
    )
    const day = today(deps.clock.now())
    const rail = deps.rails.get(ref.railId)
    const started = deps.clock.now().getTime()
    const check = rail ? await rail.check() : { ok: false, message: null }
    const millis = deps.clock.now().getTime() - started
    const testedAt = deps.clock.now().toISOString()
    await deps.documents.put(
      tenantId,
      RAIL_CREDENTIALS_COLLECTION,
      `${ref.entity.id}:${ref.railId}`,
      { ...stored, lastTestAt: testedAt },
    )
    const certificateValid =
      stored.certificateName !== null &&
      (stored.certificateValidUntil ?? day) >= day
    return {
      checks: [
        {
          kind: 'CERTIFICATE' as const,
          passed: certificateValid,
          millis: null,
        },
        {
          kind: 'API_KEY' as const,
          passed: stored.apiKeyHint !== null || stored.hasClientCredentials,
          millis: null,
        },
        { kind: 'SCOPE' as const, passed: check.ok, millis },
        { kind: 'PAYER_ACCOUNT' as const, passed: check.ok, millis: null },
      ],
      testedAt,
    }
  }

  async function remove(tenantId: string, id: string) {
    const ref = await resolve(tenantId, id)
    for (const name of Object.values(ref.fields)) {
      for (const secret of secretNames(ref.entity.id, name)) {
        await deps.secrets.delete(tenantId, secret)
      }
    }
    await deps.documents.delete(
      tenantId,
      RAIL_CREDENTIALS_COLLECTION,
      `${ref.entity.id}:${ref.railId}`,
    )
    await setEnabled(tenantId, ref, false)
    return { id }
  }

  return { list, authorize, credentials, saveCredentials, test, remove }
}
