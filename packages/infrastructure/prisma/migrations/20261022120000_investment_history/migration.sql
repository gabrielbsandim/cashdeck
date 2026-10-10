-- Movements and daily balances of each investment position, and the daily CDI rates its yield is compared with.
CREATE TYPE "InvestmentMovementKind" AS ENUM ('BUY', 'SELL', 'INCOME', 'TAX', 'TRANSFER', 'OTHER');

CREATE TABLE "investment_movements" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "investment_id" TEXT NOT NULL,
    "external_id" TEXT NOT NULL,
    "kind" "InvestmentMovementKind" NOT NULL,
    "occurred_on" DATE NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "quantity" DOUBLE PRECISION,
    "unit_price" DOUBLE PRECISION,

    CONSTRAINT "investment_movements_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "investment_snapshots" (
    "tenant_id" TEXT NOT NULL,
    "investment_id" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "balance_cents" BIGINT NOT NULL,
    "estimated" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "investment_snapshots_pkey" PRIMARY KEY ("investment_id","day")
);

CREATE TABLE "index_rates" (
    "index" TEXT NOT NULL,
    "day" DATE NOT NULL,
    "rate" DOUBLE PRECISION NOT NULL,

    CONSTRAINT "index_rates_pkey" PRIMARY KEY ("index","day")
);

CREATE INDEX "investment_movements_tenant_id_investment_id_idx" ON "investment_movements"("tenant_id", "investment_id");
CREATE UNIQUE INDEX "investment_movements_investment_id_external_id_key" ON "investment_movements"("investment_id", "external_id");
CREATE INDEX "investment_snapshots_tenant_id_day_idx" ON "investment_snapshots"("tenant_id", "day");

ALTER TABLE "investment_movements" ADD CONSTRAINT "investment_movements_investment_id_fkey" FOREIGN KEY ("investment_id") REFERENCES "investments"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "investment_snapshots" ADD CONSTRAINT "investment_snapshots_investment_id_fkey" FOREIGN KEY ("investment_id") REFERENCES "investments"("id") ON DELETE CASCADE ON UPDATE CASCADE;
