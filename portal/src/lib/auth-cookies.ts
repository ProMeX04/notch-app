import type { NextResponse } from 'next/server'

import type { NotchAuthPayload } from '@/lib/notch-auth'
import { readCookie } from '@/lib/notch-auth'

const ACCESS_COOKIE = 'notch_access_token'
const REFRESH_COOKIE = 'notch_refresh_token'

function isSecureCookie(req?: Request) {
  if (process.env.NODE_ENV !== 'production') {
    return false
  }
  
  if (req) {
    try {
      const url = new URL(req.url)
      const hostname = url.hostname.toLowerCase()
      if (hostname === 'localhost' || hostname === '127.0.0.1') {
        return false
      }
    } catch {}
  }
  
  const appUrl = process.env.NEXT_PUBLIC_APP_URL
  if (appUrl) {
    try {
      const url = new URL(appUrl)
      const hostname = url.hostname.toLowerCase()
      if (hostname === 'localhost' || hostname === '127.0.0.1') {
        return false
      }
    } catch {}
  }
  
  return true
}

function cookieOptions(expiresAt: string, httpOnly = true, req?: Request) {
  const parsed = new Date(expiresAt)

  return {
    httpOnly,
    secure: isSecureCookie(req),
    sameSite: 'lax' as const,
    path: '/',
    expires: Number.isNaN(parsed.getTime()) ? undefined : parsed,
  }
}

export function applyAuthCookies(response: NextResponse, payload: NotchAuthPayload, req?: Request) {
  response.cookies.set(ACCESS_COOKIE, payload.access_token, cookieOptions(payload.expires_at, true, req))
  response.cookies.set(REFRESH_COOKIE, payload.refresh_token, cookieOptions(payload.refresh_expires_at, true, req))
  return response
}

export function clearAuthCookies(response: NextResponse, req?: Request) {
  response.cookies.set(ACCESS_COOKIE, '', {
    httpOnly: true,
    secure: isSecureCookie(req),
    sameSite: 'lax',
    path: '/',
    expires: new Date(0),
  })
  response.cookies.set(REFRESH_COOKIE, '', {
    httpOnly: true,
    secure: isSecureCookie(req),
    sameSite: 'lax',
    path: '/',
    expires: new Date(0),
  })
  return response
}

export function readRefreshTokenCookie(req: Request) {
  return readCookie(req, REFRESH_COOKIE)
}
