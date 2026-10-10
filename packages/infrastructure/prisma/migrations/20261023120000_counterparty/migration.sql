-- The document of the other side of a payment, so a rule can tell who a bare Pix went to.
ALTER TABLE "transactions" ADD COLUMN "counterparty" TEXT;

ALTER TABLE "category_rules" ADD COLUMN "counterparty" TEXT;
