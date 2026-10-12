import { z } from 'zod'
import { moneyViewSchema } from '@/dtos/common'
import { fipeSchema } from '@/dtos/assets'
import { VEHICLE_TYPES } from '@/ports/investments'

const tableCode = z.string().regex(/^\d+$/, 'Expected a FIPE table code')

export const vehicleBrandsQuerySchema = z.object({
  type: z.enum(VEHICLE_TYPES),
})

export const vehicleYearsQuerySchema = vehicleBrandsQuerySchema.extend({
  brand: tableCode,
})

export const vehicleModelsQuerySchema = vehicleYearsQuerySchema.extend({
  modelYear: z.coerce.number().int().min(1950).max(2100),
})

export const vehiclePriceQuerySchema = vehicleYearsQuerySchema.extend({
  // A model year by fuel, as a model option carries it.
  year: z.string().regex(/^\d{4}-\d+$/, 'Expected a year code like 2020-5'),
  model: tableCode,
})

const optionSchema = z.object({ code: z.string(), name: z.string() })

export const vehicleOptionsViewSchema = z.object({
  items: z.array(optionSchema),
})

export const vehicleModelsViewSchema = z.object({
  items: z.array(optionSchema.extend({ year: z.string() })),
})

export const vehiclePriceViewSchema = z.object({
  fipe: fipeSchema,
  model: z.string(),
  price: moneyViewSchema,
})

export type VehicleBrandsQuery = z.infer<typeof vehicleBrandsQuerySchema>
export type VehicleYearsQuery = z.infer<typeof vehicleYearsQuerySchema>
export type VehicleModelsQuery = z.infer<typeof vehicleModelsQuerySchema>
export type VehiclePriceQuery = z.infer<typeof vehiclePriceQuerySchema>
export type VehicleOptionsView = z.infer<typeof vehicleOptionsViewSchema>
export type VehicleModelsView = z.infer<typeof vehicleModelsViewSchema>
export type VehiclePriceView = z.infer<typeof vehiclePriceViewSchema>
