-- pgvector backs the chat memory embeddings.
CREATE EXTENSION IF NOT EXISTS vector;

-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "EntityKind" AS ENUM ('PF', 'PJ');

-- CreateEnum
CREATE TYPE "TaxRegime" AS ENUM ('SIMPLES_NACIONAL', 'MEI', 'LUCRO_PRESUMIDO', 'LUCRO_REAL');

-- CreateEnum
CREATE TYPE "AccountType" AS ENUM ('CHECKING', 'SAVINGS', 'CREDIT_CARD', 'INVESTMENT', 'WALLET');

-- CreateEnum
CREATE TYPE "AccountOrigin" AS ENUM ('CONNECTED', 'MANUAL');

-- CreateEnum
CREATE TYPE "BillKind" AS ENUM ('BOLETO', 'PIX_KEY', 'PIX_QR', 'TAX_BARCODE', 'DARF_NO_BARCODE');

-- CreateEnum
CREATE TYPE "BillStatus" AS ENUM ('OPEN', 'NEEDS_CONFIRMATION', 'PROCESSING', 'AWAITING_BANK_APPROVAL', 'ASSISTED', 'PAID', 'CANCELLED');

-- CreateEnum
CREATE TYPE "BillSource" AS ENUM ('GMAIL', 'SHARE', 'CAMERA', 'CHAT', 'DDA', 'MANUAL');

-- CreateEnum
CREATE TYPE "PaidBy" AS ENUM ('RAIL', 'USER');

-- CreateEnum
CREATE TYPE "RailId" AS ENUM ('MERCADO_PAGO_PAYOUTS', 'ASAAS', 'INTER_EMPRESAS', 'C6_EMPRESAS', 'ASSISTED');

-- CreateEnum
CREATE TYPE "StepMode" AS ENUM ('AUTOMATIC', 'BANK_APPROVAL', 'ASSISTED');

-- CreateEnum
CREATE TYPE "AttemptOutcome" AS ENUM ('PAID', 'SUBMITTED', 'PENDING_APPROVAL', 'ASSISTED', 'FAILED');

-- CreateEnum
CREATE TYPE "InvoiceStatus" AS ENUM ('DRAFT', 'PROCESSING', 'ISSUED', 'REJECTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "CardBillStatus" AS ENUM ('OPEN', 'CLOSED', 'PAID');

-- CreateTable
CREATE TABLE "tenants" (
    "id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "tenants_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT,
    "locale" TEXT NOT NULL DEFAULT 'pt-BR',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "financial_entities" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "kind" "EntityKind" NOT NULL,
    "name" TEXT NOT NULL,
    "tax_id" TEXT NOT NULL,
    "tax_regime" "TaxRegime",
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "financial_entities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "institutions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT,
    "manual" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "institutions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "connections" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "institution_id" TEXT NOT NULL,
    "provider" TEXT NOT NULL,
    "item_id" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "last_sync_at" TIMESTAMP(3),

    CONSTRAINT "connections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "accounts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "institution_id" TEXT NOT NULL,
    "connection_id" TEXT,
    "external_id" TEXT,
    "name" TEXT NOT NULL,
    "type" "AccountType" NOT NULL,
    "origin" "AccountOrigin" NOT NULL,
    "is_reserve" BOOLEAN NOT NULL DEFAULT false,
    "balance_cents" BIGINT NOT NULL DEFAULT 0,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',

    CONSTRAINT "accounts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "transactions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "account_id" TEXT NOT NULL,
    "external_id" TEXT,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL,
    "booked_on" DATE NOT NULL,
    "description" TEXT NOT NULL,
    "category_id" TEXT,
    "transfer_group_id" TEXT,
    "note" TEXT,

    CONSTRAINT "transactions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "categories" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "parent_id" TEXT,
    "icon" TEXT,

    CONSTRAINT "categories_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "category_rules" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "pattern" TEXT NOT NULL,
    "category_id" TEXT NOT NULL,
    "priority" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "category_rules_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "budgets" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "category_id" TEXT NOT NULL,
    "month" CHAR(7) NOT NULL,
    "limit_cents" BIGINT NOT NULL,
    "rollover" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "budgets_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "recurrences" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "day_of_month" INTEGER NOT NULL,
    "confirmed" BOOLEAN NOT NULL DEFAULT false,
    "last_seen_on" DATE,

    CONSTRAINT "recurrences_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "credit_card_bills" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "account_id" TEXT NOT NULL,
    "closing_date" DATE NOT NULL,
    "due_date" DATE NOT NULL,
    "total_cents" BIGINT NOT NULL,
    "status" "CardBillStatus" NOT NULL,

    CONSTRAINT "credit_card_bills_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "holdings" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "account_id" TEXT NOT NULL,
    "ticker" TEXT,
    "name" TEXT NOT NULL,
    "quantity" DECIMAL(20,8) NOT NULL,
    "value_cents" BIGINT NOT NULL,
    "as_of" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "holdings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "goals" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "target_cents" BIGINT NOT NULL,
    "deadline" DATE,
    "account_id" TEXT,

    CONSTRAINT "goals_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "bills" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "kind" "BillKind" NOT NULL,
    "status" "BillStatus" NOT NULL,
    "source" "BillSource" NOT NULL,
    "payee" TEXT,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',
    "due_date" DATE NOT NULL,
    "code" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL,
    "paid_at" TIMESTAMP(3),
    "paid_by" "PaidBy",

    CONSTRAINT "bills_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payment_plans" (
    "bill_id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "steps" JSONB NOT NULL,
    "current_step" INTEGER NOT NULL,

    CONSTRAINT "payment_plans_pkey" PRIMARY KEY ("bill_id")
);

-- CreateTable
CREATE TABLE "payment_attempts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "bill_id" TEXT NOT NULL,
    "step_index" INTEGER NOT NULL,
    "rail" "RailId" NOT NULL,
    "mode" "StepMode" NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "outcome" "AttemptOutcome" NOT NULL,
    "reason" TEXT,
    "external_id" TEXT,
    "idempotency_key" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "payment_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "payees" (
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "first_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payees_pkey" PRIMARY KEY ("tenant_id","entity_id","key")
);

-- CreateTable
CREATE TABLE "payment_settings" (
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "kill_switch" BOOLEAN NOT NULL DEFAULT false,
    "enabled_rails" "RailId"[],
    "daily_cap_cents" JSONB NOT NULL DEFAULT '{}',
    "confirm_above_cents" BIGINT,

    CONSTRAINT "payment_settings_pkey" PRIMARY KEY ("tenant_id","entity_id")
);

-- CreateTable
CREATE TABLE "invoice_clients" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "tax_id" TEXT,
    "country" CHAR(2) NOT NULL DEFAULT 'BR',
    "email" TEXT,

    CONSTRAINT "invoice_clients_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoice_templates" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "client_id" TEXT NOT NULL,
    "service_code" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL,
    "day_of_month" INTEGER NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,

    CONSTRAINT "invoice_templates_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "invoices" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "client_id" TEXT NOT NULL,
    "template_id" TEXT,
    "issuer" TEXT NOT NULL,
    "external_id" TEXT,
    "number" TEXT,
    "status" "InvoiceStatus" NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "currency" CHAR(3) NOT NULL,
    "fx_rate" DECIMAL(18,8),
    "is_export" BOOLEAN NOT NULL DEFAULT false,
    "competence" CHAR(7) NOT NULL,
    "pdf_url" TEXT,
    "xml_url" TEXT,
    "cancel_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "invoices_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "tax_guides" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "competence" CHAR(7) NOT NULL,
    "due_date" DATE NOT NULL,
    "bill_id" TEXT,

    CONSTRAINT "tax_guides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alerts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "data" JSONB NOT NULL DEFAULT '{}',
    "read_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_events" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "actor" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "subject_id" TEXT NOT NULL,
    "rail" "RailId",
    "result" TEXT NOT NULL,
    "details" JSONB NOT NULL DEFAULT '{}',
    "at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "idempotency_records" (
    "tenant_id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "result" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "idempotency_records_pkey" PRIMARY KEY ("tenant_id","key")
);

-- CreateTable
CREATE TABLE "secrets" (
    "tenant_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "sealed" TEXT NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "secrets_pkey" PRIMARY KEY ("tenant_id","name")
);

-- CreateTable
CREATE TABLE "chat_threads" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "title" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_threads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chat_messages" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "thread_id" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "tool_calls" JSONB,
    "embedding" vector(768),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_tenant_id_email_key" ON "users"("tenant_id", "email");

-- CreateIndex
CREATE UNIQUE INDEX "financial_entities_tenant_id_tax_id_key" ON "financial_entities"("tenant_id", "tax_id");

-- CreateIndex
CREATE INDEX "institutions_tenant_id_idx" ON "institutions"("tenant_id");

-- CreateIndex
CREATE UNIQUE INDEX "connections_tenant_id_provider_item_id_key" ON "connections"("tenant_id", "provider", "item_id");

-- CreateIndex
CREATE INDEX "accounts_tenant_id_entity_id_idx" ON "accounts"("tenant_id", "entity_id");

-- CreateIndex
CREATE INDEX "transactions_tenant_id_booked_on_idx" ON "transactions"("tenant_id", "booked_on");

-- CreateIndex
CREATE UNIQUE INDEX "transactions_tenant_id_account_id_external_id_key" ON "transactions"("tenant_id", "account_id", "external_id");

-- CreateIndex
CREATE UNIQUE INDEX "categories_tenant_id_name_key" ON "categories"("tenant_id", "name");

-- CreateIndex
CREATE INDEX "category_rules_tenant_id_idx" ON "category_rules"("tenant_id");

-- CreateIndex
CREATE UNIQUE INDEX "budgets_tenant_id_entity_id_category_id_month_key" ON "budgets"("tenant_id", "entity_id", "category_id", "month");

-- CreateIndex
CREATE INDEX "recurrences_tenant_id_entity_id_idx" ON "recurrences"("tenant_id", "entity_id");

-- CreateIndex
CREATE UNIQUE INDEX "credit_card_bills_tenant_id_account_id_closing_date_key" ON "credit_card_bills"("tenant_id", "account_id", "closing_date");

-- CreateIndex
CREATE INDEX "holdings_tenant_id_account_id_idx" ON "holdings"("tenant_id", "account_id");

-- CreateIndex
CREATE INDEX "goals_tenant_id_entity_id_idx" ON "goals"("tenant_id", "entity_id");

-- CreateIndex
CREATE INDEX "bills_tenant_id_entity_id_status_idx" ON "bills"("tenant_id", "entity_id", "status");

-- CreateIndex
CREATE INDEX "bills_tenant_id_entity_id_code_idx" ON "bills"("tenant_id", "entity_id", "code");

-- CreateIndex
CREATE INDEX "payment_plans_tenant_id_idx" ON "payment_plans"("tenant_id");

-- CreateIndex
CREATE INDEX "payment_attempts_tenant_id_bill_id_idx" ON "payment_attempts"("tenant_id", "bill_id");

-- CreateIndex
CREATE INDEX "payment_attempts_tenant_id_rail_at_idx" ON "payment_attempts"("tenant_id", "rail", "at");

-- CreateIndex
CREATE INDEX "invoice_clients_tenant_id_entity_id_idx" ON "invoice_clients"("tenant_id", "entity_id");

-- CreateIndex
CREATE INDEX "invoice_templates_tenant_id_entity_id_idx" ON "invoice_templates"("tenant_id", "entity_id");

-- CreateIndex
CREATE INDEX "invoices_tenant_id_entity_id_competence_idx" ON "invoices"("tenant_id", "entity_id", "competence");

-- CreateIndex
CREATE UNIQUE INDEX "tax_guides_tenant_id_entity_id_kind_competence_key" ON "tax_guides"("tenant_id", "entity_id", "kind", "competence");

-- CreateIndex
CREATE INDEX "alerts_tenant_id_created_at_idx" ON "alerts"("tenant_id", "created_at");

-- CreateIndex
CREATE INDEX "audit_events_tenant_id_subject_id_idx" ON "audit_events"("tenant_id", "subject_id");

-- CreateIndex
CREATE INDEX "chat_threads_tenant_id_idx" ON "chat_threads"("tenant_id");

-- CreateIndex
CREATE INDEX "chat_messages_tenant_id_thread_id_idx" ON "chat_messages"("tenant_id", "thread_id");

-- AddForeignKey
ALTER TABLE "accounts" ADD CONSTRAINT "accounts_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_account_id_fkey" FOREIGN KEY ("account_id") REFERENCES "accounts"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "bills" ADD CONSTRAINT "bills_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "financial_entities"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_plans" ADD CONSTRAINT "payment_plans_bill_id_fkey" FOREIGN KEY ("bill_id") REFERENCES "bills"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payment_attempts" ADD CONSTRAINT "payment_attempts_bill_id_fkey" FOREIGN KEY ("bill_id") REFERENCES "bills"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "chat_messages" ADD CONSTRAINT "chat_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "chat_threads"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

