import { vehicleYearsQuerySchema } from '@cashdeck/application'
import { route, searchParams } from '@/server/api/handler'
import { ok } from '@/server/api/respond'

export const dynamic = 'force-dynamic'

export const GET = route('vehicles:years', async ({ request, container }) =>
  ok(
    await container.vehicles.years(
      vehicleYearsQuerySchema.parse(searchParams(request)),
    ),
  ),
)
