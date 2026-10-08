import { describe, expect, it } from 'vitest'
import {
  FakeSecretVault,
  InMemorySecretStore,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import {
  credentialSecretName,
  CredentialResolver,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'

describe('CredentialResolver', () => {
  it('prefers an entity secret, then a tenant secret, then the environment', async () => {
    const secrets = new InMemorySecretStore()
    const vault = new FakeSecretVault()
    await secrets.put(
      't',
      'ASAAS_API_KEY@pj',
      await vault.seal('entity', 'ASAAS_API_KEY@pj'),
    )
    await secrets.put(
      't',
      'ASAAS_API_KEY',
      await vault.seal('tenant', 'ASAAS_API_KEY'),
    )
    const resolver = new CredentialResolver({
      env: { ASAAS_API_KEY: ' env ', EMPTY: ' ' },
      tenantId: 't',
      secrets,
      vault,
    })
    expect(await resolver.get('ASAAS_API_KEY', { entityId: 'pj' })).toBe(
      'entity',
    )
    expect(await resolver.get('ASAAS_API_KEY', { entityId: 'pf' })).toBe(
      'tenant',
    )
    expect(await resolver.get('ASAAS_API_KEY')).toBe('tenant')
    expect(await resolver.get('ASAAS_API_KEY', { tenantId: 'other' })).toBe(
      'env',
    )
    expect(await resolver.get('EMPTY')).toBeNull()
    expect(await resolver.get('MISSING')).toBeNull()
  })

  it('reads only the environment without a vault', async () => {
    const resolver = new CredentialResolver({ env: { A: 'a' }, tenantId: 't' })
    expect(await resolver.get('A', { entityId: 'x' })).toBe('a')
    expect(credentialSecretName('A')).toBe('A')
    expect(credentialSecretName('A', 'e')).toBe('A@e')
  })

  it('requires every credential or reports the provider unconfigured', async () => {
    const resolver = new CredentialResolver({
      env: { A: 'a', B: 'b' },
      tenantId: 't',
    })
    expect(await requireCredentials(resolver, 'X', ['A', 'B'])).toEqual({
      A: 'a',
      B: 'b',
    })
    await expect(requireCredentials(resolver, 'X', ['A', 'C'])).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    expect(await optionalCredential(resolver, 'C', 'fallback')).toBe('fallback')
    expect(await optionalCredential(resolver, 'A', 'fallback')).toBe('a')
  })
})
