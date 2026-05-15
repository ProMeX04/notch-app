import { NextResponse } from 'next/server'

import {
  getAuthenticatedUser,
  listUserDevices,
  revokeDeviceSessions,
  setTrustedDevice,
} from '@/lib/notch-auth'
import { logAppEvent } from '@/lib/event-logger'

type SessionActionBody = {
  action?: 'trust' | 'untrust' | 'revoke'
  device_id?: string
}

export async function GET(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const payload = await listUserDevices(auth.user.id, auth.sessionId)
  return NextResponse.json(payload)
}

export async function PATCH(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const body = await req.json().catch(() => null) as SessionActionBody | null
  const action = body?.action
  const deviceId = body?.device_id?.trim() ?? ''

  if (!action || !deviceId) {
    return NextResponse.json({ detail: 'Missing action or device_id.' }, { status: 400 })
  }

  if (action === 'trust') {
    await setTrustedDevice({
      userId: auth.user.id,
      deviceId,
      trusted: true,
    })
    await logAppEvent({
      req,
      eventType: 'session.trust_added',
      outcome: 'success',
      source: 'web',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
    })
  } else if (action === 'untrust') {
    await setTrustedDevice({
      userId: auth.user.id,
      deviceId,
      trusted: false,
    })
    await logAppEvent({
      req,
      eventType: 'session.trust_removed',
      outcome: 'success',
      source: 'web',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
    })
  } else if (action === 'revoke') {
    await revokeDeviceSessions({
      userId: auth.user.id,
      deviceId,
      exceptSessionId: auth.sessionId,
    })
    await logAppEvent({
      req,
      eventType: 'session.revoked',
      outcome: 'success',
      source: 'web',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      metadata: { deviceId },
    })
  } else {
    return NextResponse.json({ detail: 'Unsupported action.' }, { status: 400 })
  }

  const payload = await listUserDevices(auth.user.id, auth.sessionId)
  return NextResponse.json(payload)
}
