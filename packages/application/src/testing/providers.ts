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
  type BillSource,
  type CapturedBill,
  type ImportFile,
  type InvoiceDraft,
  type InvoiceIssuer,
  type IssuedInvoice,
  type Notification,
  type Notifier,
  type OpenFinanceProvider,
  type ProviderAccount,
  type ProviderTransaction,
  type SecretVault,
  type StatementDraft,
  type StatementImporter,
} from '@/ports/providers'

type Scripted = RailResult | Error

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
}

export class FakeOpenFinanceProvider implements OpenFinanceProvider {
  constructor(
    private readonly accounts: ProviderAccount[] = [],
    private readonly transactions: ProviderTransaction[] = [],
  ) {}

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

  constructor(private readonly bills: CapturedBill[] = []) {}

  async fetch(): Promise<CapturedBill[]> {
    return this.bills
  }
}

export class FakeInvoiceIssuer implements InvoiceIssuer {
  readonly id = 'fake'
  readonly issued = new Map<string, IssuedInvoice>()

  async issue(
    _draft: InvoiceDraft,
    idempotencyKey: string,
  ): Promise<IssuedInvoice> {
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
