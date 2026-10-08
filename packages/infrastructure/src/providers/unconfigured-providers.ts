import {
  type InvoiceIssuer,
  type IssuedInvoice,
  type OpenFinanceProvider,
  type ProviderAccount,
  type ProviderCheck,
  type ProviderItem,
  type ProviderTransaction,
  ProviderNotConfiguredError,
} from '@cashdeck/application'

export class PluggyOpenFinanceProvider implements OpenFinanceProvider {
  async getItem(): Promise<ProviderItem> {
    throw new ProviderNotConfiguredError('Pluggy')
  }

  async listAccounts(): Promise<ProviderAccount[]> {
    throw new ProviderNotConfiguredError('Pluggy')
  }

  async listTransactions(): Promise<ProviderTransaction[]> {
    throw new ProviderNotConfiguredError('Pluggy')
  }
}

export class NotaasInvoiceIssuer implements InvoiceIssuer {
  readonly id = 'notaas'

  async issue(): Promise<IssuedInvoice> {
    throw new ProviderNotConfiguredError('Notaas')
  }

  async get(): Promise<IssuedInvoice> {
    throw new ProviderNotConfiguredError('Notaas')
  }

  async cancel(): Promise<IssuedInvoice> {
    throw new ProviderNotConfiguredError('Notaas')
  }

  async check(): Promise<ProviderCheck> {
    return { ok: false, message: 'Notaas is not configured.' }
  }
}
