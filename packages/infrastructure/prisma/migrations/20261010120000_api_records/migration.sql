-- DropIndex
DROP INDEX "institutions_tenant_id_idx";

-- AlterTable
ALTER TABLE "connections" ADD COLUMN     "entity_id" TEXT NOT NULL;

-- AlterTable
ALTER TABLE "accounts" ADD COLUMN     "cdi_percent" INTEGER;

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "invoice_id" TEXT;

-- AlterTable
ALTER TABLE "invoices" ADD COLUMN     "description" TEXT NOT NULL DEFAULT '',
ADD COLUMN     "issue_on" DATE NOT NULL DEFAULT CURRENT_DATE,
ADD COLUMN     "service_code" TEXT NOT NULL DEFAULT '';

-- CreateTable
CREATE TABLE "internal_transfers" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,
    "rail" TEXT NOT NULL,
    "from_account_id" TEXT NOT NULL,
    "to_account_id" TEXT NOT NULL,
    "document" TEXT,

    CONSTRAINT "internal_transfers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bill_attachments" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "bill_id" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "bytes" BYTEA NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "bill_attachments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "documents" (
    "tenant_id" TEXT NOT NULL,
    "collection" TEXT NOT NULL,
    "id" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "documents_pkey" PRIMARY KEY ("tenant_id","collection","id")
);

-- CreateIndex
CREATE INDEX "internal_transfers_tenant_id_at_idx" ON "internal_transfers"("tenant_id", "at");

-- CreateIndex
CREATE INDEX "bill_attachments_tenant_id_bill_id_idx" ON "bill_attachments"("tenant_id", "bill_id");

-- CreateIndex
CREATE UNIQUE INDEX "institutions_tenant_id_name_key" ON "institutions"("tenant_id", "name");

