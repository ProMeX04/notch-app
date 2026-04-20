ALTER TABLE "AuthSession"
ADD COLUMN "deviceId" TEXT,
ADD COLUMN "deviceName" TEXT,
ADD COLUMN "platform" TEXT,
ADD COLUMN "lastSeenAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN "trustedAt" TIMESTAMP(3),
ADD COLUMN "revokedReason" TEXT;

CREATE INDEX "AuthSession_userId_deviceId_idx" ON "AuthSession"("userId", "deviceId");
CREATE INDEX "AuthSession_lastSeenAt_idx" ON "AuthSession"("lastSeenAt");
CREATE INDEX "AuthSession_trustedAt_idx" ON "AuthSession"("trustedAt");
