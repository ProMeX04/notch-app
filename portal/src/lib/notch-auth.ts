import { createHash, randomBytes } from 'node:crypto'

import prisma from '@/lib/prisma'

const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000
const BRIDGE_TOKEN_TTL_MS = 5 * 60 * 1000

type SessionUser = {
  id: string
  email: string | null
  name: string | null
  createdAt: Date
  isPro: boolean
}

export type NotchAuthPayload = {
  access_token: string
  token_type: 'Bearer'
  expires_at: string
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

export async function createAuthPayload(user: SessionUser): Promise<NotchAuthPayload> {
  const accessToken = randomBytes(32).toString('base64url')
  const expiresAt = new Date(Date.now() + SESSION_TTL_MS)

  await prisma.authSession.create({
    data: {
      tokenHash: hashToken(accessToken),
      expiresAt,
      userId: user.id,
    },
  })

  return {
    access_token: accessToken,
    token_type: 'Bearer',
    expires_at: expiresAt.toISOString(),
    user: serializeUser(user),
  }
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

export async function getAuthenticatedUser(req: Request) {
  const token = readBearerToken(req)
  if (!token) return null

  const session = await prisma.authSession.findUnique({
    where: { tokenHash: hashToken(token) },
    include: { user: true },
  })

  if (!session) return null

  if (session.expiresAt <= new Date()) {
    await prisma.authSession.delete({ where: { id: session.id } }).catch(() => {})
    return null
  }

  return {
    sessionId: session.id,
    user: session.user,
  }
}

export async function deleteAuthSession(req: Request) {
  const token = readBearerToken(req)
  if (!token) return

  await prisma.authSession.deleteMany({
    where: { tokenHash: hashToken(token) },
  })
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
