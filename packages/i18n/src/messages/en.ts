import { type Messages } from './types'

export const en: Messages = {
  billKind: {
    BOLETO: 'Boleto',
    PIX_KEY: 'Pix to a key',
    PIX_QR: 'Pix copy and paste',
    TAX_BARCODE: 'Tax guide',
    DARF_NO_BARCODE: 'DARF without barcode',
  },
  billStatus: {
    OPEN: 'Open',
    NEEDS_CONFIRMATION: 'Waiting for your confirmation',
    PROCESSING: 'Processing',
    AWAITING_BANK_APPROVAL: 'Waiting for approval in the bank',
    ASSISTED: 'Pay with the code',
    PAID: 'Paid',
    CANCELLED: 'Cancelled',
  },
  stepMode: {
    AUTOMATIC: 'Automatic',
    BANK_APPROVAL: 'Approval in the bank',
    ASSISTED: 'Assisted',
  },
  errors: {
    VALIDATION_ERROR: 'Check the data you sent.',
    NOT_FOUND: 'Not found.',
    INVALID_TRANSITION: 'That action does not apply to the current state.',
    NOT_CONFIGURED: 'Integration not configured yet.',
    INTERNAL_ERROR: 'Something went wrong. Try again.',
  },
}
