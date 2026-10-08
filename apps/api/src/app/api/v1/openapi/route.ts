import { NextResponse } from 'next/server'
import { buildOpenApiDocument } from '@/server/api/openapi'

export function GET() {
  return NextResponse.json(buildOpenApiDocument())
}
