ALTER TABLE "User"
ADD COLUMN "displayName" TEXT,
ADD COLUMN "leaderboardOptIn" BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE "FocusDailyStat" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "date" TIMESTAMP(3) NOT NULL,
    "deviceId" TEXT NOT NULL,
    "focusSeconds" INTEGER NOT NULL DEFAULT 0,
    "sessionCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FocusDailyStat_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "FocusDailyStat_userId_date_deviceId_key"
ON "FocusDailyStat"("userId", "date", "deviceId");

CREATE INDEX "FocusDailyStat_userId_date_idx"
ON "FocusDailyStat"("userId", "date");

CREATE INDEX "FocusDailyStat_date_idx"
ON "FocusDailyStat"("date");

ALTER TABLE "FocusDailyStat"
ADD CONSTRAINT "FocusDailyStat_userId_fkey"
FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
