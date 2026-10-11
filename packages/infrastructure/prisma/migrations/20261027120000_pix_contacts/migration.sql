-- People the user sends Pix to, found by name or @handle in the chat.
CREATE TABLE "pix_contacts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "handle" TEXT NOT NULL,
    "pix_key" TEXT NOT NULL,
    "pix_key_type" TEXT NOT NULL,
    "times_paid" INTEGER NOT NULL DEFAULT 0,
    "last_paid_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pix_contacts_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "pix_contacts_tenant_id_handle_key" ON "pix_contacts"("tenant_id", "handle");

CREATE UNIQUE INDEX "pix_contacts_tenant_id_pix_key_key" ON "pix_contacts"("tenant_id", "pix_key");
