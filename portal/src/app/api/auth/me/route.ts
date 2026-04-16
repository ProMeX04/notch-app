import { NextResponse } from 'next/server'

import { authUserResponse, getAuthenticatedUser } from '@/lib/notch-auth'

export async function GET(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  return NextResponse.json(authUserResponse(auth.user))
}
