CREATE TABLE "GoogleDriveAuthHandoff" (
    "id" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "codeChallenge" TEXT NOT NULL,
    "accessToken" TEXT NOT NULL,
    "refreshToken" TEXT,
    "expiresIn" INTEGER,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "consumedAt" TIMESTAMP(3),

    CONSTRAINT "GoogleDriveAuthHandoff_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "GoogleDriveAuthHandoff_tokenHash_key" ON "GoogleDriveAuthHandoff"("tokenHash");
CREATE INDEX "GoogleDriveAuthHandoff_expiresAt_idx" ON "GoogleDriveAuthHandoff"("expiresAt");
CREATE INDEX "GoogleDriveAuthHandoff_consumedAt_idx" ON "GoogleDriveAuthHandoff"("consumedAt");
