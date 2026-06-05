/*
  Warnings:

  - You are about to drop the column `accessExpiresAt` on the `AuthSession` table. All the data in the column will be lost.
  - You are about to drop the column `expiresAt` on the `AuthSession` table. All the data in the column will be lost.
  - You are about to drop the column `image` on the `User` table. All the data in the column will be lost.
  - Added the required column `refreshTokenExpiresAt` to the `AuthSession` table without a default value. This is not possible if the table is not empty.

*/
-- DropIndex
DROP INDEX "AuthSession_accessExpiresAt_idx";

-- DropIndex
DROP INDEX "AuthSession_expiresAt_idx";

-- DropIndex
DROP INDEX "AuthSession_lastSeenAt_idx";

-- AlterTable
ALTER TABLE "AuthSession" DROP COLUMN "accessExpiresAt",
DROP COLUMN "expiresAt",
ADD COLUMN     "accessTokenExpiresAt" TIMESTAMP(3),
ADD COLUMN     "oldTokenHash" TEXT,
ADD COLUMN     "refreshTokenExpiresAt" TIMESTAMP(3) NOT NULL,
ADD COLUMN     "tokenRotatedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "User" DROP COLUMN "image",
ADD COLUMN     "isAdmin" BOOLEAN NOT NULL DEFAULT false,
ALTER COLUMN "leaderboardOptIn" SET DEFAULT true;

-- CreateTable
CREATE TABLE "FeatureConfig" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "isProOnly" BOOLEAN NOT NULL DEFAULT true,
    "isEnabled" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeatureConfig_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AppEvent" (
    "id" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "eventType" TEXT NOT NULL,
    "outcome" TEXT NOT NULL,
    "source" TEXT NOT NULL,
    "actorUserId" TEXT,
    "sessionId" TEXT,
    "deviceId" TEXT,
    "requestPath" TEXT,
    "requestMethod" TEXT,
    "statusCode" INTEGER,
    "ipHash" TEXT,
    "userAgent" TEXT,
    "metadata" JSONB,

    CONSTRAINT "AppEvent_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "FeatureConfig_key_key" ON "FeatureConfig"("key");

-- CreateIndex
CREATE INDEX "AppEvent_createdAt_idx" ON "AppEvent"("createdAt");

-- CreateIndex
CREATE INDEX "AppEvent_eventType_idx" ON "AppEvent"("eventType");

-- CreateIndex
CREATE INDEX "AppEvent_outcome_idx" ON "AppEvent"("outcome");

-- CreateIndex
CREATE INDEX "AppEvent_actorUserId_idx" ON "AppEvent"("actorUserId");

-- CreateIndex
CREATE INDEX "AuthSession_refreshTokenExpiresAt_idx" ON "AuthSession"("refreshTokenExpiresAt");

-- CreateIndex
CREATE INDEX "AuthSession_accessTokenExpiresAt_idx" ON "AuthSession"("accessTokenExpiresAt");

-- CreateIndex
CREATE INDEX "AuthSession_userId_revokedAt_idx" ON "AuthSession"("userId", "revokedAt");

-- AddForeignKey
ALTER TABLE "AppEvent" ADD CONSTRAINT "AppEvent_actorUserId_fkey" FOREIGN KEY ("actorUserId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
