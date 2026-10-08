import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { NotFoundError } from '@/errors/errors'
import { account, base64, fullDeps } from '@/testing/deps.test-helpers'
import { FakePaymentRail } from '@/testing/providers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { makeAutomation } from '@/use-cases/automation'
import { makeRails } from '@/use-cases/rails'

const pem = (name: string, text: string) => ({
  fileName: name,
  mimeType: 'application/x-pem-file',
  base64: base64(text),
})

function setup() {
  const deps = fullDeps({
    rails: [
      new FakePaymentRail('INTER_EMPRESAS'),
      new FakePaymentRail('ASAAS'),
    ],
    settings: { enabledRails: [] },
  })
  return { deps, rails: makeRails(deps) }
}

describe('rails', () => {
  it('lists each entity ladder with its status', async () => {
    const { rails } = setup()
    const pf = await rails.list(TENANT, 'PF')
    expect(pf.map(rail => [rail.id, rail.status, rail.configurable])).toEqual([
      ['PF.MERCADO_PAGO_PAYOUTS.PIX_API', 'NEEDS_AUTHORIZATION', true],
      ['PF.ASAAS.PIX_API', 'NEEDS_AUTHORIZATION', true],
      ['PF.ASAAS.BOLETO_API', 'NEEDS_AUTHORIZATION', true],
      ['PF.ASAAS.RESERVE_FUNDING', 'NEEDS_AUTHORIZATION', false],
      ['PF.NONE.BANK_APPROVAL', 'UNAVAILABLE', false],
      ['PF.ASSISTED.ASSISTED', 'ALWAYS', false],
    ])
    expect(pf[4]?.railId).toBeNull()
  })

  it('stores client credentials and the mTLS pair under adapter names', async () => {
    const { deps, rails } = setup()
    const id = 'PJ.INTER_EMPRESAS.PIX_API'
    await expect(rails.authorize(TENANT, id)).rejects.toThrow(ValidationError)
    const saved = await rails.saveCredentials(TENANT, id, {
      clientId: 'client',
      clientSecret: 'secret',
      certificate: pem('inter.crt', 'CERT PEM'),
      privateKey: pem('inter.key', 'KEY PEM'),
    })
    expect(saved).toEqual({
      certificateName: 'inter.crt',
      certificateValidUntil: '2027-03-02',
      apiKeyHint: null,
      lastTestAt: null,
    })
    expect(await deps.secrets.get(TENANT, 'INTER_CERT@pj')).toBe(
      'sealed:INTER_CERT@pj:CERT PEM',
    )
    expect(await deps.secrets.get(TENANT, 'INTER_KEY')).toBe(
      'sealed:INTER_KEY:KEY PEM',
    )
    const view = await rails.authorize(TENANT, id)
    expect(view.status).toBe('ACTIVE')
    const again = await rails.saveCredentials(TENANT, id, {
      clientSecret: 'rotated',
    })
    expect(again.certificateName).toBe('inter.crt')
    const test = await rails.test(TENANT, id)
    expect(test.checks.map(check => [check.kind, check.passed])).toEqual([
      ['CERTIFICATE', true],
      ['API_KEY', true],
      ['SCOPE', true],
      ['PAYER_ACCOUNT', true],
    ])
    expect((await rails.credentials(TENANT, id)).lastTestAt).toBe(test.testedAt)
    expect(await rails.remove(TENANT, id)).toEqual({ id })
    expect(await deps.secrets.get(TENANT, 'INTER_CLIENT_ID@pj')).toBeNull()
    expect(await deps.secrets.get(TENANT, 'INTER_CLIENT_ID')).toBeNull()
    await expect(rails.credentials(TENANT, id)).rejects.toThrow(NotFoundError)
  })

  it('stores an API key and hints the last digits', async () => {
    const { deps, rails } = setup()
    const saved = await rails.saveCredentials(TENANT, 'PF.ASAAS.PIX_API', {
      apiKey: 'key-1234',
    })
    expect(saved).toMatchObject({ apiKeyHint: '1234', certificateName: null })
    expect(await deps.secrets.get(TENANT, 'ASAAS_API_KEY@pf')).toBe(
      'sealed:ASAAS_API_KEY@pf:key-1234',
    )
    expect(await deps.secrets.get(TENANT, 'ASAAS_API_KEY')).toBe(
      'sealed:ASAAS_API_KEY:key-1234',
    )
    const test = await rails.test(TENANT, 'PF.ASAAS.PIX_API')
    expect(test.checks[0]).toMatchObject({ kind: 'CERTIFICATE', passed: false })
    expect(test.checks[1]).toMatchObject({ kind: 'API_KEY', passed: true })
  })

  it('funds the reserve only when the rail and a reserve account exist', async () => {
    const { deps, rails } = setup()
    await rails.saveCredentials(TENANT, 'PF.ASAAS.PIX_API', {
      apiKey: 'key-1234',
    })
    await rails.authorize(TENANT, 'PF.ASAAS.PIX_API')
    const statusOf = async () =>
      (await rails.list(TENANT, 'PF')).find(
        rail => rail.kind === 'RESERVE_FUNDING',
      )?.status
    expect(await statusOf()).toBe('NEEDS_AUTHORIZATION')
    await deps.accounts.save(
      account({ id: 'r', entityId: 'pf', isReserve: true }),
    )
    expect(await statusOf()).toBe('ACTIVE')
  })

  it('reads a test without a rail, or with a stale certificate, as failing', async () => {
    const { deps, rails } = setup()
    await rails.saveCredentials(TENANT, 'PJ.C6_EMPRESAS.BANK_APPROVAL', {
      certificate: pem('c6.pfx', 'binary'),
      certificateValidUntil: '2026-01-01',
    })
    const test = await rails.test(TENANT, 'PJ.C6_EMPRESAS.BANK_APPROVAL')
    expect(test.checks.map(check => check.passed)).toEqual([
      false,
      false,
      false,
      false,
    ])
    await deps.documents.put(TENANT, 'rail-credentials', 'pj:C6_EMPRESAS', {
      certificateName: 'c6.crt',
      certificateValidUntil: null,
      certificateFingerprint: null,
      apiKeyHint: null,
      hasClientCredentials: false,
      lastTestAt: null,
    })
    expect(
      (await rails.test(TENANT, 'PJ.C6_EMPRESAS.BANK_APPROVAL')).checks[0]
        ?.passed,
    ).toBe(true)
  })

  it('refuses unknown rails, unused fields and a certificate without expiry', async () => {
    const { rails } = setup()
    for (const id of [
      'XX.ASAAS.PIX_API',
      'PF.ASSISTED.ASSISTED',
      'PF.ASAAS.RESERVE_FUNDING',
      'PF.NONE.BANK_APPROVAL',
      'PF.FOO.PIX_API',
      'PF.ASAAS.FOO',
      'PJ.ASAAS.PIX_API',
    ]) {
      await expect(rails.test(TENANT, id)).rejects.toThrow(NotFoundError)
    }
    await expect(
      rails.saveCredentials(TENANT, 'PF.ASAAS.PIX_API', { clientId: 'x' }),
    ).rejects.toThrow('does not use clientId')
    await expect(
      rails.saveCredentials(TENANT, 'PJ.C6_EMPRESAS.BANK_APPROVAL', {
        certificate: pem('c6.pfx', 'binary'),
      }),
    ).rejects.toThrow('certificateValidUntil')
    await expect(rails.test(TENANT, 'PF.ASAAS.PIX_API')).rejects.toThrow(
      NotFoundError,
    )
  })
})

describe('automation', () => {
  it('pauses, resumes and updates the caps per entity', async () => {
    const deps = fullDeps()
    const automation = makeAutomation(deps)
    expect((await automation.get(TENANT)).pausedSince).toBeNull()
    const paused = await automation.pause(TENANT)
    expect(paused.pausedSince).not.toBeNull()
    expect((await deps.settings.get(TENANT, 'pj')).killSwitch).toBe(true)
    await automation.resume(TENANT)
    expect((await deps.settings.get(TENANT, 'pf')).killSwitch).toBe(false)
    const updated = await automation.update(TENANT, {
      entity: 'PJ',
      confirmAboveCents: 50000,
      dailyCapCents: { INTER_EMPRESAS: 100000 },
    })
    expect(updated.entities.map(entity => entity.entity)).toEqual(['PF', 'PJ'])
    expect(updated.entities[1]).toEqual({
      entity: 'PJ',
      confirmAboveCents: 50000,
      dailyCapCents: { INTER_EMPRESAS: 100000 },
    })
    const kept = await automation.update(TENANT, { entity: 'PJ' })
    expect(kept.entities[1]?.confirmAboveCents).toBe(50000)
  })
})
