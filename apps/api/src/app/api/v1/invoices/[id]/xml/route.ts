import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'invoices:xml',
  async ({ tenantId, params, container }) => {
    const file = await container.invoiceLifecycle.file(
      tenantId,
      params.id,
      'XML',
    )
    return fileResponse(file.bytes, file.mimeType, file.fileName)
  },
)
