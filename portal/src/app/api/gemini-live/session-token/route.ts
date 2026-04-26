import { GoogleGenAI, Modality } from '@google/genai'
import { NextResponse } from 'next/server'

import { getAuthenticatedUser, getFeatureRequirement } from '@/lib/notch-auth'

type SessionTokenRequest = {
  model?: string
  system_instruction?: string | null
  voice_name?: string | null
  thinking_budget?: number | null
  response_modalities?: string[] | null
}

function geminiClient() {
  const apiKey = process.env.GEMINI_API_KEY?.trim()
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY is not configured on the server.')
  }

  return new GoogleGenAI({ apiKey })
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

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const requirement = await getFeatureRequirement('talk_connection')
  if (requirement === 'disabled') {
    return NextResponse.json({ detail: 'This feature is currently disabled.' }, { status: 403 })
  }
  if (requirement === 'pro' && !auth.user.isPro) {
    return NextResponse.json({ detail: 'Notch Pro is required to create a Gemini Live session token.' }, { status: 403 })
  }

  try {
    const body = (await req.json()) as SessionTokenRequest
    const now = Date.now()
    const model = typeof body.model === 'string' ? body.model.trim() : ''
    if (!model) {
      return NextResponse.json({ detail: 'Model is required.' }, { status: 400 })
    }
    const expireTime = new Date(now + 30 * 60 * 1000).toISOString()
    const newSessionExpireTime = new Date(now + 60 * 1000).toISOString()
    const uses = 1

    // Forward client-supplied session settings into the ephemeral token's
    // `liveConnectConstraints`. When constraints are set, the live WebSocket
    // runs in "constrained" mode and any matching fields the client sends in
    // its setup message are ignored — so if we don't lock voiceName / system
    // instruction / thinkingBudget here, the session silently falls back to
    // defaults (previous bug: wrong voice when connecting via ephemeral token).
    const requestedModalities = Array.isArray(body.response_modalities)
      ? body.response_modalities
          .map((value) => (typeof value === 'string' ? normalizeModality(value) : null))
          .filter((value): value is Modality => value !== null)
      : []
    const responseModalities = requestedModalities.length > 0 ? requestedModalities : [Modality.AUDIO]

    const trimmedSystemInstruction =
      typeof body.system_instruction === 'string' ? body.system_instruction.trim() : ''
    const trimmedVoiceName = typeof body.voice_name === 'string' ? body.voice_name.trim() : ''
    const thinkingBudget =
      typeof body.thinking_budget === 'number' && Number.isFinite(body.thinking_budget)
        ? Math.max(0, Math.trunc(body.thinking_budget))
        : null

    const liveConfig: Record<string, unknown> = {
      responseModalities,
      sessionResumption: {},
    }

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
      liveConfig.systemInstruction = {
        parts: [{ text: trimmedSystemInstruction }],
      }
    }

    if (thinkingBudget !== null && thinkingBudget > 0) {
      liveConfig.generationConfig = {
        thinkingConfig: { thinkingBudget },
      }
    }

    const token = await geminiClient().authTokens.create({
      config: {
        uses,
        expireTime,
        newSessionExpireTime,
        // Lock only the fields explicitly embedded in the token setup.
        // Without this, @google/genai treats liveConnectConstraints as
        // "lock the entire LiveConnectConfig", which causes the client's
        // setup.tools to be ignored in constrained sessions.
        lockAdditionalFields: [],
        liveConnectConstraints: {
          model,
          config: liveConfig,
        },
        httpOptions: {
          apiVersion: 'v1alpha',
        },
      },
    })

    return NextResponse.json({
      name: token.name,
      expire_time: expireTime,
      new_session_expire_time: newSessionExpireTime,
      uses,
    })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Internal server error'
    return NextResponse.json({ detail: message }, { status: 500 })
  }
}
