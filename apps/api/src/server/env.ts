import { z } from 'zod'

const envSchema = z.object({
  CASHDECK_TENANT_ID: z.string().min(1).default('local'),
  DATABASE_URL: z.string().optional(),
  CASHDECK_MASTER_KEY: z.string().optional(),
  CRON_SECRET: z.string().optional(),
  SENTRY_DSN: z.string().optional(),
  LLM_PROVIDER: z.string().optional(),
  GEMINI_API_KEY: z.string().optional(),
  GEMINI_MODEL_ID: z.string().optional(),
  AI_GATEWAY_API_KEY: z.string().optional(),
  AI_GATEWAY_FALLBACK_MODEL: z.string().optional(),
  BRL_PER_USD: z.string().optional(),
})

export type ServerEnv = z.infer<typeof envSchema>

export function readEnv(
  source: Record<string, string | undefined> = process.env,
): ServerEnv {
  return envSchema.parse(source)
}
