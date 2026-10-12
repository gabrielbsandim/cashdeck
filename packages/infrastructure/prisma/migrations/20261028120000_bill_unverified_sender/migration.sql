-- A bill read from an e-mail whose sender failed authentication never inherits trust.
ALTER TABLE "bills" ADD COLUMN "unverified_sender" BOOLEAN NOT NULL DEFAULT false;
