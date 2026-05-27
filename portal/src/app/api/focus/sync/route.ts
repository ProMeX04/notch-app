import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import {
  focusEventTypes,
  focusRejectedMetadata,
  focusSyncFailedMetadata,
  focusSyncSucceededMetadata,
} from '@/lib/focus-event-policy'
import { getAuthenticatedUser } from '@/lib/notch-auth'
import { syncFocusDailyStats, validateFocusSyncEntries } from '@/lib/focus-ranking'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    await logAppEvent({
      req,
      eventType: focusEventTypes.syncRejected,
      outcome: 'rejected',
      source: 'desktop',
      statusCode: 401,
      metadata: focusRejectedMetadata('unauthorized'),
    })
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const deviceId = auth.deviceId
  if (!deviceId) {
    await logAppEvent({
      req,
      eventType: focusEventTypes.syncRejected,
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      statusCode: 401,
      metadata: focusRejectedMetadata('device_not_bound'),
    })
    return NextResponse.json({ detail: 'Sign in again to bind this device before syncing focus stats.' }, { status: 401 })
  }
  let entries
  try {
    const body = await req.json()
    entries = validateFocusSyncEntries(body)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Invalid focus sync payload.'
    await logAppEvent({
      req,
      eventType: focusEventTypes.syncRejected,
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 400,
      metadata: focusRejectedMetadata('invalid_payload'),
    })
    return NextResponse.json({ detail: message }, { status: 400 })
  }

  try {
    const result = await syncFocusDailyStats(
      auth.user.id,
      entries,
      deviceId,
    )

    await logAppEvent({
      req,
      eventType: focusEventTypes.syncSucceeded,
      outcome: 'success',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 200,
      metadata: focusSyncSucceededMetadata(entries.length, result.synced),
    })
    return NextResponse.json(result)
  } catch (error) {
    console.error('Failed to sync focus daily stats', error)
    await logAppEvent({
      req,
      eventType: focusEventTypes.syncFailed,
      outcome: 'failure',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 500,
      metadata: focusSyncFailedMetadata(entries.length, error),
    })
    return NextResponse.json({ detail: 'Failed to sync focus daily stats.' }, { status: 500 })
  }
}
