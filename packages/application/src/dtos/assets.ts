import { z } from 'zod'
import { ASSET_KINDS } from '@cashdeck/domain'
import { entityKindSchema, isoDate, moneyViewSchema } from '@/dtos/common'
import { VEHICLE_TYPES } from '@/ports/investments'

export const fipeSchema = z.object({
  type: z.enum(VEHICLE_TYPES),
  code: z.string().regex(/^\d{6}-\d$/, 'Expected a FIPE code like 005340-6'),
  modelYear: z.int().min(1950).max(2100),
})

// The tenant pays the rent plus the lines of the building's bill whose
// description holds a pass-through word, like the gas they used.
export const rentalSchema = z.object({
  rent: z.int().positive(),
  passThrough: z.array(z.string().trim().min(1).max(40)).max(10).default([]),
  billFrom: z.string().trim().min(1).max(80),
})

// Amounts in cents. A vehicle with a FIPE code is priced by the table.
export const createAssetSchema = z
  .object({
    entity: entityKindSchema.default('PF'),
    kind: z.enum(ASSET_KINDS),
    name: z.string().trim().min(1).max(80).optional(),
    acquiredOn: isoDate,
    value: z.int().positive().optional(),
    fipe: fipeSchema.optional(),
    loanId: z.string().min(1).nullable().default(null),
    rental: rentalSchema.nullable().default(null),
  })
  .refine(input => input.value !== undefined || input.fipe !== undefined, {
    message: 'Give a value or a FIPE code.',
    path: ['value'],
  })
  .refine(input => input.fipe === undefined || input.kind === 'VEHICLE', {
    message: 'Only a vehicle has a FIPE code.',
    path: ['fipe'],
  })
  .refine(input => input.name !== undefined || input.fipe !== undefined, {
    message: 'Name the asset.',
    path: ['name'],
  })

export const updateAssetSchema = z.object({
  name: z.string().trim().min(1).max(80).optional(),
  acquiredOn: isoDate.optional(),
  // Another model reprices the vehicle from the table; null stops the table.
  fipe: fipeSchema.nullable().optional(),
  value: z.int().positive().optional(),
  // The day the new value holds from; today when left out.
  valuedOn: isoDate.optional(),
  loanId: z.string().min(1).nullable().optional(),
  soldOn: isoDate.nullable().optional(),
  // Null stops renting it out.
  rental: rentalSchema.nullable().optional(),
})

const billLineViewSchema = z.object({
  description: z.string(),
  amount: moneyViewSchema,
})

// The latest bill of the building: what to ask the tenant for and what the
// month leaves once the loan installment and the owner's share are paid.
const rentChargeViewSchema = z.object({
  billId: z.string(),
  dueDate: isoDate,
  billTotal: moneyViewSchema,
  passedOn: z.array(billLineViewSchema),
  total: moneyViewSchema,
  ownerCost: moneyViewSchema,
  // The bill's document, to send to the tenant.
  attachmentId: z.string().nullable(),
  installment: moneyViewSchema.nullable(),
  result: moneyViewSchema,
})

const rentalViewSchema = z.object({
  rent: moneyViewSchema,
  passThrough: z.array(z.string()),
  billFrom: z.string(),
  charge: rentChargeViewSchema.nullable(),
})

const changeSchema = z.object({
  amount: moneyViewSchema,
  percent: z.number().nullable(),
})

export const assetViewSchema = z.object({
  id: z.string(),
  entity: entityKindSchema,
  kind: z.enum(ASSET_KINDS),
  name: z.string(),
  acquiredOn: isoDate,
  soldOn: isoDate.nullable(),
  value: moneyViewSchema,
  valuedOn: isoDate,
  // Since the first value known.
  change: changeSchema,
  fipe: fipeSchema.nullable(),
  loan: z
    .object({ id: z.string(), name: z.string(), balance: moneyViewSchema })
    .nullable(),
  // The value less what the linked loan still owes.
  equity: moneyViewSchema,
  rental: rentalViewSchema.nullable(),
})

export const assetsViewSchema = z.object({
  items: z.array(assetViewSchema),
  value: moneyViewSchema,
  loanDebt: moneyViewSchema,
  equity: moneyViewSchema,
})

export type CreateAssetInput = z.infer<typeof createAssetSchema>
export type UpdateAssetInput = z.infer<typeof updateAssetSchema>
export type AssetView = z.infer<typeof assetViewSchema>
export type RentalView = z.infer<typeof rentalViewSchema>
export type AssetsView = z.infer<typeof assetsViewSchema>
