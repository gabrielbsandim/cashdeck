import { createHash, randomBytes } from 'node:crypto'
import { type SessionTokens } from '@cashdeck/application'

const TOKEN_BYTES = 32

// A plain sha256 is enough here: the token is 256 random bits, so there is
// nothing to brute force and lookups stay a single indexed equality.
export class RandomSessionTokens implements SessionTokens {
  issue(): string {
    return randomBytes(TOKEN_BYTES).toString('base64url')
  }

  hash(token: string): string {
    return createHash('sha256').update(token).digest('hex')
  }
}
