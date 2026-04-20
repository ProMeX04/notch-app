CREATE TABLE "AuthAppBridgeToken" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "deviceId" TEXT,
    "deviceName" TEXT,
    "platform" TEXT,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completedAt" TIMESTAMP(3),
    "consumedAt" TIMESTAMP(3),
    "userId" TEXT,

    CONSTRAINT "AuthAppBridgeToken_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "AuthAppBridgeToken_tokenHash_key" ON "AuthAppBridgeToken"("tokenHash");
CREATE INDEX "AuthAppBridgeToken_userId_idx" ON "AuthAppBridgeToken"("userId");
CREATE INDEX "AuthAppBridgeToken_expiresAt_idx" ON "AuthAppBridgeToken"("expiresAt");
CREATE INDEX "AuthAppBridgeToken_completedAt_idx" ON "AuthAppBridgeToken"("completedAt");

ALTER TABLE "AuthAppBridgeToken"
ADD CONSTRAINT "AuthAppBridgeToken_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
