-- Investment positions each Open Finance item reports, refreshed on every sync.
CREATE TYPE "InvestmentKind" AS ENUM ('FIXED_INCOME', 'FUND', 'EQUITY', 'ETF', 'PENSION', 'STRUCTURED', 'OTHER');

CREATE TYPE "InvestmentStatus" AS ENUM ('ACTIVE', 'PENDING', 'CLOSED');

CREATE TABLE "investments" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "entity_id" TEXT NOT NULL,
    "connection_id" TEXT NOT NULL,
    "institution_id" TEXT NOT NULL,
    "external_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "kind" "InvestmentKind" NOT NULL,
    "subtype" TEXT,
    "issuer" TEXT,
    "status" "InvestmentStatus" NOT NULL,
    "balance_cents" BIGINT NOT NULL,
    "invested_cents" BIGINT,
    "profit_cents" BIGINT,
    "currency" CHAR(3) NOT NULL DEFAULT 'BRL',
    "quantity" DOUBLE PRECISION,
    "rate_percent" DOUBLE PRECISION,
    "rate_index" TEXT,
    "fixed_annual_rate" DOUBLE PRECISION,
    "last_month_rate" DOUBLE PRECISION,
    "last_twelve_months_rate" DOUBLE PRECISION,
    "due_on" DATE,
    "valued_on" DATE,
    "synced_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "investments_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "investments_tenant_id_connection_id_external_id_key" ON "investments"("tenant_id", "connection_id", "external_id");
CREATE INDEX "investments_tenant_id_entity_id_idx" ON "investments"("tenant_id", "entity_id");
