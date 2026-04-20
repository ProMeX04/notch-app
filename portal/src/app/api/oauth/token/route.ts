import { NextResponse } from 'next/server'

import { AuthDeviceLimitError } from '@/lib/notch-auth'
import { exchangeOAuthToken } from '@/lib/notch-oauth'

async function readTokenRequestBody(req: Request) {
  const contentType = req.headers.get('content-type')?.toLowerCase() ?? ''

  if (contentType.includes('application/x-www-form-urlencoded')) {
    const params = new URLSearchParams(await req.text())
    const body = Object.fromEntries(params.entries())
    return {
      ...body,
      trust_device: body.trust_device,
    }
  }

  return await req.json().catch(() => null)
}

export async function POST(req: Request) {
  const body = await readTokenRequestBody(req) as
    | {
        grant_type?: string
        client_id?: string
        redirect_uri?: string
        code?: string
        code_verifier?: string
        refresh_token?: string
        device_id?: string
        device_name?: string
        platform?: string
        trust_device?: string | boolean
      }
    | null

  try {
    const payload = await exchangeOAuthToken(req, body ?? {})
    if (!payload) {
      return NextResponse.json({ detail: 'OAuth code or token is invalid or expired.' }, { status: 401 })
    }

    return NextResponse.json(payload)
  } catch (error) {
    if (error instanceof AuthDeviceLimitError) {
      return NextResponse.json({ detail: error.message }, { status: error.statusCode })
    }

    return NextResponse.json(
      { detail: error instanceof Error ? error.message : 'Could not exchange OAuth token.' },
      { status: 400 },
    )
  }
}
