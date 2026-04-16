import { NextResponse } from 'next/server'

import { createWebBridgePayload, getAuthenticatedUser } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const payload = await createWebBridgePayload(auth.user)
  return NextResponse.json(payload)
}
