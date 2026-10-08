import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'bills:receipt-pdf',
  async ({ tenantId, params, container }) => {
    const file = await container.documents.receiptPdf(tenantId, params.id)
    return fileResponse(file.bytes, 'application/pdf', file.fileName)
  },
)
