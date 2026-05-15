import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import { AuthDeviceLimitError } from '@/lib/notch-auth'
import { exchangeOAuthToken } from '@/lib/notch-oauth'

async function readTokenRequestBody(req: Request) {
  const contentType = req.headers.get('content-type')?.toLowerCase() ?? ''

  if (contentType.includes('application/x-www-form-urlencoded')) {
    const params = new URLSearchParams(await req.text())
    const body = Object.fromEntries(params.entries())
    return {
      ...body,
      trust_device: body.trust_device,
    }
  }

  return await req.json().catch(() => null)
}

export async function POST(req: Request) {
  const body = await readTokenRequestBody(req) as
    | {
        grant_type?: string
        client_id?: string
        redirect_uri?: string
        code?: string
        code_verifier?: string
        refresh_token?: string
        device_id?: string
        device_name?: string
        platform?: string
        trust_device?: string | boolean
      }
    | null

  try {
    const payload = await exchangeOAuthToken(req, body ?? {})
    if (!payload) {
      await logAppEvent({
        req,
        eventType: 'oauth.token_failed',
        outcome: 'failure',
        source: 'oauth',
        statusCode: 401,
        metadata: { reason: 'invalid_or_expired', grantType: body?.grant_type, clientId: body?.client_id },
      })
      return NextResponse.json({ detail: 'OAuth code or token is invalid or expired.' }, { status: 401 })
    }

    await logAppEvent({
      req,
      eventType: 'oauth.token_succeeded',
      outcome: 'success',
      source: 'oauth',
      actorUserId: payload.user.id,
      sessionId: payload.session.id,
      deviceId: payload.session.device_id,
      statusCode: 200,
      metadata: { grantType: body?.grant_type, clientId: body?.client_id, platform: payload.session.platform },
    })
    return NextResponse.json(payload)
  } catch (error) {
    if (error instanceof AuthDeviceLimitError) {
      await logAppEvent({
        req,
        eventType: 'oauth.token_rejected',
        outcome: 'rejected',
        source: 'oauth',
        statusCode: error.statusCode,
        metadata: { reason: 'device_limit', grantType: body?.grant_type, clientId: body?.client_id },
      })
      return NextResponse.json({ detail: error.message }, { status: error.statusCode })
    }

    await logAppEvent({
      req,
      eventType: 'oauth.token_failed',
      outcome: 'failure',
      source: 'oauth',
      statusCode: 400,
      metadata: { grantType: body?.grant_type, clientId: body?.client_id, errorName: error instanceof Error ? error.name : 'UnknownError' },
    })
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Could not exchange OAuth token.' },
      { status: 400 },
    )
  }
}
