-- Subscriptions the user confirmed or dismissed, one per entity and charge.
ALTER TABLE "recurrences"
  ADD COLUMN "key" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "dismissed" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "recurrences" ALTER COLUMN "key" DROP DEFAULT;
CREATE UNIQUE INDEX "recurrences_tenant_id_entity_id_key_key" ON "recurrences"("tenant_id", "entity_id", "key");
