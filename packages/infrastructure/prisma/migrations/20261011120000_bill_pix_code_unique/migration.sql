-- One live bill per Pix code. Fails if open duplicates already exist; see the
-- check query in docs/providers.md ("Pix first") before deploying.

-- CreateIndex
CREATE UNIQUE INDEX "bills_tenant_id_entity_id_pix_code_key" ON "bills"("tenant_id", "entity_id", "pix_code") WHERE (pix_code IS NOT NULL AND status <> 'CANCELLED');
