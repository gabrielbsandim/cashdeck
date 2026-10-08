import { describe, it, expect } from 'vitest'

import { isNeonConnectionString } from '@/database/connection-string'

const NEON_POOLED =
  'postgresql://user:secret@ep-cool-name-123456-pooler.us-east-2.aws.neon.tech/cashdeck?sslmode=require'
const NEON_DIRECT =
  'postgresql://user:secret@ep-cool-name-123456.us-east-2.aws.neon.tech/cashdeck?sslmode=require'
const NEON_UPPERCASE_HOST =
  'postgresql://user:secret@EP-Cool-Name-123456.US-East-2.AWS.Neon.Tech/cashdeck?sslmode=require'
const LOCAL = 'postgresql://postgres:postgres@localhost:5432/cashdeck'
const CI_SERVICE = 'postgresql://postgres:postgres@postgres:5432/cashdeck'

describe('isNeonConnectionString', () => {
  it('recognises the pooled and direct Neon endpoints', () => {
    expect(isNeonConnectionString(NEON_POOLED)).toBe(true)
    expect(isNeonConnectionString(NEON_DIRECT)).toBe(true)
  })

  it('recognises a Neon host written in mixed case', () => {
    expect(new URL(NEON_UPPERCASE_HOST).hostname).not.toBe(
      new URL(NEON_UPPERCASE_HOST).hostname.toLowerCase(),
    )
    expect(isNeonConnectionString(NEON_UPPERCASE_HOST)).toBe(true)
  })

  it('does not treat a plain Postgres host as Neon', () => {
    expect(isNeonConnectionString(LOCAL)).toBe(false)
    expect(isNeonConnectionString(CI_SERVICE)).toBe(false)
    expect(
      isNeonConnectionString(
        'postgresql://user:pass@db.internal:5432/cashdeck',
      ),
    ).toBe(false)
  })

  it('matches on the host suffix, not on a substring anywhere', () => {
    expect(
      isNeonConnectionString('postgresql://u:p@neon.tech.example.com/db'),
    ).toBe(false)
  })

  it('handles a password containing @ and spaces', () => {
    expect(
      isNeonConnectionString(
        'postgresql://user:p@ss w0rd@ep-x.us-east-2.aws.neon.tech/cashdeck',
      ),
    ).toBe(true)
  })

  it('reports false for a string that is not a URL at all', () => {
    expect(() => new URL('not a connection string')).toThrow()
    expect(isNeonConnectionString('not a connection string')).toBe(false)
    expect(isNeonConnectionString('')).toBe(false)
  })
})
