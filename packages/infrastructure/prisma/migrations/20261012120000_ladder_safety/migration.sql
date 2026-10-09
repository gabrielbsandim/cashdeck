-- CreateEnum
CREATE TYPE "FundingStatus" AS ENUM ('IN_FLIGHT', 'SUBMITTED', 'PAID', 'NOT_NEEDED', 'FAILED');

-- AlterEnum
ALTER TYPE "AttemptOutcome" ADD VALUE 'IN_FLIGHT';

-- AlterTable
ALTER TABLE "payment_settings" ADD COLUMN     "approval_cutoff" TEXT NOT NULL DEFAULT '16:00',
ADD COLUMN     "entity_daily_cap_cents" BIGINT DEFAULT 1000000,
ADD COLUMN     "max_deviation_percent" INTEGER DEFAULT 30,
ADD COLUMN     "payment_cap_cents" BIGINT DEFAULT 500000;

-- AlterTable
ALTER TABLE "audit_events" ADD COLUMN     "actor_id" TEXT,
ADD COLUMN     "request_id" TEXT;

-- CreateTable
CREATE TABLE "reserve_fundings" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "round" INTEGER NOT NULL,
    "bill_ids" TEXT[],
    "bills_total_cents" BIGINT NOT NULL,
    "available_cents" BIGINT,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',
    "status" "FundingStatus" NOT NULL,
    "reason" TEXT,
    "external_id" TEXT,
    "idempotency_key" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "reserve_fundings_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "reserve_fundings_tenant_id_entity_id_day_round_key" ON "reserve_fundings"("tenant_id", "entity_id", "day", "round");

-- CreateIndex
CREATE UNIQUE INDEX "reserve_fundings_tenant_id_idempotency_key_key" ON "reserve_fundings"("tenant_id", "idempotency_key");

-- CreateIndex
CREATE INDEX "payment_attempts_tenant_id_idempotency_key_idx" ON "payment_attempts"("tenant_id", "idempotency_key");
