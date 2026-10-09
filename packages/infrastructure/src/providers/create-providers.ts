import {
  type BillSource,
  type DocumentTextReader,
  type InvoiceIssuer,
  type LlmProvider,
  type Notifier,
  type OpenFinanceProvider,
  type PaymentRail,
  type PixLocationResolver,
  type RailStatusReader,
  type ReserveFunder,
  type SecretStore,
  type SecretVault,
  type WebhookReader,
} from '@cashdeck/application'
import { type RailId } from '@cashdeck/domain'
import { BillExtractor } from '@/capture/bill-extractor'
import { C6DdaBillSource } from '@/capture/c6-dda-source'
import { GmailBillSource } from '@/capture/gmail-source'
import { PdfTextReader } from '@/capture/pdf-text-reader'
import { JwsPixLocationResolver } from '@/capture/pix-location-resolver'
import { CredentialResolver } from '@/credentials/credential-resolver'
import { type MtlsFactory, BankClients } from '@/rails/bank-client'
import { fetchTransport, type Transport } from '@/http/transport'
import { NotaasIssuer } from '@/invoices/notaas-issuer'
import { type DeviceTokens, FcmNotifier } from '@/notify/fcm-notifier'
import { PluggyProvider } from '@/openfinance/pluggy-provider'
import { AsaasRail } from '@/rails/asaas-rail'
import { C6EmpresasRail } from '@/rails/c6-empresas-rail'
import {
  type DarfDetailsLookup,
  InterEmpresasRail,
} from '@/rails/inter-empresas-rail'
import { MercadoPagoPayoutsRail } from '@/rails/mercado-pago-rail'
import { PixReserveFunder } from '@/rails/reserve-funder'
import { createWebhookReaders } from '@/webhooks/webhook-readers'

export type CreateProvidersInput = {
  env: Record<string, string | undefined>
  tenantId: string
  secrets?: SecretStore
  vault?: SecretVault
  fetch?: typeof fetch
  transport?: Transport
  mtls?: MtlsFactory
  llm?: LlmProvider
  deviceTokens?: DeviceTokens
  onInvalidToken?: (tenantId: string, token: string) => Promise<void>
  darfDetails?: DarfDetailsLookup
  now?: () => Date
}

export type Providers = {
  credentials: CredentialResolver
  rails: Array<PaymentRail & RailStatusReader>
  railStatus: Map<RailId, RailStatusReader>
  reserveFunder: ReserveFunder
  openFinance: OpenFinanceProvider
  invoiceIssuer: InvoiceIssuer
  billSources: BillSource[]
  pixLocations: PixLocationResolver
  documentText: DocumentTextReader
  notifier: Notifier
  webhooks: WebhookReader[]
}

// Every adapter resolves its credentials on each call, from a sealed secret
// first and the environment second, so credentials uploaded in the app take
// effect without a restart and a missing one reads as "not configured".
export function createProviders(input: CreateProvidersInput): Providers {
  const credentials = new CredentialResolver({
    env: input.env,
    tenantId: input.tenantId,
    secrets: input.secrets,
    vault: input.vault,
  })
  const transport = input.transport ?? fetchTransport(input.fetch)
  const clients = new BankClients(input.mtls)
  const now = input.now ?? (() => new Date())
  const documentText = new PdfTextReader()
  const payouts = new MercadoPagoPayoutsRail({ credentials, transport })
  const asaas = new AsaasRail({ credentials, transport })
  const rails = [
    payouts,
    asaas,
    new InterEmpresasRail({
      credentials,
      clients,
      darfDetails: input.darfDetails,
    }),
    new C6EmpresasRail({ credentials, clients }),
  ]
  return {
    credentials,
    rails,
    railStatus: new Map<RailId, RailStatusReader>(
      rails.map(rail => [rail.id, rail]),
    ),
    reserveFunder: new PixReserveFunder({
      credentials,
      balance: asaas,
      payouts,
    }),
    openFinance: new PluggyProvider({ credentials, transport }),
    invoiceIssuer: new NotaasIssuer({ credentials, transport, now }),
    billSources: [
      new GmailBillSource({
        credentials,
        transport,
        now,
        extractor: input.llm
          ? new BillExtractor(input.llm, documentText)
          : undefined,
      }),
      new C6DdaBillSource({ credentials, clients, now }),
    ],
    pixLocations: new JwsPixLocationResolver({ transport }),
    documentText,
    notifier: new FcmNotifier({
      credentials,
      transport,
      deviceTokens: input.deviceTokens ?? (async () => []),
      onInvalidToken: input.onInvalidToken,
    }),
    webhooks: createWebhookReaders({ credentials }),
  }
}
