import prisma from '@/lib/prisma'
import { capabilityDefaults } from '@/lib/capability-manifest'
import { mergeDefaultFeatureConfigs } from './policy-service'

export async function listCapabilities() {
  const configs = await prisma.featureConfig.findMany({
    orderBy: { name: 'asc' },
  })
  return mergeDefaultFeatureConfigs(configs)
}

export async function restoreDefaultCapabilities() {
  const defaults = capabilityDefaults()
  const defaultKeys = defaults.map((config) => config.key)

  await prisma.$transaction([
    prisma.featureConfig.deleteMany({ where: { key: { notIn: defaultKeys } } }),
    ...defaults.map((config) =>
      prisma.featureConfig.upsert({
        where: { key: config.key },
        update: {
          name: config.name,
          description: config.description,
          isProOnly: config.isProOnly,
          isEnabled: config.isEnabled,
        },
        create: {
          key: config.key,
          name: config.name,
          description: config.description,
          isProOnly: config.isProOnly,
          isEnabled: config.isEnabled,
        },
      })
    ),
  ])

  return mergeDefaultFeatureConfigs(defaults)
}

export async function upsertCapability(input: {
  key: string
  name: string
  description?: string | null
  isProOnly: boolean
  isEnabled: boolean
}) {
  const config = await prisma.featureConfig.upsert({
    where: { key: input.key },
    update: {
      name: input.name,
      description: input.description ?? null,
      isProOnly: input.isProOnly,
      isEnabled: input.isEnabled,
    },
    create: {
      key: input.key,
      name: input.name,
      description: input.description ?? null,
      isProOnly: input.isProOnly,
      isEnabled: input.isEnabled,
    },
  })
  return config
}
