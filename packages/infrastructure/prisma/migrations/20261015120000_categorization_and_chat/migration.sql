-- CreateEnum
CREATE TYPE "CategorizedBy" AS ENUM ('RULE', 'AI', 'USER');

-- AlterTable
ALTER TABLE "transactions" ADD COLUMN     "categorized_by" "CategorizedBy",
ADD COLUMN     "category_confidence" DOUBLE PRECISION;

-- AlterTable
ALTER TABLE "categories" ADD COLUMN     "key" TEXT;

-- AlterTable
ALTER TABLE "category_rules" ADD COLUMN     "entity_id" TEXT,
ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "chat_threads" ADD COLUMN     "scope" TEXT NOT NULL DEFAULT 'ALL',
ADD COLUMN     "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- AlterTable
ALTER TABLE "chat_messages" ADD COLUMN     "notice" TEXT;

-- CreateTable
CREATE TABLE "chat_attachments" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "thread_id" TEXT NOT NULL,
    "message_id" TEXT NOT NULL,
    "file_name" TEXT NOT NULL,
    "mime_type" TEXT NOT NULL,
    "size" INTEGER NOT NULL,
    "bytes" BYTEA NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "chat_attachments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chat_actions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "thread_id" TEXT NOT NULL,
    "message_id" TEXT NOT NULL,
    "tool" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "entity" "EntityKind",
    "needs_entity" BOOLEAN NOT NULL DEFAULT false,
    "target" JSONB NOT NULL DEFAULT '{}',
    "details" JSONB NOT NULL DEFAULT '{}',
    "result" JSONB,
    "error" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL,
    "resolved_at" TIMESTAMP(3),

    CONSTRAINT "chat_actions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "transactions_tenant_id_category_id_idx" ON "transactions"("tenant_id", "category_id");

-- CreateIndex
CREATE INDEX "chat_threads_tenant_id_updated_at_idx" ON "chat_threads"("tenant_id", "updated_at");

-- CreateIndex
CREATE INDEX "chat_attachments_tenant_id_thread_id_idx" ON "chat_attachments"("tenant_id", "thread_id");

-- CreateIndex
CREATE INDEX "chat_actions_tenant_id_thread_id_idx" ON "chat_actions"("tenant_id", "thread_id");
