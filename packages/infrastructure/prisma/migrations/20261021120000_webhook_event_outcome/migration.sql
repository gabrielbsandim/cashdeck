-- What each webhook named and what handling it came to, for auditing.
ALTER TABLE "webhook_events" ADD COLUMN "type" TEXT,
ADD COLUMN "subject_id" TEXT,
ADD COLUMN "outcome" TEXT,
ADD COLUMN "reason" TEXT,
ADD COLUMN "processed_at" TIMESTAMP(3);
