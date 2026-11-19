-- Existing plans are round 0, whose keys match the ones already stored.
ALTER TABLE "payment_plans" ADD COLUMN "round" INTEGER NOT NULL DEFAULT 0;
