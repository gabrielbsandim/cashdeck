import { z } from 'zod'
import {
  isoDate,
  isoMonth,
  moneyViewSchema,
  pageQuerySchema,
  uploadSchema,
} from '@/dtos/common'
import { INVOICE_STATUSES } from '@/ports/records'

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
