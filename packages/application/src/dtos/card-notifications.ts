import { z } from 'zod'

export const captureNotificationsSchema = z.object({
  accountId: z.string().min(1),
  notifications: z
    .array(
      z.object({
        id: z.string().regex(/^[A-Za-z0-9_-]{8,128}$/),
        app: z.string().trim().min(1).max(200),
        title: z.string().max(500),
        text: z.string().max(2000),
        postedAt: z.iso.datetime({ offset: true }),
      }),
    )
    .min(1)
    .max(50),
})

export type CaptureNotificationsInput = z.infer<
  typeof captureNotificationsSchema
>

export const capturedNotificationsViewSchema = z.object({
  received: z.int(),
  added: z.int(),
})

export type CapturedNotificationsView = z.infer<
  typeof capturedNotificationsViewSchema
>

// What the AI returns when it reads card notifications.
export const notificationReadingSchema = z.object({
  items: z.array(
    z.object({
      ref: z.string(),
      kind: z.enum(['PURCHASE', 'REFUND', 'OTHER']),
      amount: z.number().nonnegative(),
      merchant: z.string(),
      installments: z.int().min(1).max(48),
    }),
  ),
})
