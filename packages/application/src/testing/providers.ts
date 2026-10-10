import { type BillKind, type RailId } from '@cashdeck/domain'
import {
  assertSchemaWithoutTools,
  type LlmChatParams,
  type LlmChatResult,
  type LlmProvider,
} from '@/ports/llm-provider'
import {
  type PaymentRail,
  type PaymentRequest,
  type RailResult,
} from '@/ports/payment-rail'
import {
  type BillOwner,
  type BillSource,
  type CapturedBill,
  type ImportFile,
  type InvoiceDraft,
  type InvoiceIssuer,
  type IssuedInvoice,
  type Notification,
  type Notifier,
  type OpenFinanceProvider,
  type PixCharge,
  type PixLocationResolver,
  type PreviewAccount,
  type PreviewProvider,
  type ProviderAccount,
  type ProviderBill,
  type ProviderCheck,
  type ProviderConnector,
  type ProviderItem,
  type ProviderTransaction,
  type SecretVault,
  type StatementDraft,
  type StatementImporter,
} from '@/ports/providers'
import {
  type ProviderInvestment,
  type ProviderMovement,
} from '@/ports/investments'
import { type RailStatusScope } from '@/ports/rail-status'
import {
  type FundingRequest,
  type FundingResult,
  type ReserveFunder,
} from '@/ports/reserve-funder'

type Scripted = RailResult | Error

type ScriptedFunding = FundingResult | Error

export class FakeReserveFunder implements ReserveFunder {
  readonly requests: FundingRequest[] = []
  private readonly script: ScriptedFunding[] = []

  constructor(
    public available: number | Error = 0,
    private readonly fallback: FundingResult = {
      outcome: 'PAID',
      externalId: 'funding',
      reason: null,
    },
  ) {}

  willReturn(...results: ScriptedFunding[]): this {
    this.script.push(...results)
    return this
  }

  async availableCents(_scope: RailStatusScope): Promise<number> {
    if (this.available instanceof Error) {
      throw this.available
    }
    return this.available
  }

  async fund(request: FundingRequest): Promise<FundingResult> {
    this.requests.push(request)
    const next = this.script.shift() ?? this.fallback
    if (next instanceof Error) {
      throw next
    }
    return next
  }
}

export class FakePaymentRail implements PaymentRail {
  readonly requests: PaymentRequest[] = []
  private readonly script: Scripted[] = []

  constructor(
    readonly id: RailId,
    private readonly kinds: readonly BillKind[] = [
      'BOLETO',
      'PIX_KEY',
      'PIX_QR',
      'TAX_BARCODE',
      'DARF_NO_BARCODE',
    ],
    private readonly fallback: RailResult = {
      outcome: 'PAID',
      externalId: 'fake',
    },
  ) {}

  willReturn(...results: Scripted[]): this {
    this.script.push(...results)
    return this
  }

  supports(kind: BillKind): boolean {
    return this.kinds.includes(kind)
  }

  async pay(request: PaymentRequest): Promise<RailResult> {
    this.requests.push(request)
    const next = this.script.shift() ?? this.fallback
    if (next instanceof Error) {
      throw next
    }
    return next
  }

  async check(): Promise<ProviderCheck> {
    return { ok: true, message: null }
  }
}

export class FakeOpenFinanceProvider implements OpenFinanceProvider {
  bills = new Map<string, ProviderBill[]>()
  connectors: ProviderConnector[] = []
  investments: ProviderInvestment[] | Error = []
  movements = new Map<string, ProviderMovement[] | Error>()

  constructor(
    private readonly accounts: ProviderAccount[] = [],
    private readonly transactions: ProviderTransaction[] = [],
    private readonly items: ProviderItem[] = [],
  ) {}

  async listBills(
    _connection: unknown,
    accountExternalId: string,
  ): Promise<ProviderBill[]> {
    return this.bills.get(accountExternalId) ?? []
  }

  async listConnectors(): Promise<ProviderConnector[]> {
    return this.connectors
  }

  async listInvestments(): Promise<ProviderInvestment[]> {
    if (this.investments instanceof Error) {
      throw this.investments
    }
    return this.investments
  }

  async listInvestmentMovements(
    _connection: unknown,
    investmentExternalId: string,
  ): Promise<ProviderMovement[]> {
    const movements = this.movements.get(investmentExternalId) ?? []
    if (movements instanceof Error) {
      throw movements
    }
    return movements
  }

  async getItem(itemId: string): Promise<ProviderItem> {
    const item = this.items.find(candidate => candidate.itemId === itemId)
    if (!item) {
      throw new Error(`Item ${itemId} was not found.`)
    }
    return item
  }

  async listAccounts(): Promise<ProviderAccount[]> {
    return this.accounts
  }

  async listTransactions(
    _connection: unknown,
    accountExternalId: string,
    range: { from: string; to: string },
  ): Promise<ProviderTransaction[]> {
    return this.transactions.filter(
      tx =>
        tx.accountExternalId === accountExternalId &&
        tx.bookedOn >= range.from &&
        tx.bookedOn <= range.to,
    )
  }
}

export class FakePreviewProvider implements PreviewProvider {
  refreshes = 0
  refreshError: Error | null = null

  constructor(
    readonly accounts: PreviewAccount[] = [],
    readonly transactions: ProviderTransaction[] = [],
  ) {}

  async listAccounts(): Promise<PreviewAccount[]> {
    return this.accounts
  }

  async listTransactions(range: {
    from: string
    to: string
  }): Promise<ProviderTransaction[]> {
    return this.transactions.filter(
      tx => tx.bookedOn >= range.from && tx.bookedOn <= range.to,
    )
  }

  async requestRefresh(): Promise<void> {
    this.refreshes += 1
    if (this.refreshError) {
      throw this.refreshError
    }
  }
}

export class FakeStatementImporter implements StatementImporter {
  readonly format = 'fake'

  constructor(private readonly draft: StatementDraft) {}

  canRead(file: ImportFile): boolean {
    return file.name.endsWith('.fake')
  }

  async read(): Promise<StatementDraft> {
    return this.draft
  }
}

export class FakeBillSource implements BillSource {
  readonly source = 'GMAIL' as const
  readonly owners: Array<BillOwner | undefined> = []

  constructor(private readonly bills: CapturedBill[] = []) {}

  async fetch(
    _tenantId: string,
    _entityId: string,
    _since: Date,
    owner?: BillOwner,
  ): Promise<CapturedBill[]> {
    this.owners.push(owner)
    return this.bills
  }
}

export class FakePixLocationResolver implements PixLocationResolver {
  readonly resolved: string[] = []

  constructor(
    private readonly charges: Record<string, PixCharge | Error> = {},
  ) {}

  async resolve(location: string): Promise<PixCharge | null> {
    this.resolved.push(location)
    const charge = this.charges[location]
    if (charge instanceof Error) {
      throw charge
    }
    return charge ?? null
  }
}

export class FakeInvoiceIssuer implements InvoiceIssuer {
  readonly id = 'fake'
  readonly issued = new Map<string, IssuedInvoice>()
  readonly drafts: InvoiceDraft[] = []

  async issue(
    draft: InvoiceDraft,
    idempotencyKey: string,
  ): Promise<IssuedInvoice> {
    this.drafts.push(draft)
    const existing = this.issued.get(idempotencyKey)
    if (existing) {
      return existing
    }
    const invoice: IssuedInvoice = {
      externalId: idempotencyKey,
      number: String(this.issued.size + 1),
      status: 'ISSUED',
      pdfUrl: null,
      xmlUrl: null,
    }
    this.issued.set(idempotencyKey, invoice)
    return invoice
  }

  async get(externalId: string): Promise<IssuedInvoice> {
    const invoice = this.issued.get(externalId)
    if (!invoice) {
      throw new Error(`Invoice ${externalId} was not issued.`)
    }
    return invoice
  }

  async cancel(externalId: string, _reason: string): Promise<IssuedInvoice> {
    const cancelled = {
      ...(await this.get(externalId)),
      status: 'CANCELLED' as const,
    }
    this.issued.set(externalId, cancelled)
    return cancelled
  }

  async download(url: string): Promise<Uint8Array> {
    return new TextEncoder().encode(`document:${url}`)
  }

  async check(): Promise<ProviderCheck> {
    return { ok: true, message: null }
  }
}

export class FakeNotifier implements Notifier {
  readonly sent: Notification[] = []

  async notify(notification: Notification): Promise<void> {
    this.sent.push(notification)
  }
}

export class FakeSecretVault implements SecretVault {
  async seal(plaintext: string, context: string): Promise<string> {
    return `sealed:${context}:${plaintext}`
  }

  async open(sealed: string, context: string): Promise<string> {
    const prefix = `sealed:${context}:`
    if (!sealed.startsWith(prefix)) {
      throw new Error('Secret was sealed for another context.')
    }
    return sealed.slice(prefix.length)
  }
}

const EMPTY_USAGE = { inputTokens: 0, outputTokens: 0, costMillicents: 0 }

export class FakeLlmProvider implements LlmProvider {
  readonly name = 'fake'
  readonly modelId = 'fake-llm'
  readonly calls: LlmChatParams[] = []
  private readonly queue: LlmChatResult[] = []

  enqueue(result: LlmChatResult): this {
    this.queue.push(result)
    return this
  }

  enqueueObject(object: unknown): this {
    return this.enqueue({
      text: JSON.stringify(object),
      toolCalls: [],
      usage: EMPTY_USAGE,
      stopReason: 'end',
      object,
    })
  }

  async chat(params: LlmChatParams): Promise<LlmChatResult> {
    assertSchemaWithoutTools(params)
    this.calls.push(params)
    return (
      this.queue.shift() ?? {
        text: 'fake response',
        toolCalls: [],
        usage: EMPTY_USAGE,
        stopReason: 'end',
      }
    )
  }
}
