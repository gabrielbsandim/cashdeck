import { describe, it, expect, beforeEach } from 'vitest'
import { PrismaNeon } from '@prisma/adapter-neon'
import { PrismaPg } from '@prisma/adapter-pg'
import { neonConfig } from '@neondatabase/serverless'

import { createRuntimeAdapter } from '@/database/runtime-adapter'

const NEON_POOLED =
  'postgresql://user:secret@ep-cool-name-123456-pooler.us-east-2.aws.neon.tech/cashdeck?sslmode=require'
const NEON_UPPERCASE_HOST =
  'postgresql://user:secret@EP-Cool-Name-123456.US-East-2.AWS.Neon.Tech/cashdeck?sslmode=require'
const LOCAL = 'postgresql://postgres:postgres@localhost:5432/cashdeck'
const CI_SERVICE = 'postgresql://postgres:postgres@postgres:5432/cashdeck_ci'

describe('createRuntimeAdapter', () => {
  beforeEach(() => {
    neonConfig.poolQueryViaFetch = false
  })

  it('uses the Neon driver for a Neon connection string', () => {
    expect(createRuntimeAdapter(NEON_POOLED)).toBeInstanceOf(PrismaNeon)
    expect(createRuntimeAdapter(NEON_UPPERCASE_HOST)).toBeInstanceOf(PrismaNeon)
  })

  it('uses the standard pg driver for a plain Postgres connection string', () => {
    expect(createRuntimeAdapter(LOCAL)).toBeInstanceOf(PrismaPg)
    expect(createRuntimeAdapter(CI_SERVICE)).toBeInstanceOf(PrismaPg)
  })

  it('sends queries over HTTP on Neon', () => {
    createRuntimeAdapter(NEON_POOLED)
    expect(neonConfig.poolQueryViaFetch).toBe(true)
  })

  it('leaves the HTTP transport off for a plain Postgres', () => {
    createRuntimeAdapter(LOCAL)
    expect(neonConfig.poolQueryViaFetch).toBe(false)
  })
})
