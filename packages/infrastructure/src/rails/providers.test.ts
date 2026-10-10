import { describe, expect, it } from 'vitest'
import { ProviderNotConfiguredError } from '@cashdeck/application'
import {
  asaasRail,
  c6EmpresasRail,
  defaultRails,
  interEmpresasRail,
  mercadoPagoPayoutsRail,
} from '@/rails/unconfigured-rail'
import {
  NotaasInvoiceIssuer,
  PluggyOpenFinanceProvider,
} from '@/providers/unconfigured-providers'

describe('unconfigured rails', () => {
  it('declare the coverage from the payment plan', () => {
    expect(mercadoPagoPayoutsRail().supports('PIX_KEY', 'PF')).toBe(true)
    expect(mercadoPagoPayoutsRail().supports('PIX_KEY', 'PJ')).toBe(false)
    expect(asaasRail().supports('BOLETO', 'PF')).toBe(true)
    expect(asaasRail().supports('TAX_BARCODE', 'PF')).toBe(false)
    expect(interEmpresasRail().supports('DARF_NO_BARCODE', 'PJ')).toBe(true)
    expect(c6EmpresasRail().supports('TAX_BARCODE', 'PJ')).toBe(false)
    expect(defaultRails().map(rail => rail.id)).toEqual([
      'MERCADO_PAGO_PAYOUTS',
      'ASAAS',
      'INTER_EMPRESAS',
      'C6_EMPRESAS',
    ])
  })

  it('throw a typed error when asked to pay', async () => {
    await expect(interEmpresasRail().pay({} as never)).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    expect(await asaasRail().check()).toEqual({
      ok: false,
      message: 'Asaas is not configured.',
    })
  })
})

describe('unconfigured providers', () => {
  it('throw a typed error', async () => {
    const pluggy = new PluggyOpenFinanceProvider()
    await expect(pluggy.listAccounts()).rejects.toThrow(
      'Pluggy is not configured.',
    )
    await expect(pluggy.listTransactions()).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    await expect(pluggy.listBills()).rejects.toThrow(ProviderNotConfiguredError)
    await expect(pluggy.listConnectors()).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    await expect(pluggy.listInvestments()).rejects.toThrow(
      ProviderNotConfiguredError,
    )
    const notaas = new NotaasInvoiceIssuer()
    expect(notaas.id).toBe('notaas')
    await expect(notaas.issue()).rejects.toThrow('Notaas is not configured.')
    await expect(notaas.get()).rejects.toThrow(ProviderNotConfiguredError)
    await expect(notaas.cancel()).rejects.toThrow(ProviderNotConfiguredError)
    await expect(notaas.download()).rejects.toThrow(ProviderNotConfiguredError)
    await expect(pluggy.getItem()).rejects.toThrow(ProviderNotConfiguredError)
    expect((await notaas.check()).ok).toBe(false)
  })
})
