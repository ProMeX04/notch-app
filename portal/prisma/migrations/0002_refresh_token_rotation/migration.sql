-- AlterTable
ALTER TABLE "AuthSession"
ADD COLUMN "accessExpiresAt" TIMESTAMP(3),
ADD COLUMN "accessTokenHash" TEXT;

-- CreateIndex
CREATE UNIQUE INDEX "AuthSession_accessTokenHash_key" ON "AuthSession"("accessTokenHash");

-- CreateIndex
CREATE INDEX "AuthSession_accessExpiresAt_idx" ON "AuthSession"("accessExpiresAt");
