import { NextResponse } from 'next/server'

import { refreshAuthSession } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const payload = await refreshAuthSession(req)
  if (!payload) {
    return NextResponse.json({ detail: 'Refresh token is invalid or expired.' }, { status: 401 })
  }

  return NextResponse.json(payload)
}
