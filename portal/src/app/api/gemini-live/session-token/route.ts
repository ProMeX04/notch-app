import { GoogleGenAI } from '@google/genai'
import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import { buildGeminiLiveConnectConfig, type GeminiLiveSessionTokenRequest } from '@/lib/gemini-live-token-policy'
import { getAuthenticatedUser, getFeatureRequirement } from '@/lib/notch-auth'

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
    await logAppEvent({
      req,
      eventType: 'gemini_live.session_token_rejected',
      outcome: 'rejected',
      source: 'desktop',
      statusCode: 401,
      metadata: { reason: 'invalid_session' },
    })
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const requirement = await getFeatureRequirement('talk_connection')
  if (requirement === 'disabled') {
    await logAppEvent({
      req,
      eventType: 'gemini_live.session_token_rejected',
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      statusCode: 403,
      metadata: { reason: 'feature_disabled' },
    })
    return NextResponse.json({ detail: 'This feature is currently disabled.' }, { status: 403 })
  }
  if (requirement === 'pro' && !auth.user.isPro) {
    await logAppEvent({
      req,
      eventType: 'gemini_live.session_token_rejected',
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      statusCode: 403,
      metadata: { reason: 'pro_required' },
    })
    return NextResponse.json({ detail: 'Notch Pro is required to create a Gemini Live session token.' }, { status: 403 })
  }

  try {
    const body = (await req.json()) as GeminiLiveSessionTokenRequest
    const now = Date.now()
    const model = typeof body.model === 'string' ? body.model.trim() : ''
    if (!model) {
      await logAppEvent({
        req,
        eventType: 'gemini_live.session_token_rejected',
        outcome: 'rejected',
        source: 'desktop',
        actorUserId: auth.user.id,
        statusCode: 400,
        metadata: { reason: 'missing_model' },
      })
      return NextResponse.json({ detail: 'Model is required.' }, { status: 400 })
    }
    const expireTime = new Date(now + 30 * 60 * 1000).toISOString()
    const newSessionExpireTime = new Date(now + 60 * 1000).toISOString()
    // Session resumption may reuse this token within expireTime even with one use.
    const uses = 1

    // Forward client-supplied session settings into the ephemeral token's
    // `liveConnectConstraints`. When constraints are set, the live WebSocket
    // runs in "constrained" mode and any matching fields the client sends in
    // its setup message are ignored. Embed stable session settings here, while
    // deliberately leaving sessionResumption unlocked because its handle is
    // only known later when the desktop reconnects.
    const { liveConfig, responseModalities, mediaResolution, hasThinkingLevel, hasThinkingBudget } =
      buildGeminiLiveConnectConfig(body, model)

    await logAppEvent({
      req,
      eventType: 'gemini_live.session_token_requested',
      outcome: 'success',
      source: 'desktop',
      actorUserId: auth.user.id,
      statusCode: 200,
      metadata: {
        model,
        responseModalities,
        modalityCount: responseModalities.length,
        hasVoice: Boolean(typeof body.voice_name === 'string' && body.voice_name.trim()),
        hasThinkingLevel,
        hasThinkingBudget,
        mediaResolution,
        requirement,
      },
    })

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
    await logAppEvent({
      req,
      eventType: 'gemini_live.session_token_failed',
      outcome: 'failure',
      source: 'desktop',
      actorUserId: auth.user.id,
      statusCode: 500,
      metadata: { errorName: error instanceof Error ? error.name : 'UnknownError' },
    })
    return NextResponse.json({ detail: message }, { status: 500 })
  }
}
