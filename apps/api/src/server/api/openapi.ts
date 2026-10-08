import { z } from 'zod'
import {
  accountViewSchema,
  attachmentViewSchema,
  automationViewSchema,
  billDetailViewSchema,
  billViewSchema,
  captureBillSchema,
  captureFileSchema,
  captureSourcesViewSchema,
  cardStatementViewSchema,
  companySummarySchema,
  connectionViewSchema,
  connectItemSchema,
  consolidatedSummarySchema,
  createAccountSchema,
  entityKindSchema,
  entityViewSchema,
  exportPeriodQuerySchema,
  exportPlanViewSchema,
  exportRecordViewSchema,
  generateExportSchema,
  importStatementSchema,
  invoiceViewSchema,
  issuerCertificateSchema,
  issuerSetupViewSchema,
  issuerTestViewSchema,
  itemLookupViewSchema,
  listAccountsQuerySchema,
  listBillsQuerySchema,
  listInvoicesQuerySchema,
  listRailsQuerySchema,
  listTransactionsQuerySchema,
  listTransfersQuerySchema,
  lookupItemSchema,
  payrollSheetViewSchema,
  personalSummarySchema,
  railCredentialsViewSchema,
  railTestViewSchema,
  railViewSchema,
  receiptViewSchema,
  recordTransferSchema,
  saveIssuerSchema,
  savePayrollSchema,
  saveRailCredentialsSchema,
  serviceCodeSchema,
  setDdaSchema,
  startMailboxSchema,
  statementBillSchema,
  statementBillViewSchema,
  syncResultSchema,
  transactionViewSchema,
  transferViewSchema,
  updateAccountSchema,
  updateAutomationSchema,
  uploadSchema,
} from '@cashdeck/application'
import { markPaidSchema, payBillSchema } from '@/server/api/schemas'

export const API_VERSION = 'v1'

type Method = 'get' | 'post' | 'put' | 'patch' | 'delete'

type Operation = {
  method: Method
  path: string
  id: string
  summary: string
  query?: z.ZodObject
  body?: z.ZodType
  status?: '200' | '201'
  response: z.ZodType | 'file' | 'redirect'
  page?: boolean
  public?: boolean
}

const errorSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    details: z.unknown().optional(),
  }),
})

const assistedInstructionsSchema = z.object({
  kind: z.string(),
  copyCode: z.string().nullable(),
  pixCode: z.string().nullable(),
  amountCents: z.int(),
  dueDate: z.string(),
})

const authCheckSchema = z.object({
  server: z.object({
    name: z.string(),
    version: z.string(),
    tenantId: z.string(),
  }),
  entities: z.array(
    entityViewSchema.pick({ id: true, kind: true, name: true }),
  ),
})

const idSchema = z.object({ id: z.string() })

const OPERATIONS: Operation[] = [
  {
    method: 'get',
    path: '/health',
    id: 'getHealth',
    summary: 'Service is up',
    response: z.object({ status: z.literal('ok') }),
    public: true,
  },
  {
    method: 'get',
    path: '/auth/check',
    id: 'checkAuth',
    summary: 'Token is valid; server name and entities',
    response: authCheckSchema,
  },
  {
    method: 'get',
    path: '/entities',
    id: 'listEntities',
    summary: 'Personal and company entities',
    response: z.array(entityViewSchema),
  },
  {
    method: 'get',
    path: '/home/personal',
    id: 'getPersonalSummary',
    summary: 'Personal home',
    response: personalSummarySchema,
  },
  {
    method: 'get',
    path: '/home/company',
    id: 'getCompanySummary',
    summary: 'Company home',
    response: companySummarySchema,
  },
  {
    method: 'post',
    path: '/home/company/drafts/{invoiceId}/approve',
    id: 'approveInvoiceDraft',
    summary: 'Issue a draft invoice; returns the refreshed company home',
    response: companySummarySchema,
  },
  {
    method: 'post',
    path: '/home/company/unbilled/{transactionId}/invoice',
    id: 'invoiceReceipt',
    summary: 'Issue an invoice for an unbilled receipt',
    response: companySummarySchema,
  },
  {
    method: 'get',
    path: '/home/consolidated',
    id: 'getConsolidatedSummary',
    summary: 'Personal and company together',
    response: consolidatedSummarySchema,
  },
  {
    method: 'get',
    path: '/accounts',
    id: 'listAccounts',
    summary: 'Accounts of an entity',
    query: listAccountsQuerySchema,
    response: z.array(accountViewSchema),
  },
  {
    method: 'post',
    path: '/accounts',
    id: 'createAccount',
    summary: 'Create a manual account',
    body: createAccountSchema,
    status: '201',
    response: accountViewSchema,
  },
  {
    method: 'patch',
    path: '/accounts/{id}',
    id: 'updateAccount',
    summary: 'Update an account',
    body: updateAccountSchema,
    response: accountViewSchema,
  },
  {
    method: 'get',
    path: '/transactions',
    id: 'listTransactions',
    summary: 'Transactions, newest first',
    query: listTransactionsQuerySchema,
    response: transactionViewSchema,
    page: true,
  },
  {
    method: 'get',
    path: '/transfers',
    id: 'listTransfers',
    summary: 'Transfers between the entities',
    query: listTransfersQuerySchema,
    response: z.array(transferViewSchema),
  },
  {
    method: 'post',
    path: '/transfers',
    id: 'recordTransfer',
    summary: 'Record a transfer between the entities',
    body: recordTransferSchema,
    status: '201',
    response: transferViewSchema,
  },
  {
    method: 'get',
    path: '/transfers/{id}',
    id: 'getTransfer',
    summary: 'One transfer',
    response: transferViewSchema,
  },
  {
    method: 'get',
    path: '/transfers/{id}/document',
    id: 'downloadTransferDocument',
    summary: 'Transfer statement as a PDF',
    response: 'file',
  },
  {
    method: 'get',
    path: '/bills',
    id: 'listBills',
    summary: 'Bills by due date',
    query: listBillsQuerySchema,
    response: billViewSchema,
    page: true,
  },
  {
    method: 'post',
    path: '/bills',
    id: 'captureBill',
    summary: 'Capture a bill; 200 when the same code already exists',
    body: captureBillSchema,
    status: '201',
    response: billViewSchema,
  },
  {
    method: 'get',
    path: '/bills/{id}',
    id: 'getBill',
    summary: 'Bill with its plan',
    response: billDetailViewSchema,
  },
  {
    method: 'post',
    path: '/bills/{id}/pay',
    id: 'payBill',
    summary: 'Run the payment ladder',
    body: payBillSchema,
    response: billDetailViewSchema.extend({
      instructions: assistedInstructionsSchema.nullable(),
    }),
  },
  {
    method: 'post',
    path: '/bills/{id}/mark-paid',
    id: 'markBillPaid',
    summary: 'Mark a bill paid by hand',
    body: markPaidSchema,
    response: billViewSchema,
  },
  {
    method: 'get',
    path: '/bills/{id}/receipt',
    id: 'getReceipt',
    summary: 'Payment receipt and attachments',
    response: receiptViewSchema,
  },
  {
    method: 'get',
    path: '/bills/{id}/receipt/pdf',
    id: 'downloadReceiptPdf',
    summary: 'Receipt of a paid bill as a PDF',
    response: 'file',
  },
  {
    method: 'post',
    path: '/bills/{id}/attachments',
    id: 'addAttachment',
    summary: 'Attach a file to a bill',
    body: uploadSchema,
    status: '201',
    response: attachmentViewSchema,
  },
  {
    method: 'get',
    path: '/bills/{id}/attachments/{attachmentId}',
    id: 'downloadAttachment',
    summary: 'Download an attachment',
    response: 'file',
  },
  {
    method: 'post',
    path: '/open-finance/lookup',
    id: 'lookupItem',
    summary: 'Look up an aggregator item',
    body: lookupItemSchema,
    response: itemLookupViewSchema,
  },
  {
    method: 'get',
    path: '/open-finance/connections',
    id: 'listConnections',
    summary: 'Open Finance connections',
    response: z.array(connectionViewSchema),
  },
  {
    method: 'post',
    path: '/open-finance/connections',
    id: 'connectItem',
    summary: 'Link an item and import its accounts',
    body: connectItemSchema,
    status: '201',
    response: z.object({ connectionId: z.string(), imported: z.int() }),
  },
  {
    method: 'delete',
    path: '/open-finance/connections/{id}',
    id: 'removeConnection',
    summary: 'Remove a connection; accounts become manual',
    response: idSchema,
  },
  {
    method: 'post',
    path: '/open-finance/connections/{id}/sync',
    id: 'syncConnection',
    summary: 'Sync a connection now',
    response: syncResultSchema,
  },
  {
    method: 'get',
    path: '/rails',
    id: 'listRails',
    summary: 'Payment rails of an entity',
    query: listRailsQuerySchema,
    response: z.array(railViewSchema),
  },
  {
    method: 'delete',
    path: '/rails/{id}',
    id: 'removeRail',
    summary: 'Remove rail credentials and disable it',
    response: idSchema,
  },
  {
    method: 'post',
    path: '/rails/{id}/authorize',
    id: 'authorizeRail',
    summary: 'Enable a configured rail',
    response: railViewSchema,
  },
  {
    method: 'get',
    path: '/rails/{id}/credentials',
    id: 'getRailCredentials',
    summary: 'Credential metadata, never the secrets',
    response: railCredentialsViewSchema,
  },
  {
    method: 'put',
    path: '/rails/{id}/credentials',
    id: 'saveRailCredentials',
    summary: 'Store rail credentials in the vault',
    body: saveRailCredentialsSchema,
    response: railCredentialsViewSchema,
  },
  {
    method: 'post',
    path: '/rails/{id}/test',
    id: 'testRail',
    summary: 'Check a rail against its provider',
    response: railTestViewSchema,
  },
  {
    method: 'get',
    path: '/automation',
    id: 'getAutomation',
    summary: 'Automation state',
    response: automationViewSchema,
  },
  {
    method: 'post',
    path: '/automation/pause',
    id: 'pauseAutomation',
    summary: 'Pause every automatic payment',
    response: automationViewSchema,
  },
  {
    method: 'post',
    path: '/automation/resume',
    id: 'resumeAutomation',
    summary: 'Resume automatic payments',
    response: automationViewSchema,
  },
  {
    method: 'patch',
    path: '/automation/settings',
    id: 'updateAutomation',
    summary: 'Tune limits of an entity',
    body: updateAutomationSchema,
    response: automationViewSchema,
  },
  {
    method: 'get',
    path: '/capture/sources',
    id: 'getCaptureSources',
    summary: 'Mailboxes and DDA enrollments',
    response: captureSourcesViewSchema,
  },
  {
    method: 'post',
    path: '/capture/mailboxes/oauth/start',
    id: 'startMailbox',
    summary: 'Authorization URL for a mailbox',
    body: startMailboxSchema,
    response: z.object({ url: z.string() }),
  },
  {
    method: 'get',
    path: '/capture/mailboxes/oauth/callback',
    id: 'completeMailbox',
    summary: 'OAuth redirect target; checked by the signed state',
    query: z.object({
      code: z.string().optional(),
      state: z.string().optional(),
    }),
    response: 'redirect',
    public: true,
  },
  {
    method: 'post',
    path: '/capture/files',
    id: 'captureFile',
    summary: 'Capture a bill from a shared PDF or photo; 200 when known',
    body: captureFileSchema,
    status: '201',
    response: billViewSchema,
  },
  {
    method: 'delete',
    path: '/capture/mailboxes/{id}',
    id: 'removeMailbox',
    summary: 'Disconnect a mailbox',
    response: captureSourcesViewSchema,
  },
  {
    method: 'post',
    path: '/capture/mailboxes/{id}/read',
    id: 'readMailbox',
    summary: 'Read a mailbox now',
    response: captureSourcesViewSchema,
  },
  {
    method: 'put',
    path: '/capture/dda/{entity}',
    id: 'setDda',
    summary: 'Enable or disable DDA for an entity',
    body: setDdaSchema,
    response: captureSourcesViewSchema,
  },
  {
    method: 'get',
    path: '/invoices',
    id: 'listInvoices',
    summary: 'Invoices of a month',
    query: listInvoicesQuerySchema,
    response: invoiceViewSchema,
    page: true,
  },
  {
    method: 'get',
    path: '/invoices/issuer',
    id: 'getIssuer',
    summary: 'Invoice issuer setup, null before the first save',
    response: issuerSetupViewSchema.nullable(),
  },
  {
    method: 'put',
    path: '/invoices/issuer',
    id: 'saveIssuer',
    summary: 'Save the invoice issuer setup',
    body: saveIssuerSchema,
    response: issuerSetupViewSchema,
  },
  {
    method: 'put',
    path: '/invoices/issuer/certificate',
    id: 'uploadIssuerCertificate',
    summary: 'Store the issuer certificate in the vault',
    body: issuerCertificateSchema,
    response: issuerSetupViewSchema,
  },
  {
    method: 'post',
    path: '/invoices/issuer/test',
    id: 'testIssuer',
    summary: 'Check the issuer against its provider',
    response: issuerTestViewSchema,
  },
  {
    method: 'get',
    path: '/invoices/service-codes',
    id: 'listServiceCodes',
    summary: 'Service codes the issuer accepts',
    response: z.array(serviceCodeSchema),
  },
  {
    method: 'get',
    path: '/payroll',
    id: 'getPayroll',
    summary: 'Payroll sheet and Fator R',
    response: payrollSheetViewSchema,
  },
  {
    method: 'put',
    path: '/payroll/{month}',
    id: 'savePayroll',
    summary: 'Save the payroll of a month',
    body: savePayrollSchema,
    response: payrollSheetViewSchema,
  },
  {
    method: 'post',
    path: '/card-statements',
    id: 'readCardStatement',
    summary: 'Read a card statement with the AI',
    body: importStatementSchema,
    status: '201',
    response: cardStatementViewSchema,
  },
  {
    method: 'get',
    path: '/card-statements/latest',
    id: 'getLatestCardStatement',
    summary: 'Latest statement without a bill, or null',
    response: cardStatementViewSchema.nullable(),
  },
  {
    method: 'get',
    path: '/card-statements/{id}',
    id: 'getCardStatement',
    summary: 'One card statement',
    response: cardStatementViewSchema,
  },
  {
    method: 'post',
    path: '/card-statements/{id}/bill',
    id: 'createStatementBill',
    summary: 'Bill the selected lines of a statement',
    body: statementBillSchema,
    status: '201',
    response: statementBillViewSchema,
  },
  {
    method: 'get',
    path: '/accountant-export/plan',
    id: 'planAccountantExport',
    summary: 'What an export of the period would hold',
    query: exportPeriodQuerySchema,
    response: exportPlanViewSchema,
  },
  {
    method: 'post',
    path: '/accountant-export',
    id: 'generateAccountantExport',
    summary: 'Record an export',
    body: generateExportSchema,
    status: '201',
    response: exportRecordViewSchema,
  },
  {
    method: 'get',
    path: '/accountant-export/history',
    id: 'listAccountantExports',
    summary: 'Past exports, newest first',
    response: z.array(exportRecordViewSchema),
  },
  {
    method: 'get',
    path: '/accountant-export/{id}/download',
    id: 'downloadAccountantExport',
    summary: 'ZIP with the CSVs and attachments',
    response: 'file',
  },
]

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

const ERROR = { $ref: '#/components/responses/Error' }
const ERRORS = Object.fromEntries(
  ['400', '401', '404', '409', '422', '500', '502', '503'].map(code => [
    code,
    ERROR,
  ]),
)

const FILE = {
  description: 'File download',
  content: {
    'application/octet-stream': {
      schema: { type: 'string', format: 'binary' },
    },
  },
}

const REDIRECT = {
  description: 'Redirect to the app with connected=1 or an error code',
}

function success(operation: Operation) {
  if (operation.response === 'file') {
    return FILE
  }
  if (operation.response === 'redirect') {
    return REDIRECT
  }
  const data = operation.page
    ? z.object({
        data: z.array(operation.response),
        nextCursor: z.string().nullable(),
      })
    : z.object({ data: operation.response })
  return json(operation.summary, data)
}

function parameters(operation: Operation) {
  const path = [...operation.path.matchAll(/\{(\w+)\}/g)].map(([, name]) => ({
    name,
    in: 'path',
    required: true,
    schema: name === 'entity' ? schema(entityKindSchema) : { type: 'string' },
  }))
  const shape = operation.query?.shape ?? {}
  const query = Object.entries(shape).map(([name, field]) => ({
    name,
    in: 'query',
    required: !(field as z.ZodType).safeParse(undefined).success,
    schema: schema(field as z.ZodType, 'input'),
  }))
  return [...path, ...query]
}

function describe(operation: Operation) {
  const status =
    operation.response === 'redirect' ? '302' : (operation.status ?? '200')
  return {
    operationId: operation.id,
    summary: operation.summary,
    ...(operation.public ? { security: [] } : {}),
    parameters: parameters(operation),
    ...(operation.body
      ? {
          requestBody: {
            required: true,
            content: {
              'application/json': { schema: schema(operation.body, 'input') },
            },
          },
        }
      : {}),
    responses: { [status]: success(operation), ...ERRORS },
  }
}

export function buildOpenApiDocument() {
  const paths: Record<string, Record<string, unknown>> = {}
  for (const operation of OPERATIONS) {
    paths[operation.path] = {
      ...paths[operation.path],
      [operation.method]: describe(operation),
    }
  }
  return {
    openapi: '3.1.0',
    info: { title: 'Cashdeck API', version: API_VERSION },
    servers: [{ url: `/api/${API_VERSION}` }],
    security: [{ bearer: [] }],
    paths,
    components: {
      securitySchemes: { bearer: { type: 'http', scheme: 'bearer' } },
      responses: { Error: json('Error envelope', errorSchema) },
    },
  }
}
