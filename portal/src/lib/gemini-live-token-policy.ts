import { MediaResolution, Modality, ThinkingLevel, type LiveConnectConfig } from '@google/genai'

export type GeminiLiveSessionTokenRequest = {
  model?: string
  system_instruction?: string | null
  voice_name?: string | null
  thinking_level?: string | null
  thinking_budget?: number | null
  media_resolution?: string | null
  response_modalities?: string[] | null
}

function normalizeModality(raw: string): Modality | null {
  switch (raw.trim().toUpperCase()) {
    case 'AUDIO':
      return Modality.AUDIO
    case 'TEXT':
      return Modality.TEXT
    case 'IMAGE':
      return Modality.IMAGE
    default:
      return null
  }
}

function normalizeMediaResolution(raw: string): MediaResolution | null {
  switch (raw.trim().toUpperCase()) {
    case 'MEDIA_RESOLUTION_LOW':
      return MediaResolution.MEDIA_RESOLUTION_LOW
    case 'MEDIA_RESOLUTION_MEDIUM':
      return MediaResolution.MEDIA_RESOLUTION_MEDIUM
    case 'MEDIA_RESOLUTION_HIGH':
      return MediaResolution.MEDIA_RESOLUTION_HIGH
    default:
      return null
  }
}

function normalizeThinkingLevel(raw: string): ThinkingLevel | null {
  switch (raw.trim().toUpperCase()) {
    case 'MINIMAL':
      return ThinkingLevel.MINIMAL
    case 'LOW':
      return ThinkingLevel.LOW
    case 'MEDIUM':
      return ThinkingLevel.MEDIUM
    case 'HIGH':
      return ThinkingLevel.HIGH
    default:
      return null
  }
}

function modelUsesThinkingLevel(model: string): boolean {
  return model.replace(/^models\//, '').toLowerCase().startsWith('gemini-3')
}

export function buildGeminiLiveConnectConfig(body: GeminiLiveSessionTokenRequest, model: string): {
  liveConfig: LiveConnectConfig
  responseModalities: Modality[]
  mediaResolution: MediaResolution | null
  hasThinkingLevel: boolean
  hasThinkingBudget: boolean
} {
  const requestedModalities = Array.isArray(body.response_modalities)
    ? body.response_modalities
        .map((value) => (typeof value === 'string' ? normalizeModality(value) : null))
        .filter((value): value is Modality => value !== null)
    : []
  const responseModalities = requestedModalities.length > 0 ? requestedModalities : [Modality.AUDIO]
  const trimmedSystemInstruction =
    typeof body.system_instruction === 'string' ? body.system_instruction.trim() : ''
  const trimmedVoiceName = typeof body.voice_name === 'string' ? body.voice_name.trim() : ''
  const thinkingLevel =
    typeof body.thinking_level === 'string' ? normalizeThinkingLevel(body.thinking_level) : null
  const thinkingBudget =
    typeof body.thinking_budget === 'number' && Number.isFinite(body.thinking_budget)
      ? Math.max(0, Math.trunc(body.thinking_budget))
      : null
  const mediaResolution =
    typeof body.media_resolution === 'string' ? normalizeMediaResolution(body.media_resolution) : null

  // Do not constrain sessionResumption. The desktop client supplies the latest
  // handle at reconnect time, which cannot be embedded when this token is issued.
  const liveConfig: LiveConnectConfig = { responseModalities }

  if (trimmedVoiceName) {
    liveConfig.speechConfig = {
      voiceConfig: {
        prebuiltVoiceConfig: {
          voiceName: trimmedVoiceName,
        },
      },
    }
  }
  if (trimmedSystemInstruction) {
    liveConfig.systemInstruction = { parts: [{ text: trimmedSystemInstruction }] }
  }

  let hasThinkingLevel = false
  let hasThinkingBudget = false
  if (modelUsesThinkingLevel(model)) {
    if (thinkingLevel !== null) {
      liveConfig.thinkingConfig = { thinkingLevel }
      hasThinkingLevel = true
    }
  } else if (thinkingBudget !== null) {
    liveConfig.thinkingConfig = { thinkingBudget }
    hasThinkingBudget = true
  }

  if (mediaResolution !== null) {
    liveConfig.mediaResolution = mediaResolution
  }

  return { liveConfig, responseModalities, mediaResolution, hasThinkingLevel, hasThinkingBudget }
}
