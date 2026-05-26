import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import { listAllowedGeminiLiveModels } from '@/lib/gemini-live-model-policy'
import { getAuthenticatedUser, getFeatureRequirement } from '@/lib/notch-auth'

export async function GET(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    await logAppEvent({
      req,
      eventType: 'gemini_live.models_rejected',
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
      eventType: 'gemini_live.models_rejected',
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
      eventType: 'gemini_live.models_rejected',
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      statusCode: 403,
      metadata: { reason: 'pro_required' },
    })
    return NextResponse.json({ detail: 'Notch Pro is required to list Gemini Live models.' }, { status: 403 })
  }

  const models = await listAllowedGeminiLiveModels()
  await logAppEvent({
    req,
    eventType: 'gemini_live.models_requested',
    outcome: 'success',
    source: 'desktop',
    actorUserId: auth.user.id,
    statusCode: 200,
    metadata: {
      modelCount: models.length,
      requirement,
    },
  })

  return NextResponse.json({ models })
}
