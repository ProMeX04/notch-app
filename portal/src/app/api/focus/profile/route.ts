import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import {
  focusEventTypes,
  focusRejectedMetadata,
  leaderboardProfileFailedMetadata,
  leaderboardProfileUpdatedMetadata,
} from '@/lib/focus-event-policy'
import { normalizeDisplayName } from '@/lib/focus-ranking'
import { getAuthenticatedUser } from '@/lib/notch-auth'
import prisma from '@/lib/prisma'

export async function PATCH(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    await logAppEvent({
      req,
      eventType: focusEventTypes.leaderboardProfileRejected,
      outcome: 'rejected',
      source: 'desktop',
      statusCode: 401,
      metadata: focusRejectedMetadata('unauthorized'),
    })
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const deviceId = auth.deviceId
  const body = await req.json().catch(() => null) as Record<string, unknown> | null
  if (!body || typeof body.leaderboard_opt_in !== 'boolean') {
    await logAppEvent({
      req,
      eventType: focusEventTypes.leaderboardProfileRejected,
      outcome: 'rejected',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 400,
      metadata: focusRejectedMetadata('invalid_payload'),
    })
    return NextResponse.json({ detail: 'leaderboard_opt_in must be a boolean.' }, { status: 400 })
  }

  try {
    const user = await prisma.user.update({
      where: { id: auth.user.id },
      data: {
        leaderboardOptIn: body.leaderboard_opt_in,
        displayName: normalizeDisplayName(body.display_name),
      },
      select: {
        id: true,
        displayName: true,
        leaderboardOptIn: true,
      },
    })

    await logAppEvent({
      req,
      eventType: focusEventTypes.leaderboardProfileUpdated,
      outcome: 'success',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 200,
      metadata: leaderboardProfileUpdatedMetadata(user.leaderboardOptIn, user.displayName),
    })

    return NextResponse.json({
      user: {
        id: user.id,
        display_name: user.displayName,
        leaderboard_opt_in: user.leaderboardOptIn,
      },
    })
  } catch (error) {
    console.error('Failed to update focus leaderboard profile', error)
    await logAppEvent({
      req,
      eventType: focusEventTypes.leaderboardProfileFailed,
      outcome: 'failure',
      source: 'desktop',
      actorUserId: auth.user.id,
      sessionId: auth.sessionId,
      deviceId,
      statusCode: 500,
      metadata: leaderboardProfileFailedMetadata(error),
    })
    return NextResponse.json({ detail: 'Failed to update leaderboard profile.' }, { status: 500 })
  }
}
