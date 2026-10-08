import {
  type PaymentRail,
  type PaymentRequest,
  ProviderNotConfiguredError,
  type RailResult,
} from '@cashdeck/application'
import { type BillKind, type EntityKind, type RailId } from '@cashdeck/domain'

type Coverage = {
  entityKinds: readonly EntityKind[]
  billKinds: readonly BillKind[]
}

// Real calls land after each Phase 0 spike; until then a rail reports itself
// unconfigured and the ladder moves down a step.
export class UnconfiguredRail implements PaymentRail {
  constructor(
    readonly id: RailId,
    readonly provider: string,
    private readonly coverage: Coverage,
  ) {}

  supports(kind: BillKind, entityKind: EntityKind): boolean {
    return (
      this.coverage.entityKinds.includes(entityKind) &&
      this.coverage.billKinds.includes(kind)
    )
  }

  async pay(_request: PaymentRequest): Promise<RailResult> {
    throw new ProviderNotConfiguredError(this.provider)
  }
}

export function mercadoPagoPayoutsRail(): UnconfiguredRail {
  return new UnconfiguredRail('MERCADO_PAGO_PAYOUTS', 'Mercado Pago Payouts', {
    entityKinds: ['PF'],
    billKinds: ['PIX_KEY'],
  })
}

export function asaasRail(): UnconfiguredRail {
  return new UnconfiguredRail('ASAAS', 'Asaas', {
    entityKinds: ['PF', 'PJ'],
    billKinds: ['BOLETO', 'PIX_QR', 'PIX_KEY'],
  })
}

export function interEmpresasRail(): UnconfiguredRail {
  return new UnconfiguredRail('INTER_EMPRESAS', 'Inter Empresas', {
    entityKinds: ['PJ'],
    billKinds: [
      'BOLETO',
      'PIX_KEY',
      'PIX_QR',
      'TAX_BARCODE',
      'DARF_NO_BARCODE',
    ],
  })
}

export function c6EmpresasRail(): UnconfiguredRail {
  return new UnconfiguredRail('C6_EMPRESAS', 'C6 Empresas', {
    entityKinds: ['PJ'],
    billKinds: ['BOLETO', 'PIX_KEY'],
  })
}

export function defaultRails(): UnconfiguredRail[] {
  return [
    mercadoPagoPayoutsRail(),
    asaasRail(),
    interEmpresasRail(),
    c6EmpresasRail(),
  ]
}
