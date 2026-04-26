import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic';

import { applyAuthCookies, clearAuthCookies, readRefreshTokenCookie } from '@/lib/auth-cookies'
import { authUserResponse, getAuthenticatedUser, refreshAuthSessionWithToken } from '@/lib/notch-auth'

export async function GET(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (auth) {
    const response = await authUserResponse(auth.user, auth.sessionId);
    return NextResponse.json(response);
  }

  const payload = await refreshAuthSessionWithToken(req, readRefreshTokenCookie(req) ?? '', {
    device_id: req.headers.get('x-notch-device-id')?.trim() ?? undefined,
  })
  if (!payload) {
    return clearAuthCookies(NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 }))
  }

  return applyAuthCookies(
    NextResponse.json({
      ...payload.user,
      current_session_id: payload.session.id,
      max_active_devices: payload.max_active_devices,
    }),
    payload,
  )
}
