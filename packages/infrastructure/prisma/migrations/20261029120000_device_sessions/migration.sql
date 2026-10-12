-- Signed-in devices, each with its own revocable bearer token kept only as a
-- sha256 hash. Sliding 30-day expiry.
CREATE TABLE "device_sessions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "token_hash" TEXT NOT NULL,
    "device_name" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL,
    "last_used_at" TIMESTAMP(3) NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "device_sessions_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "device_sessions_token_hash_key" ON "device_sessions"("token_hash");

CREATE INDEX "device_sessions_tenant_id_revoked_at_expires_at_idx" ON "device_sessions"("tenant_id", "revoked_at", "expires_at");
