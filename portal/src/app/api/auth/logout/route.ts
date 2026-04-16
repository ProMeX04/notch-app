import { NextResponse } from 'next/server'

import { deleteAuthSession, getAuthenticatedUser } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  await deleteAuthSession(req)
  return new NextResponse(null, { status: 204 })
}
