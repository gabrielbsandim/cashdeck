-- The time of day orders a day's transactions; banks that send only the date
-- leave it empty.
ALTER TABLE "transactions" ADD COLUMN "booked_at" TIMESTAMP(3);
