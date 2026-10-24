import { route } from '@/server/api/handler'
import { receiptCopy } from '@/server/api/receipt-copy'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'bills:receipt-pdf',
  async ({ request, tenantId, params, container }) => {
    const file = await container.documents.receiptPdf(
      tenantId,
      params.id,
      receiptCopy(request),
    )
    return fileResponse(file.bytes, 'application/pdf', file.fileName)
  },
)
