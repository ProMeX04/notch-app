export type GeminiLiveModelDescriptor = {
  id: string
  name: string
  displayName: string
  supportedGenerationMethods: string[]
}

export type GeminiLiveModelAdminConfig = GeminiLiveModelDescriptor & {
  configId: string | null
  isEnabled: boolean
  sortOrder: number
  source: 'database' | 'default'
  updatedAt: string | null
}

type GeminiLiveModelPolicyEnv = Record<string, string | undefined>

const liveGenerationMethod = 'bidiGenerateContent'

const defaultLiveModels: GeminiLiveModelDescriptor[] = [
  buildModelDescriptor('gemini-3.1-flash-live-preview', 'Gemini 3.1 Flash Live Preview'),
  buildModelDescriptor('gemini-2.5-flash-native-audio-preview-12-2025', 'Gemini 2.5 Flash Native Audio Preview'),
]

export function normalizeGeminiLiveModelID(value: string): string {
  return value.trim().replace(/^models\//, '')
}

export function listConfiguredGeminiLiveModels(
  env: GeminiLiveModelPolicyEnv = process.env,
): GeminiLiveModelDescriptor[] {
  const rawList = env.NOTCH_GEMINI_LIVE_ALLOWED_MODELS ?? ''
  const configuredModels = rawList
    .split(',')
    .map(parseConfiguredModelEntry)
    .filter((model): model is GeminiLiveModelDescriptor => model !== null)

  return uniqueModels(configuredModels.length > 0 ? configuredModels : defaultLiveModels)
}

export async function listAllowedGeminiLiveModels(): Promise<GeminiLiveModelDescriptor[]> {
  const prisma = await getPrisma()
  const databaseModels = await prisma.geminiLiveModelConfig.findMany({
    orderBy: [{ sortOrder: 'asc' }, { displayName: 'asc' }],
  })

  if (databaseModels.length === 0) {
    return listConfiguredGeminiLiveModels()
  }

  return databaseModels
    .filter((model) => model.isEnabled)
    .map((model) =>
      buildModelDescriptor(
        model.modelId,
        model.displayName,
        model.supportedGenerationMethods.length > 0 ? model.supportedGenerationMethods : [liveGenerationMethod],
      ),
    )
}

export async function listGeminiLiveModelAdminConfigs(): Promise<GeminiLiveModelAdminConfig[]> {
  const prisma = await getPrisma()
  const databaseModels = await prisma.geminiLiveModelConfig.findMany({
    orderBy: [{ sortOrder: 'asc' }, { displayName: 'asc' }],
  })

  if (databaseModels.length === 0) {
    return listConfiguredGeminiLiveModels().map((model, index) => ({
      ...model,
      configId: null,
      isEnabled: true,
      sortOrder: index,
      source: 'default',
      updatedAt: null,
    }))
  }

  return databaseModels.map((model) => ({
    ...buildModelDescriptor(
      model.modelId,
      model.displayName,
      model.supportedGenerationMethods.length > 0 ? model.supportedGenerationMethods : [liveGenerationMethod],
    ),
    configId: model.id,
    isEnabled: model.isEnabled,
    sortOrder: model.sortOrder,
    source: 'database',
    updatedAt: model.updatedAt.toISOString(),
  }))
}

export async function replaceGeminiLiveModelAdminConfigs(
  models: Array<{
    modelId: string
    displayName: string
    isEnabled: boolean
    sortOrder: number
  }>,
): Promise<GeminiLiveModelAdminConfig[]> {
  const prisma = await getPrisma()
  await prisma.$transaction([
    prisma.geminiLiveModelConfig.deleteMany(),
    ...models.map((model) =>
      prisma.geminiLiveModelConfig.create({
        data: {
          modelId: normalizeGeminiLiveModelID(model.modelId),
          displayName: normalizedDisplayName(model.displayName, model.modelId),
          supportedGenerationMethods: [liveGenerationMethod],
          isEnabled: model.isEnabled,
          sortOrder: model.sortOrder,
        },
      }),
    ),
  ])

  return listGeminiLiveModelAdminConfigs()
}

export async function upsertGeminiLiveModelAdminConfig(input: {
  modelId: string
  displayName: string
  isEnabled: boolean
  sortOrder: number
}): Promise<GeminiLiveModelAdminConfig> {
  const prisma = await getPrisma()
  const modelId = normalizeGeminiLiveModelID(input.modelId)
  const displayName = normalizedDisplayName(input.displayName, modelId)
  const model = await prisma.geminiLiveModelConfig.upsert({
    where: { modelId },
    update: {
      displayName,
      supportedGenerationMethods: [liveGenerationMethod],
      isEnabled: input.isEnabled,
      sortOrder: input.sortOrder,
    },
    create: {
      modelId,
      displayName,
      supportedGenerationMethods: [liveGenerationMethod],
      isEnabled: input.isEnabled,
      sortOrder: input.sortOrder,
    },
  })

  return {
    ...buildModelDescriptor(model.modelId, model.displayName, model.supportedGenerationMethods),
    configId: model.id,
    isEnabled: model.isEnabled,
    sortOrder: model.sortOrder,
    source: 'database',
    updatedAt: model.updatedAt.toISOString(),
  }
}

export async function deleteGeminiLiveModelAdminConfig(modelID: string): Promise<void> {
  const prisma = await getPrisma()
  await prisma.geminiLiveModelConfig.deleteMany({
    where: { modelId: normalizeGeminiLiveModelID(modelID) },
  })
}

export async function restoreDefaultGeminiLiveModelAdminConfigs(): Promise<GeminiLiveModelAdminConfig[]> {
  return replaceGeminiLiveModelAdminConfigs(
    listConfiguredGeminiLiveModels().map((model, index) => ({
      modelId: model.id,
      displayName: model.displayName,
      isEnabled: true,
      sortOrder: index,
    })),
  )
}

export async function resolveAllowedGeminiLiveModel(modelID: string): Promise<GeminiLiveModelDescriptor | null> {
  const normalizedID = normalizeGeminiLiveModelID(modelID)
  return (await listAllowedGeminiLiveModels()).find((model) => model.id === normalizedID) ?? null
}

export function resolveConfiguredGeminiLiveModel(
  modelID: string,
  env: GeminiLiveModelPolicyEnv = process.env,
): GeminiLiveModelDescriptor | null {
  const normalizedID = normalizeGeminiLiveModelID(modelID)
  return listConfiguredGeminiLiveModels(env).find((model) => model.id === normalizedID) ?? null
}

function parseConfiguredModelEntry(rawValue: string): GeminiLiveModelDescriptor | null {
  const trimmed = rawValue.trim()
  if (!trimmed) return null

  const [rawID, rawDisplayName] = trimmed.split('|', 2)
  const id = normalizeGeminiLiveModelID(rawID)
  if (!id) return null

  const displayName = rawDisplayName?.trim() || titleFromModelID(id)
  return buildModelDescriptor(id, displayName)
}

function buildModelDescriptor(
  id: string,
  displayName: string,
  supportedGenerationMethods: string[] = [liveGenerationMethod],
): GeminiLiveModelDescriptor {
  const normalizedID = normalizeGeminiLiveModelID(id)
  return {
    id: normalizedID,
    name: `models/${normalizedID}`,
    displayName,
    supportedGenerationMethods,
  }
}

function uniqueModels(models: GeminiLiveModelDescriptor[]): GeminiLiveModelDescriptor[] {
  const seen = new Set<string>()
  const unique: GeminiLiveModelDescriptor[] = []
  for (const model of models) {
    if (seen.has(model.id)) continue
    seen.add(model.id)
    unique.push(model)
  }
  return unique
}

function titleFromModelID(id: string): string {
  return id
    .replace(/^gemini-/, 'Gemini ')
    .split('-')
    .map((part) => (part ? part[0].toUpperCase() + part.slice(1) : part))
    .join(' ')
}

function normalizedDisplayName(displayName: string, modelID: string): string {
  const trimmedDisplayName = displayName.trim()
  return trimmedDisplayName || titleFromModelID(normalizeGeminiLiveModelID(modelID))
}

async function getPrisma() {
  return (await import('@/lib/prisma')).default
}
