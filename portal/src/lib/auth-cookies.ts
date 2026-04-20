import type { NextResponse } from 'next/server'

import type { NotchAuthPayload } from '@/lib/notch-auth'
import { readCookie } from '@/lib/notch-auth'

const ACCESS_COOKIE = 'notch_access_token'
const REFRESH_COOKIE = 'notch_refresh_token'

function isSecureCookie() {
  return process.env.NODE_ENV === 'production'
}

function cookieOptions(expiresAt: string, httpOnly = true) {
  const parsed = new Date(expiresAt)

  return {
    httpOnly,
    secure: isSecureCookie(),
    sameSite: 'lax' as const,
    path: '/',
    expires: Number.isNaN(parsed.getTime()) ? undefined : parsed,
  }
}

export function applyAuthCookies(response: NextResponse, payload: NotchAuthPayload) {
  response.cookies.set(ACCESS_COOKIE, payload.access_token, cookieOptions(payload.expires_at))
  response.cookies.set(REFRESH_COOKIE, payload.refresh_token, cookieOptions(payload.refresh_expires_at))
  return response
}

export function clearAuthCookies(response: NextResponse) {
  response.cookies.set(ACCESS_COOKIE, '', {
    httpOnly: true,
    secure: isSecureCookie(),
    sameSite: 'lax',
    path: '/',
    expires: new Date(0),
  })
  response.cookies.set(REFRESH_COOKIE, '', {
    httpOnly: true,
    secure: isSecureCookie(),
    sameSite: 'lax',
    path: '/',
    expires: new Date(0),
  })
  return response
}

export function readRefreshTokenCookie(req: Request) {
  return readCookie(req, REFRESH_COOKIE)
}
