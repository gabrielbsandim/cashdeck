import { route } from '@/server/api/handler'
import { fileResponse } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route<{ id: string }>(
  'export:download',
  async ({ tenantId, params, container }) => {
    const archive = await container.accountantExport.download(
      tenantId,
      params.id,
    )
    return fileResponse(archive.bytes, 'application/zip', archive.fileName)
  },
)
