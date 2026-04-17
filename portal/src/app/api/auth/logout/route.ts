import { NextResponse } from 'next/server'

import { revokeAuthSessions } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const result = await revokeAuthSessions(req)
  if (!result.hasTokens) {
    return NextResponse.json({ detail: 'Missing session token.' }, { status: 400 })
  }

  return new NextResponse(null, { status: 204 })
}
