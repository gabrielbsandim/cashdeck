import {
  type Credentials,
  type CredentialScope,
  optionalCredential,
  requireCredentials,
} from '@/credentials/credential-resolver'
import {
  type Call,
  isClientError,
  isSuccess,
  ProviderHttpError,
  readJson,
  safeJson,
} from '@/http/transport'
import { type BankClient, type BankClients } from '@/rails/bank-client'

export const C6_PROVIDER = 'C6 Empresas'

export const C6_HOSTS = {
  production: 'https://baas-api.c6bank.info',
  sandbox: 'https://baas-api-sandbox.c6bank.info',
} as const

export type C6Answer<T> = { ok: true; data: T } | { ok: false; reason: string }

export type C6Client = {
  bank: BankClient
  baseUrl: string
  uploaderName: string
}

export async function c6Client(
  credentials: Credentials,
  clients: BankClients,
  scope: CredentialScope,
): Promise<C6Client> {
  const values = await requireCredentials(
    credentials,
    C6_PROVIDER,
    ['C6_CLIENT_ID', 'C6_CLIENT_SECRET', 'C6_CERT', 'C6_KEY'],
    scope,
  )
  const environment = await optionalCredential(
    credentials,
    'C6_ENVIRONMENT',
    'production',
    scope,
  )
  const host =
    environment === 'sandbox' ? C6_HOSTS.sandbox : C6_HOSTS.production
  // The schedule-payments spec names no token endpoint; this default is unconfirmed.
  const tokenUrl = await optionalCredential(
    credentials,
    'C6_TOKEN_URL',
    `${host}/v1/auth/`,
    scope,
  )
  const uploaderName = await optionalCredential(
    credentials,
    'C6_UPLOADER_NAME',
    'Cashdeck',
    scope,
  )
  const bank = clients.for({
    provider: C6_PROVIDER,
    tokenUrl,
    clientId: values.C6_CLIENT_ID,
    clientSecret: values.C6_CLIENT_SECRET,
    scope: null,
    certificate: { cert: values.C6_CERT, key: values.C6_KEY },
  })
  return { bank, baseUrl: `${host}/v1/schedule_payments`, uploaderName }
}

export async function c6Call<T>(
  client: C6Client,
  request: Call,
): Promise<C6Answer<T>> {
  const response = await client.bank.call({
    ...request,
    url: `${client.baseUrl}${request.url}`,
  })
  if (isSuccess(response)) {
    return { ok: true, data: readJson<T>(response) }
  }
  if (isClientError(response)) {
    const body = safeJson(response.text) as {
      message?: string
      detail?: string
    } | null
    return {
      ok: false,
      reason:
        body?.message ??
        body?.detail ??
        `C6 refused the request (${response.status}).`,
    }
  }
  throw new ProviderHttpError(C6_PROVIDER, response.status, response.text)
}
