import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'invoices:pdf',
  async ({ tenantId, params, container }) => {
    const file = await container.invoiceLifecycle.file(
      tenantId,
      params.id,
      'PDF',
    )
    return fileResponse(file.bytes, file.mimeType, file.fileName)
  },
)
