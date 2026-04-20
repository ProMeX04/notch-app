import { NextResponse } from 'next/server'

import { clearAuthCookies } from '@/lib/auth-cookies'
import { revokeAuthSessions } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const result = await revokeAuthSessions(req)
  if (!result.hasTokens) {
    return clearAuthCookies(NextResponse.json({ detail: 'Missing session token.' }, { status: 400 }))
  }

  return clearAuthCookies(new NextResponse(null, { status: 204 }))
}
