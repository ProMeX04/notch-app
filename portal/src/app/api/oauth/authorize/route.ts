import { NextResponse } from 'next/server'

import { logAppEvent } from '@/lib/event-logger'
import { getAuthenticatedUser } from '@/lib/notch-auth'
import { createOAuthAuthorizationRedirect } from '@/lib/notch-oauth'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    await logAppEvent({
      req,
      eventType: 'oauth.authorize_rejected',
      outcome: 'rejected',
      source: 'oauth',
      statusCode: 401,
      metadata: { reason: 'invalid_session' },
    })
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const body = await req.json().catch(() => null) as
    | {
        client_id?: string
        redirect_uri?: string
        response_type?: string
        code_challenge?: string
        code_challenge_method?: string
        state?: string
      }
    | null

  try {
    const payload = await createOAuthAuthorizationRedirect(auth.user, body ?? {})
    await logAppEvent({
      req,
      eventType: 'oauth.authorize_succeeded',
      outcome: 'success',
      source: 'oauth',
      actorUserId: auth.user.id,
      statusCode: 200,
      metadata: { clientId: body?.client_id, responseType: body?.response_type },
    })
    return NextResponse.json(payload)
  } catch (error) {
    await logAppEvent({
      req,
      eventType: 'oauth.authorize_failed',
      outcome: 'failure',
      source: 'oauth',
      actorUserId: auth.user.id,
      statusCode: 400,
      metadata: { errorName: error instanceof Error ? error.name : 'UnknownError' },
    })
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Could not create OAuth authorization code.' },
      { status: 400 },
    )
  }
}
