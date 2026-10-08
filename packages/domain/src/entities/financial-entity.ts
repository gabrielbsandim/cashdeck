import { ValidationError } from '@/shared/domain-error'
import { guard } from '@/shared/guard'
import { TaxId } from '@/tax-id/tax-id'

export const ENTITY_KINDS = ['PF', 'PJ'] as const
export type EntityKind = (typeof ENTITY_KINDS)[number]

export const TAX_REGIMES = [
  'SIMPLES_NACIONAL',
  'MEI',
  'LUCRO_PRESUMIDO',
  'LUCRO_REAL',
] as const
export type TaxRegime = (typeof TAX_REGIMES)[number]

export type FinancialEntity = {
  readonly id: string
  readonly tenantId: string
  readonly kind: EntityKind
  readonly name: string
  readonly taxId: TaxId
  readonly taxRegime: TaxRegime | null
}

export type CreateFinancialEntityInput = {
  id: string
  tenantId: string
  kind: EntityKind
  name: string
  taxId: string
  taxRegime?: TaxRegime | null
}

const KIND_BY_TAX_ID = { CPF: 'PF', CNPJ: 'PJ' } as const

export function createFinancialEntity(
  input: CreateFinancialEntityInput,
): FinancialEntity {
  const taxId = TaxId.parse(input.taxId)
  if (KIND_BY_TAX_ID[taxId.kind] !== input.kind) {
    throw new ValidationError(`A ${input.kind} entity needs a matching tax id.`)
  }
  const taxRegime = input.taxRegime ?? null
  if (input.kind === 'PF' && taxRegime !== null) {
    throw new ValidationError('A personal entity has no company tax regime.')
  }
  if (input.kind === 'PJ' && taxRegime === null) {
    throw new ValidationError('A company entity needs a tax regime.')
  }
  return {
    id: input.id,
    tenantId: input.tenantId,
    kind: input.kind,
    name: guard.notEmpty(input.name, 'Entity name'),
    taxId,
    taxRegime,
  }
}
