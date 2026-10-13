import { TaxId, ValidationError } from '@cashdeck/domain'
import { type HouseholdInput, type HouseholdView } from '@/dtos/household'
import { type Deps } from '@/use-cases/deps'

export const HOUSEHOLD_COLLECTION = 'household'
const MEMBERS = 'members'

type HouseholdDeps = Pick<Deps, 'documents'>

export async function loadHousehold(
  deps: HouseholdDeps,
  tenantId: string,
): Promise<HouseholdView> {
  const stored = await deps.documents.get<HouseholdView>(
    tenantId,
    HOUSEHOLD_COLLECTION,
    MEMBERS,
  )
  return stored ?? { members: [] }
}

export async function householdTaxIds(
  deps: HouseholdDeps,
  tenantId: string,
): Promise<string[]> {
  const { members } = await loadHousehold(deps, tenantId)
  return members.map(member => member.taxId)
}

// A member's company pays them a salary, so only a person's CPF counts as the
// household's own money.
function personOf(raw: string): string {
  const taxId = TaxId.parse(raw)
  if (taxId.kind !== 'CPF') {
    throw new ValidationError('A household member needs a CPF.')
  }
  return taxId.value
}

export function makeHousehold(deps: HouseholdDeps) {
  async function set(
    tenantId: string,
    input: HouseholdInput,
  ): Promise<HouseholdView> {
    const members = input.members.map(member => ({
      name: member.name,
      taxId: personOf(member.taxId),
    }))
    const unique = [...new Map(members.map(m => [m.taxId, m])).values()]
    const view = { members: unique }
    await deps.documents.put(tenantId, HOUSEHOLD_COLLECTION, MEMBERS, view)
    return view
  }

  return { get: (tenantId: string) => loadHousehold(deps, tenantId), set }
}
