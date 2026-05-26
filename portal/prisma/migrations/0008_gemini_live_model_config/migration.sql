CREATE TABLE "GeminiLiveModelConfig" (
    "id" TEXT NOT NULL,
    "modelId" TEXT NOT NULL,
    "displayName" TEXT NOT NULL,
    "supportedGenerationMethods" TEXT[] NOT NULL DEFAULT ARRAY['bidiGenerateContent']::TEXT[],
    "isEnabled" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GeminiLiveModelConfig_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "GeminiLiveModelConfig_modelId_key" ON "GeminiLiveModelConfig"("modelId");
CREATE INDEX "GeminiLiveModelConfig_isEnabled_idx" ON "GeminiLiveModelConfig"("isEnabled");
CREATE INDEX "GeminiLiveModelConfig_sortOrder_idx" ON "GeminiLiveModelConfig"("sortOrder");
