import prisma from '@/lib/prisma'
import { capabilityDefaults, type CapabilityRequirement } from '@/lib/capability-manifest'

export type FeatureRequirement = CapabilityRequirement

export type FeatureConfigLike = {
  key: string
  name: string
  description: string | null
  isProOnly: boolean
  isEnabled: boolean
  updatedAt?: Date
}

export const DEFAULT_FEATURE_CONFIGS = capabilityDefaults()

function featureRequirement(config: Pick<FeatureConfigLike, 'isEnabled' | 'isProOnly'>): FeatureRequirement {
  if (!config.isEnabled) return 'disabled'
  return config.isProOnly ? 'pro' : 'free'
}

export function mergeDefaultFeatureConfigs(configs: FeatureConfigLike[]) {
  const byKey = new Map<string, FeatureConfigLike>()

  DEFAULT_FEATURE_CONFIGS.forEach((config) => {
    byKey.set(config.key, {
      ...config,
      description: config.description,
    })
  })

  configs.forEach((config) => {
    byKey.set(config.key, config)
  })

  return Array.from(byKey.values()).sort((a, b) => a.name.localeCompare(b.name))
}

export async function getRemotePermissionPolicy() {
  const configs = await prisma.featureConfig.findMany()
  const features: Record<string, FeatureRequirement> = {}

  mergeDefaultFeatureConfigs(configs).forEach((config) => {
    features[config.key] = featureRequirement(config)
  })

  return {
    version: 1,
    features,
    updated_at: new Date().toISOString(),
  }
}

export async function getFeatureRequirement(key: string): Promise<FeatureRequirement> {
  const config = await prisma.featureConfig.findUnique({ where: { key } })
  const resolvedConfig = config ?? DEFAULT_FEATURE_CONFIGS.find((defaultConfig) => defaultConfig.key === key)
  if (!resolvedConfig) return 'disabled'
  return featureRequirement(resolvedConfig)
}

export async function canUseFeature(user: { isPro: boolean }, key: string): Promise<boolean> {
  const requirement = await getFeatureRequirement(key)
  if (requirement === 'disabled') return false
  if (requirement === 'pro') return user.isPro
  return true
}
