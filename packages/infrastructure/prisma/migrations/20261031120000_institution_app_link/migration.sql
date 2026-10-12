-- The link that opens a bank app, read when a payment waits on its approval.
ALTER TABLE "institutions" ADD COLUMN "app_link" TEXT;
