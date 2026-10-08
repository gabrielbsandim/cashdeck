import { randomBytes } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  EnvelopeSecretVault,
  SecretVaultError,
} from '@/crypto/envelope-secret-vault'

const key = randomBytes(32).toString('base64')

describe('EnvelopeSecretVault', () => {
  it('round trips a secret bound to its context', async () => {
    const vault = new EnvelopeSecretVault(key)
    const sealed = await vault.seal('token-123', 'tenant:t1:rail:INTER')
    expect(sealed.startsWith('v1.k1.')).toBe(true)
    expect(sealed).not.toContain('token-123')
    expect(await vault.open(sealed, 'tenant:t1:rail:INTER')).toBe('token-123')
    expect(await vault.seal('token-123', 'c')).not.toBe(
      await vault.seal('token-123', 'c'),
    )
  })

  it('refuses the wrong context, a tampered body and another key', async () => {
    const vault = new EnvelopeSecretVault(key)
    const sealed = await vault.seal('secret', 'a')
    await expect(vault.open(sealed, 'b')).rejects.toThrow(SecretVaultError)
    const parts = sealed.split('.')
    parts[5] = Buffer.from('tampered-body-with-enough-bytes').toString(
      'base64url',
    )
    await expect(vault.open(parts.join('.'), 'a')).rejects.toThrow(
      'could not be opened',
    )
    const rotated = new EnvelopeSecretVault(
      randomBytes(32).toString('base64'),
      'k2',
    )
    await expect(rotated.open(sealed, 'a')).rejects.toThrow(
      'sealed with key k1',
    )
    await expect(vault.open('garbage', 'a')).rejects.toThrow('Unrecognised')
    await expect(vault.open(`v2${sealed.slice(2)}`, 'a')).rejects.toThrow(
      'Unrecognised',
    )
  })

  it('requires a 32 byte master key', () => {
    expect(() => new EnvelopeSecretVault('c2hvcnQ=')).toThrow('32 bytes')
  })
})
