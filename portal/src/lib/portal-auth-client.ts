'use client'

const AUTH_SESSION_STORAGE_KEY = 'notch:authSession'
const PENDING_LOGOUT_TOKENS_STORAGE_KEY = 'notch:pendingLogoutTokens'
const ACCESS_TOKEN_REFRESH_SKEW_MS = 60 * 1000

export type StoredAuthSession = {
  accessToken: string
  expiresAt: string
  refreshToken: string
  refreshExpiresAt: string
}

export type AuthSessionPayload = {
  access_token: string
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
}

function isStoredAuthSession(value: unknown): value is StoredAuthSession {
  if (!value || typeof value !== 'object') return false
  const candidate = value as Partial<StoredAuthSession>
  return (
    typeof candidate.accessToken === 'string' &&
    typeof candidate.expiresAt === 'string' &&
    typeof candidate.refreshToken === 'string' &&
    typeof candidate.refreshExpiresAt === 'string'
  )
}

function mapPayloadToSession(payload: AuthSessionPayload): StoredAuthSession {
  return {
    accessToken: payload.access_token,
    expiresAt: payload.expires_at,
    refreshToken: payload.refresh_token,
    refreshExpiresAt: payload.refresh_expires_at,
  }
}

function hasExpired(expiresAt: string, skewMs = 0) {
  const parsed = Date.parse(expiresAt)
  if (Number.isNaN(parsed)) return true
  return parsed <= Date.now() + skewMs
}

function readPendingLogoutTokens(): string[] {
  try {
    const raw = window.localStorage.getItem(PENDING_LOGOUT_TOKENS_STORAGE_KEY)
    if (!raw) return []

    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []

    return parsed
      .map((value) => (typeof value === 'string' ? value.trim() : ''))
      .filter(Boolean)
  } catch {
    return []
  }
}

function writePendingLogoutTokens(tokens: string[]) {
  if (tokens.length === 0) {
    window.localStorage.removeItem(PENDING_LOGOUT_TOKENS_STORAGE_KEY)
    return
  }

  window.localStorage.setItem(PENDING_LOGOUT_TOKENS_STORAGE_KEY, JSON.stringify(tokens))
}

function queuePendingLogoutTokens(tokens: string[]) {
  const merged = new Set(readPendingLogoutTokens())
  for (const token of tokens) {
    const trimmed = token.trim()
    if (trimmed) merged.add(trimmed)
  }
  writePendingLogoutTokens([...merged])
}

function logoutRequestPayload(tokens: string[]) {
  return JSON.stringify({ tokens })
}

export function storeAuthSession(payload: AuthSessionPayload) {
  window.localStorage.setItem(
    AUTH_SESSION_STORAGE_KEY,
    JSON.stringify(mapPayloadToSession(payload)),
  )
}

export function readAuthSession(): StoredAuthSession | null {
  try {
    const raw = window.localStorage.getItem(AUTH_SESSION_STORAGE_KEY)
    if (!raw) return null

    const parsed = JSON.parse(raw)
    if (!isStoredAuthSession(parsed)) return null
    return parsed
  } catch {
    return null
  }
}

export function readAccessToken() {
  return readAuthSession()?.accessToken ?? null
}

export function clearAuthSession() {
  window.localStorage.removeItem(AUTH_SESSION_STORAGE_KEY)
}

export async function flushPendingLogoutTokens() {
  const tokens = readPendingLogoutTokens()
  if (tokens.length === 0) return true

  try {
    const response = await fetch('/api/auth/logout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: logoutRequestPayload(tokens),
      keepalive: true,
    })

    if (!response.ok) return false

    writePendingLogoutTokens([])
    return true
  } catch {
    return false
  }
}

async function refreshStoredAuthSession() {
  const session = readAuthSession()
  if (!session) return null

  if (hasExpired(session.refreshExpiresAt)) {
    queuePendingLogoutTokens([session.accessToken, session.refreshToken])
    clearAuthSession()
    return null
  }

  const response = await fetch('/api/auth/refresh', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ refresh_token: session.refreshToken }),
  })

  if (!response.ok) {
    queuePendingLogoutTokens([session.accessToken, session.refreshToken])
    clearAuthSession()
    return null
  }

  const payload = await response.json() as AuthSessionPayload
  storeAuthSession(payload)
  return mapPayloadToSession(payload)
}

export async function getValidAccessToken() {
  const session = readAuthSession()
  if (!session) return null

  if (hasExpired(session.refreshExpiresAt)) {
    queuePendingLogoutTokens([session.accessToken, session.refreshToken])
    clearAuthSession()
    return null
  }

  if (!hasExpired(session.expiresAt, ACCESS_TOKEN_REFRESH_SKEW_MS)) {
    return session.accessToken
  }

  const refreshed = await refreshStoredAuthSession()
  return refreshed?.accessToken ?? null
}

export async function authenticatedFetch(
  input: RequestInfo | URL,
  init: RequestInit = {},
): Promise<Response> {
  let accessToken = await getValidAccessToken()
  let headers = new Headers(init.headers)
  if (accessToken) {
    headers.set('Authorization', `Bearer ${accessToken}`)
  }

  let response = await fetch(input, { ...init, headers })
  if (response.status !== 401) {
    return response
  }

  const refreshed = await refreshStoredAuthSession()
  headers = new Headers(init.headers)
  accessToken = refreshed?.accessToken ?? null
  if (accessToken) {
    headers.set('Authorization', `Bearer ${accessToken}`)
  } else {
    headers.delete('Authorization')
  }

  response = await fetch(input, { ...init, headers })
  return response
}

export function signOutImmediately() {
  const session = readAuthSession()
  if (!session) {
    clearAuthSession()
    return
  }

  const tokens = [session.accessToken, session.refreshToken]
  queuePendingLogoutTokens(tokens)
  clearAuthSession()

  try {
    const payload = logoutRequestPayload(tokens)
    const blob = new Blob([payload], { type: 'application/json' })
    window.navigator.sendBeacon?.('/api/auth/logout', blob)
  } catch {}

  void fetch('/api/auth/logout', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: logoutRequestPayload(tokens),
    keepalive: true,
  })
    .then((response) => {
      if (!response.ok) return
      writePendingLogoutTokens(readPendingLogoutTokens().filter((value) => !tokens.includes(value)))
    })
    .catch(() => {})
}
