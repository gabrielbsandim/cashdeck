import { z } from 'zod'
import {
  billDetailViewSchema,
  billViewSchema,
  captureBillSchema,
} from '@cashdeck/application'

export const API_VERSION = 'v1'

const errorSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    details: z.unknown().optional(),
  }),
})

function schema(value: z.ZodType, io: 'input' | 'output' = 'output') {
  return z.toJSONSchema(value, {
    io,
    target: 'openapi-3.0',
    unrepresentable: 'any',
  })
}

function json(description: string, body: z.ZodType) {
  return {
    description,
    content: { 'application/json': { schema: schema(body) } },
  }
}

const errors = {
  '404': { $ref: '#/components/responses/Error' },
  '422': { $ref: '#/components/responses/Error' },
  '500': { $ref: '#/components/responses/Error' },
}

const billId = {
  name: 'id',
  in: 'path',
  required: true,
  schema: { type: 'string' },
}

export function buildOpenApiDocument() {
  return {
    openapi: '3.1.0',
    info: { title: 'Cashdeck API', version: API_VERSION },
    servers: [{ url: `/api/${API_VERSION}` }],
    paths: {
      '/health': {
        get: {
          operationId: 'getHealth',
          responses: {
            '200': json(
              'Service is up',
              z.object({ data: z.object({ status: z.literal('ok') }) }),
            ),
          },
        },
      },
      '/bills': {
        get: {
          operationId: 'listBills',
          parameters: ['entityId', 'status', 'cursor', 'limit'].map(name => ({
            name,
            in: 'query',
            required: false,
            schema: { type: 'string' },
          })),
          responses: {
            '200': json(
              'Bills by due date',
              z.object({
                data: z.array(billViewSchema),
                nextCursor: z.string().nullable(),
              }),
            ),
            ...errors,
          },
        },
        post: {
          operationId: 'captureBill',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: schema(captureBillSchema, 'input'),
              },
            },
          },
          responses: {
            '200': json(
              'Existing bill with the same code',
              z.object({ data: billViewSchema }),
            ),
            '201': json('Bill captured', z.object({ data: billViewSchema })),
            ...errors,
          },
        },
      },
      '/bills/{id}': {
        get: {
          operationId: 'getBill',
          parameters: [billId],
          responses: {
            '200': json(
              'Bill with its plan',
              z.object({ data: billDetailViewSchema }),
            ),
            ...errors,
          },
        },
      },
      '/bills/{id}/pay': {
        post: {
          operationId: 'payBill',
          parameters: [billId],
          requestBody: {
            content: {
              'application/json': {
                schema: schema(
                  z.object({ confirmed: z.boolean().optional() }),
                  'input',
                ),
              },
            },
          },
          responses: {
            '200': json('Ladder run', z.object({ data: billDetailViewSchema })),
            ...errors,
          },
        },
      },
      '/bills/{id}/mark-paid': {
        post: {
          operationId: 'markBillPaid',
          parameters: [billId],
          responses: {
            '200': json('Bill marked paid', z.object({ data: billViewSchema })),
            ...errors,
          },
        },
      },
    },
    components: {
      responses: { Error: json('Error envelope', errorSchema) },
    },
  }
}
