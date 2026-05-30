import { createHash, createHmac, timingSafeEqual } from 'node:crypto'

const PORTABLE_SESSION_TOKEN_PREFIX = 'nts_'

export type NotchPortableSession = {
  access_token: string
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
}

type BridgeBackedSessionToken = {
  token_kind: 'bridge'
  bridge_token: string
  access_token: string
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
}

export type DecodedSessionToken =
  | {
      kind: 'bridge'
      bridgeToken: string
    }
  | {
      kind: 'portable'
      accessToken: string
      refreshToken: string
    }

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

export function readBearerToken(req: Request): string | null {
  const authHeader = req.headers.get('authorization')?.trim()
  if (!authHeader) return null

  const [scheme, token] = authHeader.split(/\s+/, 2)
  if (!scheme || !token || scheme.toLowerCase() !== 'bearer') {
    return null
  }

  return token
}

export function readCookie(req: Request, name: string): string | null {
  const header = req.headers.get('cookie')
  if (!header) return null

  for (const part of header.split(';')) {
    const [rawName, ...rest] = part.split('=')
    if (rawName?.trim() !== name) continue
    const value = rest.join('=').trim()
    if (!value) return null

    try {
      return decodeURIComponent(value)
    } catch {
      return value
    }
  }

  return null
}

export function encodeSessionToken(payload: NotchPortableSession | BridgeBackedSessionToken): string {
  const raw = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${PORTABLE_SESSION_TOKEN_PREFIX}${raw}`
}

export function createBridgeBackedSessionToken(bridgeToken: string, expiresAt: string): string {
  return encodeSessionToken({
    token_kind: 'bridge',
    bridge_token: bridgeToken,
    access_token: '',
    expires_at: expiresAt,
    refresh_token: '',
    refresh_expires_at: expiresAt,
  })
}

export function decodeSessionToken(token: string): DecodedSessionToken | null {
  const trimmed = token.trim()
  if (!trimmed.startsWith(PORTABLE_SESSION_TOKEN_PREFIX)) return null

  const encoded = trimmed.slice(PORTABLE_SESSION_TOKEN_PREFIX.length)
  try {
    const decoded = Buffer.from(encoded, 'base64url').toString('utf8')
    const parsed = JSON.parse(decoded) as Partial<NotchPortableSession & BridgeBackedSessionToken>

    if (parsed.token_kind === 'bridge' && typeof parsed.bridge_token === 'string') {
      return {
        kind: 'bridge',
        bridgeToken: parsed.bridge_token,
      }
    }

    if (
      typeof parsed.access_token !== 'string' ||
      typeof parsed.expires_at !== 'string' ||
      typeof parsed.refresh_token !== 'string' ||
      typeof parsed.refresh_expires_at !== 'string'
    ) {
      return null
    }

    return {
      kind: 'portable',
      accessToken: parsed.access_token,
      refreshToken: parsed.refresh_token,
    }
  } catch {
    return null
  }
}

export type JWTPayload = {
  userId: string
  email: string | null
  name: string | null
  displayName: string | null
  avatarUrl: string | null
  isPro: boolean
  isAdmin: boolean
  leaderboardOptIn: boolean
  userCreatedAt: string
  sessionId: string
  deviceId: string | null
  iat?: number
  exp?: number
}

function getJwtSecret(): string {
  const secret = process.env.JWT_SECRET?.trim()
  if (!secret) {
    return 'development-secret-key-notch-default-change-in-production'
  }
  return secret
}

function base64UrlEncode(str: string): string {
  return Buffer.from(str).toString('base64url')
}

function base64UrlDecode(str: string): string {
  return Buffer.from(str, 'base64url').toString('utf8')
}

export function signJWT(payload: Omit<JWTPayload, 'iat' | 'exp'>, expiresInMs: number): string {
  const secret = getJwtSecret()
  const header = { alg: 'HS256', typ: 'JWT' }
  const now = Date.now()
  const fullPayload = {
    ...payload,
    iat: Math.floor(now / 1000),
    exp: Math.floor((now + expiresInMs) / 1000),
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedPayload = base64UrlEncode(JSON.stringify(fullPayload))

  const hmac = createHmac('sha256', secret)
  hmac.update(`${encodedHeader}.${encodedPayload}`)
  const signature = hmac.digest('base64url')

  return `${encodedHeader}.${encodedPayload}.${signature}`
}

export function verifyJWT(token: string): JWTPayload | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null

    const [encodedHeader, encodedPayload, signature] = parts
    const secret = getJwtSecret()

    const hmac = createHmac('sha256', secret)
    hmac.update(`${encodedHeader}.${encodedPayload}`)
    const expectedSignature = hmac.digest('base64url')

    const signatureBuf = Buffer.from(signature)
    const expectedBuf = Buffer.from(expectedSignature)
    if (signatureBuf.length !== expectedBuf.length) {
      return null
    }

    if (!timingSafeEqual(signatureBuf, expectedBuf)) {
      return null
    }

    const payload = JSON.parse(base64UrlDecode(encodedPayload)) as JWTPayload
    const nowSeconds = Math.floor(Date.now() / 1000)
    if (payload.exp && nowSeconds >= payload.exp) {
      return null
    }

    return payload
  } catch {
    return null
  }
}

