import { NextResponse } from 'next/server'

import { exchangeWebBridgeToken } from '@/lib/notch-auth'

export async function POST(req: Request) {
  const body = await req.json().catch(() => null) as { token?: string } | null
  const token = body?.token?.trim() ?? ''

  if (!token) {
    return NextResponse.json({ detail: 'Missing bridge token.' }, { status: 400 })
  }

  const payload = await exchangeWebBridgeToken(token)
  if (!payload) {
    return NextResponse.json({ detail: 'Bridge token is invalid or expired.' }, { status: 401 })
  }

  return NextResponse.json(payload)
}
