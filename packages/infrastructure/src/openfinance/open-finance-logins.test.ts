import { describe, expect, it, vi } from 'vitest'
import {
  type OpenFinanceProvider,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import { OpenFinanceLogins } from '@/openfinance/open-finance-logins'
import { ProviderHttpError } from '@/http/transport'

const range = { from: '2026-10-01', to: '2026-10-31' }

function login(items: readonly string[], missing: unknown = null) {
  return {
    getItem: vi.fn(async (itemId: string) => {
      if (!items.includes(itemId)) {
        throw missing ?? new ProviderHttpError('Pluggy', 404, 'not found')
      }
      return {
        itemId,
        institutionName: 'Banco Exemplo',
        status: 'UPDATED' as const,
        lastUpdatedAt: null,
      }
    }),
    listAccounts: vi.fn(async () => []),
    listTransactions: vi.fn(async () => []),
    listBills: vi.fn(async () => []),
    listConnectors: vi.fn(async () => []),
    listInvestments: vi.fn(async () => []),
    listInvestmentMovements: vi.fn(async () => []),
  } satisfies OpenFinanceProvider
}

describe('OpenFinanceLogins', () => {
  it('serves each item from the login that owns it, looking it up once', async () => {
    const first = login(['item-1'])
    const second = login(['item-2'])
    const logins = new OpenFinanceLogins([first, second])
    const connection = { provider: 'pluggy', itemId: 'item-2' }

    await logins.listAccounts(connection)
    await logins.listTransactions(connection, 'account-1', range)
    await logins.listBills(connection, 'account-1')
    await logins.listInvestments(connection)
    await logins.listInvestmentMovements(connection, 'investment-1')
    expect(await logins.getItem('item-2')).toMatchObject({ itemId: 'item-2' })

    expect(first.getItem).toHaveBeenCalledTimes(1)
    expect(second.getItem).toHaveBeenCalledTimes(2)
    expect(second.listAccounts).toHaveBeenCalledWith(connection)
    expect(second.listTransactions).toHaveBeenCalledWith(
      connection,
      'account-1',
      range,
    )
    expect(second.listBills).toHaveBeenCalledWith(connection, 'account-1')
    expect(second.listInvestments).toHaveBeenCalledWith(connection)
    expect(second.listInvestmentMovements).toHaveBeenCalledWith(
      connection,
      'investment-1',
    )
    expect(first.listAccounts).not.toHaveBeenCalled()

    expect(await logins.getItem('item-1')).toMatchObject({ itemId: 'item-1' })
    expect(second.getItem).toHaveBeenCalledTimes(2)
  })

  it('reads an unknown item as missing even past an unconfigured login', async () => {
    const logins = new OpenFinanceLogins([
      login([]),
      login([], new ProviderNotConfiguredError('Pluggy')),
    ])
    await expect(logins.getItem('item-9')).rejects.toMatchObject({
      status: 404,
    })
  })

  it('stops at an error that is not about ownership', async () => {
    const broken = login([], new ProviderHttpError('Pluggy', 500, 'down'))
    const other = login(['item-1'])
    const logins = new OpenFinanceLogins([broken, other])
    await expect(logins.getItem('item-1')).rejects.toMatchObject({
      status: 500,
    })
    expect(other.getItem).not.toHaveBeenCalled()
  })

  it('reports not configured when no login is set or there is none', async () => {
    const unset = new ProviderNotConfiguredError('Pluggy')
    await expect(
      new OpenFinanceLogins([login([], unset)]).getItem('item-1'),
    ).rejects.toBe(unset)
    const none = new OpenFinanceLogins([])
    await expect(none.getItem('item-1')).rejects.toBeInstanceOf(
      ProviderNotConfiguredError,
    )
    await expect(none.listConnectors()).rejects.toBeInstanceOf(
      ProviderNotConfiguredError,
    )
  })

  it('lists connectors from the first login', async () => {
    const first = login([])
    await new OpenFinanceLogins([first, login([])]).listConnectors()
    expect(first.listConnectors).toHaveBeenCalledTimes(1)
  })
})
