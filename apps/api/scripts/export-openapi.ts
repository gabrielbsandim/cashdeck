import { writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { buildOpenApiDocument } from '../src/server/api/openapi'

const target = fileURLToPath(
  new URL('../../../packages/client/openapi.json', import.meta.url),
)
writeFileSync(target, `${JSON.stringify(buildOpenApiDocument(), null, 2)}\n`)
console.log(`OpenAPI written to ${target}`)
