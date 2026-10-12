import { vehicleModelsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('vehicles:models', async ({ request, container }) =>
  ok(
    await container.vehicles.models(
      vehicleModelsQuerySchema.parse(searchParams(request)),
    ),
  ),
)
