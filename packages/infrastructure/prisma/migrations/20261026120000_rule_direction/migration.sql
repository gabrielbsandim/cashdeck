-- A rule learned from a credit stays off debits to the same payee.
ALTER TABLE "category_rules" ADD COLUMN "direction" TEXT;
