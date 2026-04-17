import { createHash, randomBytes } from 'node:crypto'

import prisma from '@/lib/prisma'

const ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000
const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000
const BRIDGE_TOKEN_TTL_MS = 5 * 60 * 1000
const PORTABLE_SESSION_TOKEN_PREFIX = 'nts_'

type SessionUser = {
  id: string
  email: string | null
  name: string | null
  createdAt: Date
  isPro: boolean
}

type LogoutRequestBody = {
  token?: string
  tokens?: string[]
  refresh_token?: string
}

type RefreshRequestBody = {
  refresh_token?: string
}

export type NotchPortableSession = {
  access_token: string
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
}

export type NotchAuthPayload = {
  access_token: string
  token_type: 'Bearer'
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
  session_token: string
  user: {
    id: string
    email: string
    name: string | null
    created_at: string
    is_pro: boolean
  }
}

export type NotchWebBridgePayload = {
  bridge_token: string
  expires_at: string
}

function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex')
}

function serializeUser(user: SessionUser) {
  return {
    id: user.id,
    email: user.email ?? '',
    name: user.name,
    created_at: user.createdAt.toISOString(),
    is_pro: user.isPro,
  }
}

function createPortableSessionToken(payload: NotchPortableSession): string {
  const raw = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${PORTABLE_SESSION_TOKEN_PREFIX}${raw}`
}

function buildAuthPayload(args: {
  accessToken: string
  accessExpiresAt: Date
  refreshToken: string
  refreshExpiresAt: Date
  user: SessionUser
}): NotchAuthPayload {
  const expiresAt = args.accessExpiresAt.toISOString()
  const refreshExpiresAt = args.refreshExpiresAt.toISOString()

  return {
    access_token: args.accessToken,
    token_type: 'Bearer',
    expires_at: expiresAt,
    refresh_token: args.refreshToken,
    refresh_expires_at: refreshExpiresAt,
    session_token: createPortableSessionToken({
      access_token: args.accessToken,
      expires_at: expiresAt,
      refresh_token: args.refreshToken,
      refresh_expires_at: refreshExpiresAt,
    }),
    user: serializeUser(args.user),
  }
}

export async function createAuthPayload(
  user: SessionUser,
  options: { sessionId?: string } = {},
): Promise<NotchAuthPayload> {
  const accessToken = randomBytes(32).toString('base64url')
  const refreshToken = randomBytes(48).toString('base64url')
  const accessExpiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_MS)
  const refreshExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS)

  const data = {
    tokenHash: hashToken(refreshToken),
    accessTokenHash: hashToken(accessToken),
    expiresAt: refreshExpiresAt,
    accessExpiresAt,
    revokedAt: null,
    userId: user.id,
  }

  if (options.sessionId) {
    await prisma.authSession.update({
      where: { id: options.sessionId },
      data,
    })
  } else {
    await prisma.authSession.create({ data })
  }

  return buildAuthPayload({
    accessToken,
    accessExpiresAt,
    refreshToken,
    refreshExpiresAt,
    user,
  })
}

export async function createWebBridgePayload(user: SessionUser): Promise<NotchWebBridgePayload> {
  const bridgeToken = randomBytes(24).toString('base64url')
  const expiresAt = new Date(Date.now() + BRIDGE_TOKEN_TTL_MS)

  await prisma.authBridgeToken.create({
    data: {
      tokenHash: hashToken(bridgeToken),
      expiresAt,
      userId: user.id,
    },
  })

  return {
    bridge_token: bridgeToken,
    expires_at: expiresAt.toISOString(),
  }
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

async function findSessionByAccessToken(token: string) {
  const tokenHash = hashToken(token)
  return prisma.authSession.findFirst({
    where: {
      OR: [
        { accessTokenHash: tokenHash },
        { accessTokenHash: null, tokenHash },
      ],
    },
    include: { user: true },
  })
}

export async function getAuthenticatedUser(req: Request) {
  const token = readBearerToken(req)
  if (!token) return null

  const session = await findSessionByAccessToken(token)
  if (!session) return null

  const accessExpiresAt = session.accessExpiresAt ?? session.expiresAt
  if (session.revokedAt || accessExpiresAt <= new Date()) {
    await prisma.authSession.delete({ where: { id: session.id } }).catch(() => {})
    return null
  }

  return {
    sessionId: session.id,
    user: session.user,
  }
}

function normalizedLogoutTokens(
  body: LogoutRequestBody | null,
  bearerToken: string | null,
): string[] {
  const tokens = new Set<string>()

  const register = (value: string | null | undefined) => {
    const trimmed = value?.trim()
    if (trimmed) {
      tokens.add(trimmed)
    }
  }

  register(bearerToken)
  register(body?.token)
  register(body?.refresh_token)

  if (Array.isArray(body?.tokens)) {
    for (const token of body.tokens) {
      register(token)
    }
  }

  return [...tokens]
}

export async function revokeAuthSessions(req: Request) {
  const bearerToken = readBearerToken(req)
  const body = await req.clone().json().catch(() => null) as LogoutRequestBody | null
  const tokens = normalizedLogoutTokens(body, bearerToken)

  if (tokens.length === 0) {
    return {
      hasTokens: false,
      revokedCount: 0,
    }
  }

  const tokenHashes = tokens.map(hashToken)
  const result = await prisma.authSession.updateMany({
    where: {
      OR: [
        { tokenHash: { in: tokenHashes } },
        { accessTokenHash: { in: tokenHashes } },
      ],
      revokedAt: null,
    },
    data: {
      revokedAt: new Date(),
    },
  })

  return {
    hasTokens: true,
    revokedCount: result.count,
  }
}

export async function refreshAuthSession(req: Request) {
  const body = await req.clone().json().catch(() => null) as RefreshRequestBody | null
  const refreshToken = body?.refresh_token?.trim() ?? ''
  if (!refreshToken) return null

  const session = await prisma.authSession.findUnique({
    where: { tokenHash: hashToken(refreshToken) },
    include: { user: true },
  })

  if (!session) return null

  if (session.revokedAt || session.expiresAt <= new Date()) {
    await prisma.authSession.delete({ where: { id: session.id } }).catch(() => {})
    return null
  }

  return createAuthPayload(session.user, { sessionId: session.id })
}

export async function exchangeWebBridgeToken(token: string) {
  const trimmed = token.trim()
  if (!trimmed) return null

  const bridge = await prisma.authBridgeToken.findUnique({
    where: { tokenHash: hashToken(trimmed) },
    include: { user: true },
  })

  if (!bridge) return null

  if (bridge.consumedAt || bridge.expiresAt <= new Date()) {
    await prisma.authBridgeToken.delete({ where: { id: bridge.id } }).catch(() => {})
    return null
  }

  await prisma.authBridgeToken.update({
    where: { id: bridge.id },
    data: { consumedAt: new Date() },
  })

  return createAuthPayload(bridge.user)
}

export function authUserResponse(user: SessionUser) {
  return serializeUser(user)
}
