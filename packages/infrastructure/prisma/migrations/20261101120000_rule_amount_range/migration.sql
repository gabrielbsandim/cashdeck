-- One payee can send a shared subscription and a large reimbursement.
ALTER TABLE "category_rules" ADD COLUMN "min_cents" INTEGER, ADD COLUMN "max_cents" INTEGER;
