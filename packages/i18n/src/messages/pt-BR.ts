export const ptBR = {
  billKind: {
    BOLETO: 'Boleto',
    PIX_KEY: 'Pix por chave',
    PIX_QR: 'Pix copia e cola',
    TAX_BARCODE: 'Guia de imposto',
    DARF_NO_BARCODE: 'DARF sem código de barras',
  },
  billStatus: {
    OPEN: 'Em aberto',
    NEEDS_CONFIRMATION: 'Aguardando sua confirmação',
    PROCESSING: 'Processando',
    AWAITING_BANK_APPROVAL: 'Aguardando aprovação no banco',
    ASSISTED: 'Pague com o código',
    PAID: 'Paga',
    CANCELLED: 'Cancelada',
  },
  stepMode: {
    AUTOMATIC: 'Automático',
    BANK_APPROVAL: 'Aprovação no banco',
    ASSISTED: 'Assistido',
  },
  errors: {
    VALIDATION_ERROR: 'Confira os dados enviados.',
    NOT_FOUND: 'Não encontrado.',
    INVALID_TRANSITION: 'Essa ação não vale para o estado atual.',
    NOT_CONFIGURED: 'Integração ainda não configurada.',
    INTERNAL_ERROR: 'Algo deu errado. Tente de novo.',
  },
} as const
