-- AlterTable
ALTER TABLE "invoice_templates" ADD COLUMN     "billing" TEXT NOT NULL DEFAULT 'FIXED',
ADD COLUMN     "hours" DECIMAL(8,2);

-- CreateTable
CREATE TABLE "invoice_files" (
    "tenant_id" TEXT NOT NULL,
    "invoice_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "bytes" BYTEA NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "invoice_files_pkey" PRIMARY KEY ("tenant_id","invoice_id","kind")
);

-- CreateTable
CREATE TABLE "webhook_events" (
    "tenant_id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "event_id" TEXT NOT NULL,
    "received_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "webhook_events_pkey" PRIMARY KEY ("tenant_id","provider","event_id")
);

-- CreateIndex
CREATE INDEX "invoices_tenant_id_external_id_idx" ON "invoices"("tenant_id", "external_id");

-- CreateIndex
CREATE INDEX "webhook_events_received_at_idx" ON "webhook_events"("received_at");
