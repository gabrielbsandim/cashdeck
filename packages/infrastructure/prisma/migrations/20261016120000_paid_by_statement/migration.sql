-- A bill settled because the bank statement showed the debit.
ALTER TYPE "PaidBy" ADD VALUE IF NOT EXISTS 'STATEMENT';
