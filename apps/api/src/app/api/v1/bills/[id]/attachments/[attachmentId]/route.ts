import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string; attachmentId: string }>(
  'bills:attachment',
  async ({ tenantId, params, container }) => {
    const file = await container.receipts.attachment(
      tenantId,
      params.id,
      params.attachmentId,
    )
    return fileResponse(file.bytes, file.mimeType, file.fileName)
  },
)
