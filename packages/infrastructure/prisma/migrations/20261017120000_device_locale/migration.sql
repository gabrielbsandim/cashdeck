-- The language a device reads its push alerts in.
ALTER TABLE "device_tokens" ADD COLUMN "locale" TEXT NOT NULL DEFAULT 'pt';
