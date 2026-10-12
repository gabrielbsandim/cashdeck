-- Goals get a look, a link to an investment, an archive date and manual
-- contributions; budgets carry the leftover of a month that rolls over.
ALTER TABLE "goals" ADD COLUMN "investment_id" TEXT,
ADD COLUMN "icon" TEXT,
ADD COLUMN "color" TEXT,
ADD COLUMN "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN "archived_at" TIMESTAMP(3);

ALTER TABLE "budgets" ADD COLUMN "carried_cents" BIGINT NOT NULL DEFAULT 0;

CREATE TABLE "goal_contributions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "goal_id" TEXT NOT NULL,
    "amount_cents" BIGINT NOT NULL,
    "on" DATE NOT NULL,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "goal_contributions_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "goal_contributions_tenant_id_goal_id_idx" ON "goal_contributions"("tenant_id", "goal_id");
