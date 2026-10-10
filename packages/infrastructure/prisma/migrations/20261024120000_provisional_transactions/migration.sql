-- Movements read from the preview feed wait for the main provider to confirm them.
ALTER TABLE "transactions" ADD COLUMN "provisional" BOOLEAN NOT NULL DEFAULT false;
