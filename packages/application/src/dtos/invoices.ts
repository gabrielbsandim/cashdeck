import { z } from 'zod'
import {
  isoDate,
  isoMonth,
  moneyViewSchema,
  pageQuerySchema,
  uploadSchema,
} from '@/dtos/common'
import { INVOICE_STATUSES, TEMPLATE_BILLING } from '@/ports/records'

export const ISSUER_KINDS = ['NATIONAL', 'MUNICIPAL'] as const
export const CERTIFICATE_STATES = ['VALID', 'EXPIRING_SOON', 'EXPIRED'] as const

export const serviceCodeSchema = z.object({
  code: z.string(),
  description: z.string(),
})

export const issuerSetupViewSchema = z.object({
  kind: z.enum(ISSUER_KINDS),
  city: z.string(),
  certificateName: z.string().nullable(),
  certificateExpiresOn: isoDate.nullable(),
  certificateState: z.enum(CERTIFICATE_STATES).nullable(),
  municipalRegistration: z.string(),
  serviceCode: serviceCodeSchema,
})

export type IssuerSetupView = z.infer<typeof issuerSetupViewSchema>

export const saveIssuerSchema = z.object({
  kind: z.enum(ISSUER_KINDS),
  city: z.string().trim().min(1).max(80),
  municipalRegistration: z.string().trim().min(1).max(40),
  serviceCode: z.string().trim().min(1).max(10),
})

export const issuerCertificateSchema = uploadSchema.extend({
  password: z.string().min(1).max(200),
  expiresOn: isoDate,
})

export const issuerTestViewSchema = z.object({
  protocol: z.string(),
  elapsedMs: z.int(),
})

export const invoiceViewSchema = z.object({
  id: z.string(),
  client: z.string(),
  amount: moneyViewSchema,
  status: z.enum(INVOICE_STATUSES),
  number: z.string().nullable(),
  competence: isoMonth,
  issueOn: isoDate,
  recurring: z.boolean(),
  isExport: z.boolean(),
  pdfUrl: z.string().nullable(),
})

export type InvoiceView = z.infer<typeof invoiceViewSchema>

export const listInvoicesQuerySchema = pageQuerySchema.extend({
  status: z.enum(INVOICE_STATUSES).optional(),
  month: isoMonth.optional(),
})

// Notaas accepts a cancellation reason of 15 to 255 characters.
export const cancelInvoiceSchema = z.object({
  reason: z.string().trim().min(15).max(255),
})

export const templateClientSchema = z.object({
  name: z.string().trim().min(1).max(120),
  taxId: z.string().trim().min(1).max(40).nullable().optional(),
  country: z
    .string()
    .regex(/^[A-Z]{2}$/, 'Expected an ISO country code')
    .optional(),
})

const templateFields = {
  client: templateClientSchema,
  description: z.string().trim().min(1).max(500),
  serviceCode: z.string().trim().min(1).max(10),
  amountCents: z.int().positive(),
  currency: z.string().regex(/^[A-Z]{3}$/, 'Expected an ISO currency code'),
  billing: z.enum(TEMPLATE_BILLING),
  hours: z.number().positive().max(744).nullable(),
  dayOfMonth: z.int().min(1).max(31),
  active: z.boolean(),
}

export const createInvoiceTemplateSchema = z.object({
  ...templateFields,
  currency: templateFields.currency.default('BRL'),
  billing: templateFields.billing.default('FIXED'),
  hours: templateFields.hours.default(null),
  active: templateFields.active.default(true),
})

export const updateInvoiceTemplateSchema = z.object(templateFields).partial()

export const invoiceTemplateViewSchema = z.object({
  id: z.string(),
  client: z.object({
    id: z.string(),
    name: z.string(),
    taxId: z.string().nullable(),
    country: z.string(),
  }),
  description: z.string(),
  serviceCode: z.string(),
  amount: moneyViewSchema,
  billing: z.enum(TEMPLATE_BILLING),
  hours: z.number().nullable(),
  cycleAmount: moneyViewSchema,
  dayOfMonth: z.int(),
  active: z.boolean(),
})

export type InvoiceTemplateView = z.infer<typeof invoiceTemplateViewSchema>
