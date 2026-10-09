-- What the open card bill holds so far, when the issuer marks billed charges.
ALTER TABLE "accounts" ADD COLUMN "credit_open_bill_cents" BIGINT;
