import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'transfers:document',
  async ({ tenantId, params, container }) => {
    const file = await container.documents.transferPdf(tenantId, params.id)
    return fileResponse(file.bytes, 'application/pdf', file.fileName)
  },
)
