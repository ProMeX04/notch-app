import { NextResponse } from 'next/server'

import { applyAuthCookies, clearAuthCookies, readRefreshTokenCookie } from '@/lib/auth-cookies'
import { logAppEvent } from '@/lib/event-logger'
import { refreshAuthSessionWithToken } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const body = await req.clone().json().catch(() => null) as {
    refresh_token?: string
    device_id?: string
    device_name?: string
    platform?: string
    trust_device?: boolean | string
  } | null
  const device = body
    ? {
        device_id: body.device_id,
        device_name: body.device_name,
        platform: body.platform,
        trust_device:
          typeof body.trust_device === 'boolean'
            ? body.trust_device
            : typeof body.trust_device === 'string'
              ? ['1', 'true', 'yes'].includes(body.trust_device.trim().toLowerCase())
              : undefined,
      }
    : null
  const refreshToken = body?.refresh_token?.trim() || readRefreshTokenCookie(req) || ''
  const payload = await refreshAuthSessionWithToken(req, refreshToken, device)
  if (!payload) {
    await logAppEvent({
      req,
      eventType: 'auth.refresh_failed',
      outcome: 'failure',
      source: 'web',
      statusCode: 401,
      metadata: { reason: 'invalid_or_expired' },
    })
    return clearAuthCookies(NextResponse.json({ detail: 'Refresh token is invalid or expired.' }, { status: 401 }), req)
  }

  await logAppEvent({
    req,
    eventType: 'auth.refresh_succeeded',
    outcome: 'success',
    source: 'web',
    actorUserId: payload.user.id,
    sessionId: payload.session.id,
    deviceId: payload.session.device_id,
    statusCode: 200,
    metadata: { platform: payload.session.platform },
  })

  return applyAuthCookies(
    NextResponse.json(payload),
    payload,
    req,
  )
}
