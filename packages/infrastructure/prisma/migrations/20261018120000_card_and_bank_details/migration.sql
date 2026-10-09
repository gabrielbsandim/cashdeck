-- Bank logos, card credit lines, installments and the card bill history.
ALTER TABLE "institutions"
  ADD COLUMN "connector_id" INTEGER,
  ADD COLUMN "image_url" TEXT,
  ADD COLUMN "primary_color" TEXT;

ALTER TABLE "accounts"
  ADD COLUMN "number_suffix" TEXT,
  ADD COLUMN "credit_limit_cents" BIGINT,
  ADD COLUMN "credit_available_cents" BIGINT,
  ADD COLUMN "credit_closes_on" DATE,
  ADD COLUMN "credit_due_on" DATE,
  ADD COLUMN "credit_brand" TEXT;

ALTER TABLE "transactions"
  ADD COLUMN "merchant" TEXT,
  ADD COLUMN "installment_number" INTEGER,
  ADD COLUMN "installment_count" INTEGER,
  ADD COLUMN "purchase_on" DATE;

-- Some issuers report no closing date, so a bill is keyed by its due date.
DROP INDEX "credit_card_bills_tenant_id_account_id_closing_date_key";
ALTER TABLE "credit_card_bills"
  ALTER COLUMN "closing_date" DROP NOT NULL,
  ALTER COLUMN "status" SET DEFAULT 'CLOSED',
  ADD COLUMN "external_id" TEXT,
  ADD COLUMN "minimum_cents" BIGINT,
  ADD COLUMN "currency" CHAR(3) NOT NULL DEFAULT 'BRL';
CREATE UNIQUE INDEX "credit_card_bills_tenant_id_account_id_due_date_key" ON "credit_card_bills"("tenant_id", "account_id", "due_date");
