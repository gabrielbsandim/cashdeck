import { z } from 'zod'

export const householdMemberSchema = z.object({
  name: z.string().trim().min(1).max(80),
  taxId: z.string().trim().min(11).max(14),
})

export const householdSchema = z.object({
  members: z.array(householdMemberSchema).max(10),
})

export type HouseholdInput = z.infer<typeof householdSchema>

export const householdViewSchema = householdSchema

export type HouseholdView = z.infer<typeof householdViewSchema>
