import { GoogleGenAI, Modality } from '@google/genai'
import { NextResponse } from 'next/server'

import { getAuthenticatedUser } from '@/lib/notch-auth'

type SessionTokenRequest = {
  model?: string
}

function geminiClient() {
  const apiKey = process.env.GEMINI_API_KEY?.trim()
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY is not configured on the server.')
  }

  return new GoogleGenAI({ apiKey })
}

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  if (!auth.user.isPro) {
    return NextResponse.json({ detail: 'Notch Pro is required to create a Gemini Live session token.' }, { status: 403 })
  }

  try {
    const body = (await req.json()) as SessionTokenRequest
    const now = Date.now()
    const model = typeof body.model === 'string' && body.model.trim() ? body.model.trim() : 'gemini-3.1-flash-live-preview'
    const expireTime = new Date(now + 30 * 60 * 1000).toISOString()
    const newSessionExpireTime = new Date(now + 60 * 1000).toISOString()
    const uses = 1

    const token = await geminiClient().authTokens.create({
      config: {
        uses,
        expireTime,
        newSessionExpireTime,
        liveConnectConstraints: {
          model,
          config: {
            responseModalities: [Modality.AUDIO],
            sessionResumption: {},
          },
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
