import { NextResponse } from 'next/server'

import { clearAuthCookies } from '@/lib/auth-cookies'
import { logAppEvent } from '@/lib/event-logger'
import { revokeAuthSessions } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const result = await revokeAuthSessions(req)
  if (!result.hasTokens) {
    await logAppEvent({
      req,
      eventType: 'auth.logout_rejected',
      outcome: 'rejected',
      source: 'web',
      statusCode: 400,
      metadata: { reason: 'missing_session_token' },
    })
    return clearAuthCookies(NextResponse.json({ detail: 'Missing session token.' }, { status: 400 }))
  }

  await logAppEvent({
    req,
    eventType: 'auth.logout_succeeded',
    outcome: 'success',
    source: 'web',
    actorUserId: result.userId,
    sessionId: result.sessionId,
    deviceId: result.deviceId,
    statusCode: 204,
  })

  return clearAuthCookies(new NextResponse(null, { status: 204 }))
}
