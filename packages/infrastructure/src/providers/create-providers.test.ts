import { describe, expect, it, vi } from 'vitest'
import {
  FakeLlmProvider,
  FakeSecretVault,
  InMemorySecretStore,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import { createProviders } from '@/providers/create-providers'
import {
  checkWith,
  outcomeFrom,
  splitExternalId,
  statusResult,
} from '@/rails/rail-support'
import { ASAAS_URLS } from '@/rails/asaas-rail'
import { payment, TENANT } from '@/testing/provider-fixtures'
import { ScriptedTransport } from '@/testing/scripted-transport'

describe('createProviders', () => {
  it('wires every adapter behind its port', async () => {
    const providers = createProviders({ env: {}, tenantId: TENANT })
    expect(providers.rails.map(rail => rail.id)).toEqual([
      'MERCADO_PAGO_PAYOUTS',
      'ASAAS',
      'INTER_EMPRESAS',
      'C6_EMPRESAS',
    ])
    expect([...providers.railStatus.keys()]).toHaveLength(4)
    expect(providers.billSources.map(source => source.source)).toEqual([
      'GMAIL',
      'DDA',
    ])
    expect(providers.invoiceIssuer.id).toBe('notaas')
    expect(await providers.pixLocations.resolve('localhost/qr')).toBeNull()
    expect(
      await providers.documentText.read({
        mimeType: 'image/png',
        bytes: new Uint8Array(),
      }),
    ).toBeNull()
    for (const rail of providers.rails) {
      expect((await rail.check()).ok).toBe(false)
    }
    await expect(providers.openFinance.getItem('x')).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    await expect(providers.preview.listAccounts()).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    await expect(
      providers.notifier.notify({
        tenantId: TENANT,
        type: 'x',
        title: 't',
        body: 'b',
        localized: {
          pt: { title: 't', body: 'b' },
          en: { title: 't', body: 'b' },
        },
        data: {},
      }),
    ).resolves.toBeUndefined()
  })

  it('picks up a credential sealed after start', async () => {
    const secrets = new InMemorySecretStore()
    const vault = new FakeSecretVault()
    const scripted = new ScriptedTransport().on(
      'POST',
      `${ASAAS_URLS.production}/bill`,
      { json: { id: 'b1', status: 'PENDING' } },
    )
    const providers = createProviders({
      env: {},
      tenantId: TENANT,
      secrets,
      vault,
      transport: scripted.transport,
      llm: new FakeLlmProvider(),
      now: () => new Date('2026-10-08T12:00:00Z'),
    })
    const asaas = providers.rails[1]
    await expect(asaas?.pay(payment())).rejects.toThrow('not configured')
    await secrets.put(
      TENANT,
      'ASAAS_API_KEY@entity-1',
      await vault.seal('sealed-key', 'ASAAS_API_KEY@entity-1'),
    )
    expect((await asaas?.pay(payment()))?.externalId).toBe('bill:b1')
    expect(
      scripted.last('POST', `${ASAAS_URLS.production}/bill`).headers,
    ).toMatchObject({
      access_token: 'sealed-key',
    })
  })

  it('uses fetch when no transport is given', async () => {
    const fetchImpl = vi.fn(async () => new Response('{}', { status: 200 }))
    const providers = createProviders({
      env: { ASAAS_API_KEY: 'k' },
      tenantId: TENANT,
      fetch: fetchImpl as unknown as typeof fetch,
    })
    expect(await providers.rails[1]?.check()).toEqual({
      ok: true,
      message: null,
    })
    expect(fetchImpl).toHaveBeenCalledOnce()
  })
})

describe('rail support', () => {
  it('maps statuses, splits ids and reports odd failures', async () => {
    expect(outcomeFrom({ DONE: 'PAID' }, 'DONE')).toBe('PAID')
    expect(outcomeFrom({ DONE: 'PAID' }, undefined, 'FAILED')).toBe('FAILED')
    expect(splitExternalId('pix:a:b', 'X')).toEqual(['pix', 'a:b'])
    expect(() => splitExternalId(':a', 'X')).toThrow('does not know')
    expect(statusResult('PAID', 'e')).toEqual({
      outcome: 'PAID',
      externalId: 'e',
      endToEndId: null,
      settledAt: null,
      reason: null,
    })
    expect(
      await checkWith('X', async () => {
        throw 'boom'
      }),
    ).toEqual({ ok: false, message: 'X check failed: boom' })
  })
})
