import { NextResponse } from 'next/server'

import { getAuthenticatedUser } from '@/lib/notch-auth'
import { createOAuthAuthorizationRedirect } from '@/lib/notch-oauth'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
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
    return NextResponse.json(payload)
  } catch (error) {
    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Could not create OAuth authorization code.' },
      { status: 400 },
    )
  }
}
