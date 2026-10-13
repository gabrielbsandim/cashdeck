import { describe, expect, it } from 'vitest'
import { ValidationError } from '@cashdeck/domain'
import { fullDeps } from '@/testing/deps.test-helpers'
import { TENANT } from '@/testing/scenario.test-helpers'
import { householdTaxIds, makeHousehold } from '@/use-cases/household'

describe('household', () => {
  it('keeps each member once, by the digits of the CPF', async () => {
    const deps = fullDeps()
    const household = makeHousehold(deps)
    expect(await household.get(TENANT)).toEqual({ members: [] })

    const saved = await household.set(TENANT, {
      members: [
        { name: 'Ana Lima', taxId: '111.444.777-35' },
        { name: 'Ana', taxId: '11144477735' },
      ],
    })

    expect(saved).toEqual({ members: [{ name: 'Ana', taxId: '11144477735' }] })
    expect(await household.get(TENANT)).toEqual(saved)
    expect(await householdTaxIds(deps, TENANT)).toEqual(['11144477735'])
  })

  it('refuses a company, whose payments are a salary', async () => {
    const household = makeHousehold(fullDeps())
    await expect(
      household.set(TENANT, {
        members: [{ name: 'Ana Lima ME', taxId: '11.222.333/0001-81' }],
      }),
    ).rejects.toThrow(ValidationError)
  })
})
