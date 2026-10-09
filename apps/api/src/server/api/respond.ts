import { NextResponse } from 'next/server'
import { ZodError } from 'zod'
import { InvalidTransitionError, ValidationError } from '@cashdeck/domain'
import {
  AmountRequiredError,
  NotFoundError,
  ProviderError,
  ProviderNotConfiguredError,
} from '@cashdeck/application'
import { reportError } from '@/server/observability'

export type ApiErrorBody = {
  error: { code: string; message: string; details?: unknown }
}

export function ok<T>(data: T, status = 200): NextResponse {
  return NextResponse.json({ data }, { status })
}

export function okPage<T>(items: T[], nextCursor: string | null): NextResponse {
  return NextResponse.json({ data: items, nextCursor })
}

export function fileResponse(
  bytes: Uint8Array,
  contentType: string,
  fileName: string,
): Response {
  return new Response(Buffer.from(bytes), {
    headers: {
      'content-type': contentType,
      'content-disposition': `attachment; filename="${fileName.replaceAll('"', '')}"`,
      'content-length': String(bytes.length),
    },
  })
}

export function fail(
  code: string,
  message: string,
  status: number,
  details?: unknown,
): NextResponse<ApiErrorBody> {
  return NextResponse.json({ error: { code, message, details } }, { status })
}

type ErrorRule = {
  matches: (error: unknown) => boolean
  respond: (error: Error) => NextResponse<ApiErrorBody>
}

const PRISMA_STATUS: Record<string, [string, number]> = {
  P2002: ['CONFLICT', 409],
  P2025: ['NOT_FOUND', 404],
}

function prismaCode(error: unknown): string | null {
  const code = (error as { code?: unknown } | null)?.code
  return typeof code === 'string' && code in PRISMA_STATUS ? code : null
}

const RULES: ErrorRule[] = [
  {
    matches: error => error instanceof ZodError,
    respond: error =>
      fail('VALIDATION_ERROR', 'Invalid request payload.', 422, {
        issues: (error as ZodError).issues,
      }),
  },
  {
    matches: error => error instanceof AmountRequiredError,
    respond: error =>
      fail(
        'AMOUNT_REQUIRED',
        error.message,
        422,
        (error as AmountRequiredError).details,
      ),
  },
  {
    matches: error => error instanceof ValidationError,
    respond: error => fail('VALIDATION_ERROR', error.message, 422),
  },
  {
    matches: error => error instanceof SyntaxError,
    respond: () => fail('INVALID_JSON', 'Request body is not valid JSON.', 400),
  },
  {
    matches: error => error instanceof NotFoundError,
    respond: error => fail('NOT_FOUND', error.message, 404),
  },
  {
    matches: error => error instanceof InvalidTransitionError,
    respond: error => fail('INVALID_TRANSITION', error.message, 409),
  },
  {
    matches: error => error instanceof ProviderNotConfiguredError,
    respond: error => fail('NOT_CONFIGURED', error.message, 503),
  },
  {
    matches: error =>
      error instanceof ProviderError ||
      (error as { code?: unknown } | null)?.code === 'PROVIDER_HTTP_ERROR',
    respond: error => fail('PROVIDER_ERROR', error.message, 502),
  },
  {
    matches: error => prismaCode(error) !== null,
    respond: error => {
      const [code, status] = PRISMA_STATUS[prismaCode(error) as string] as [
        string,
        number,
      ]
      return fail(code, 'The request conflicts with stored data.', status)
    },
  },
]

export function handleError(
  error: unknown,
  scope = 'api',
): NextResponse<ApiErrorBody> {
  const rule = RULES.find(candidate => candidate.matches(error))
  if (rule) {
    return rule.respond(error as Error)
  }
  reportError(error, scope)
  return fail('INTERNAL_ERROR', 'Something went wrong.', 500)
}

export async function readJson(request: Request): Promise<unknown> {
  const text = await request.text()
  return text.length === 0 ? {} : JSON.parse(text)
}
