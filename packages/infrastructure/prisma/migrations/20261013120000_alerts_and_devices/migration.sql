-- AlterTable
ALTER TABLE "alerts" ADD COLUMN     "entity_id" TEXT,
ADD COLUMN     "bill_id" TEXT,
ADD COLUMN     "invoice_id" TEXT,
ADD COLUMN     "dedupe_key" TEXT;

-- CreateTable
CREATE TABLE "device_tokens" (
    "token" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "device_tokens_pkey" PRIMARY KEY ("token")
);

-- CreateIndex
CREATE UNIQUE INDEX "alerts_tenant_id_dedupe_key_key" ON "alerts"("tenant_id", "dedupe_key");

-- CreateIndex
CREATE INDEX "alerts_tenant_id_read_at_idx" ON "alerts"("tenant_id", "read_at");

-- CreateIndex
CREATE INDEX "device_tokens_tenant_id_idx" ON "device_tokens"("tenant_id");
