import manifest from '@/lib/capabilities/notch-capabilities.json'

export type CapabilityRequirement = 'free' | 'pro' | 'disabled'

type CapabilityManifestEntry = {
  key: string
  name: string
  description: string
  requirement: CapabilityRequirement
}

type CapabilityManifest = {
  version: number
  capabilities: CapabilityManifestEntry[]
}

const capabilityManifest = manifest as CapabilityManifest

export function loadCapabilityManifest(): CapabilityManifest {
  return capabilityManifest
}

export type FeatureConfigDefault = {
  key: string
  name: string
  description: string
  isProOnly: boolean
  isEnabled: boolean
}

export function capabilityDefaults(): FeatureConfigDefault[] {
  return capabilityManifest.capabilities.map((entry) => ({
    key: entry.key,
    name: entry.name,
    description: entry.description,
    isProOnly: entry.requirement === 'pro',
    isEnabled: entry.requirement !== 'disabled',
  }))
}
