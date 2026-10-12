import {
  type OpenFinanceConnection,
  type OpenFinanceProvider,
  type ProviderItem,
  ProviderNotConfiguredError,
} from '@cashdeck/application'

// Another login answers 403 or 404 for an item it does not own.
const notHere = (error: unknown) =>
  error instanceof ProviderNotConfiguredError ||
  [403, 404].includes(Number((error as { status?: unknown } | null)?.status))

// A household can split its connections over several aggregator accounts. Each
// item is looked up on every login once, then served by the one that owns it.
export class OpenFinanceLogins implements OpenFinanceProvider {
  private readonly owners = new Map<string, OpenFinanceProvider>()

  constructor(private readonly logins: readonly OpenFinanceProvider[]) {}

  async getItem(itemId: string): Promise<ProviderItem> {
    const known = this.owners.get(itemId)
    if (known) {
      return known.getItem(itemId)
    }
    return (await this.locate(itemId)).item
  }

  async listAccounts(connection: OpenFinanceConnection) {
    return (await this.owner(connection)).listAccounts(connection)
  }

  async listTransactions(
    connection: OpenFinanceConnection,
    accountExternalId: string,
    range: { from: string; to: string },
  ) {
    return (await this.owner(connection)).listTransactions(
      connection,
      accountExternalId,
      range,
    )
  }

  async listBills(
    connection: OpenFinanceConnection,
    accountExternalId: string,
  ) {
    return (await this.owner(connection)).listBills(
      connection,
      accountExternalId,
    )
  }

  async listConnectors() {
    const [first] = this.logins
    if (!first) {
      throw new ProviderNotConfiguredError('Open Finance')
    }
    return first.listConnectors()
  }

  async listInvestments(connection: OpenFinanceConnection) {
    return (await this.owner(connection)).listInvestments(connection)
  }

  async listInvestmentMovements(
    connection: OpenFinanceConnection,
    investmentExternalId: string,
  ) {
    return (await this.owner(connection)).listInvestmentMovements(
      connection,
      investmentExternalId,
    )
  }

  private async owner(connection: OpenFinanceConnection) {
    const known = this.owners.get(connection.itemId)
    if (known) {
      return known
    }
    return (await this.locate(connection.itemId)).login
  }

  // An answer from the aggregator outranks a login left unconfigured, so an
  // unknown item still reads as missing.
  private async locate(itemId: string) {
    const errors: unknown[] = []
    for (const login of this.logins) {
      const item = await login.getItem(itemId).catch((error: unknown) => {
        if (!notHere(error)) {
          throw error
        }
        errors.push(error)
        return null
      })
      if (item) {
        this.owners.set(itemId, login)
        return { login, item }
      }
    }
    throw (
      errors.find(error => !(error instanceof ProviderNotConfiguredError)) ??
      errors[0] ??
      new ProviderNotConfiguredError('Open Finance')
    )
  }
}
