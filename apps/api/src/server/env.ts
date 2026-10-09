import { z } from 'zod'

// Read by the provider adapters through createProviders; a credential stored in
// the app overrides the variable. See docs/providers.md.
export const PROVIDER_ENV_NAMES = [
  'PLUGGY_CLIENT_ID',
  'PLUGGY_CLIENT_SECRET',
  'ASAAS_API_KEY',
  'ASAAS_ENVIRONMENT',
  'ASAAS_PIX_KEY',
  'MERCADO_PAGO_ACCESS_TOKEN',
  'MERCADO_PAGO_SIGNING_KEY',
  'MERCADO_PAGO_ENVIRONMENT',
  'INTER_CLIENT_ID',
  'INTER_CLIENT_SECRET',
  'INTER_CERT',
  'INTER_KEY',
  'INTER_ACCOUNT',
  'INTER_ENVIRONMENT',
  'C6_CLIENT_ID',
  'C6_CLIENT_SECRET',
  'C6_CERT',
  'C6_KEY',
  'C6_TOKEN_URL',
  'C6_UPLOADER_NAME',
  'C6_ENVIRONMENT',
  'GMAIL_CLIENT_ID',
  'GMAIL_CLIENT_SECRET',
  'GMAIL_REDIRECT_URI',
  'NOTAAS_API_KEY',
  'NOTAAS_ALIQUOTA_ISS',
  'NOTAAS_LOCAL_PRESTACAO',
  'NOTAAS_EXPORT_COUNTRY',
  'NOTAAS_WEBHOOK_SECRET',
  'ASAAS_WEBHOOK_TOKEN',
  'MERCADO_PAGO_WEBHOOK_SECRET',
  'INTER_WEBHOOK_TOKEN',
  'PLUGGY_WEBHOOK_SECRET',
  'FCM_SERVICE_ACCOUNT_JSON',
] as const

const providerEnv = Object.fromEntries(
  PROVIDER_ENV_NAMES.map(name => [name, z.string().optional()]),
) as Record<(typeof PROVIDER_ENV_NAMES)[number], z.ZodOptional<z.ZodString>>

const envSchema = z.object({
  CASHDECK_TENANT_ID: z.string().min(1).default('local'),
  DATABASE_URL: z.string().optional(),
  VERCEL_ENV: z.string().optional(),
  CASHDECK_MASTER_KEY: z.string().optional(),
  CRON_SECRET: z.string().optional(),
  SENTRY_DSN: z.string().optional(),
  LLM_PROVIDER: z.string().optional(),
  GEMINI_API_KEY: z.string().optional(),
  GEMINI_MODEL_ID: z.string().optional(),
  AI_GATEWAY_API_KEY: z.string().optional(),
  AI_GATEWAY_FALLBACK_MODEL: z.string().optional(),
  BRL_PER_USD: z.string().optional(),
  // An empty variable reads as unset; a set token must be long enough to guess.
  CASHDECK_API_TOKEN: z.preprocess(
    value => (value === '' ? undefined : value),
    z.string().min(16).optional(),
  ),
  CASHDECK_SERVER_NAME: z.string().min(1).default('Cashdeck'),
  CASHDECK_APP_SCHEME: z.string().min(1).default('cashdeck'),
  ...providerEnv,
})

export type ServerEnv = z.infer<typeof envSchema>

export function readEnv(
  source: Record<string, string | undefined> = process.env,
): ServerEnv {
  return envSchema.parse(source)
}
