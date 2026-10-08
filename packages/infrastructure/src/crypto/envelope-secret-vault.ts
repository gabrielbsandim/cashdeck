import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto'
import { type SecretVault } from '@cashdeck/application'

const ALGORITHM = 'aes-256-gcm'
const IV_BYTES = 12
const TAG_BYTES = 16
const KEY_BYTES = 32
const FORMAT = 'v1'

export class SecretVaultError extends Error {
  readonly code = 'SECRET_VAULT_ERROR'

  constructor(message: string) {
    super(message)
    this.name = 'SecretVaultError'
  }
}

function encrypt(key: Buffer, plaintext: Buffer, context: string): string[] {
  const iv = randomBytes(IV_BYTES)
  const cipher = createCipheriv(ALGORITHM, key, iv)
  cipher.setAAD(Buffer.from(context))
  const body = Buffer.concat([
    cipher.update(plaintext),
    cipher.final(),
    cipher.getAuthTag(),
  ])
  return [iv.toString('base64url'), body.toString('base64url')]
}

function decrypt(
  key: Buffer,
  iv: string,
  body: string,
  context: string,
): Buffer {
  const raw = Buffer.from(body, 'base64url')
  const decipher = createDecipheriv(
    ALGORITHM,
    key,
    Buffer.from(iv, 'base64url'),
  )
  decipher.setAAD(Buffer.from(context))
  decipher.setAuthTag(raw.subarray(raw.length - TAG_BYTES))
  return Buffer.concat([
    decipher.update(raw.subarray(0, raw.length - TAG_BYTES)),
    decipher.final(),
  ])
}

// Each secret gets its own data key, wrapped by the master key, so rotating the
// master key only rewraps data keys. The context is bound as associated data.
export class EnvelopeSecretVault implements SecretVault {
  private readonly masterKey: Buffer

  constructor(
    masterKeyBase64: string,
    private readonly keyId = 'k1',
  ) {
    const key = Buffer.from(masterKeyBase64, 'base64')
    if (key.length !== KEY_BYTES) {
      throw new SecretVaultError(
        'The master key must be 32 bytes, base64 encoded.',
      )
    }
    this.masterKey = key
  }

  async seal(plaintext: string, context: string): Promise<string> {
    const dataKey = randomBytes(KEY_BYTES)
    const wrapped = encrypt(this.masterKey, dataKey, `${this.keyId}:${context}`)
    const sealed = encrypt(dataKey, Buffer.from(plaintext, 'utf8'), context)
    return [FORMAT, this.keyId, ...wrapped, ...sealed].join('.')
  }

  async open(sealed: string, context: string): Promise<string> {
    const parts = sealed.split('.')
    const [format, keyId, wrapIv, wrapBody, iv, body] = parts
    if (parts.length !== 6 || format !== FORMAT) {
      throw new SecretVaultError('Unrecognised sealed secret.')
    }
    if (keyId !== this.keyId) {
      throw new SecretVaultError(`Secret was sealed with key ${keyId}.`)
    }
    try {
      const dataKey = decrypt(
        this.masterKey,
        wrapIv as string,
        wrapBody as string,
        `${keyId}:${context}`,
      )
      return decrypt(dataKey, iv as string, body as string, context).toString(
        'utf8',
      )
    } catch {
      throw new SecretVaultError('Secret could not be opened for this context.')
    }
  }
}
