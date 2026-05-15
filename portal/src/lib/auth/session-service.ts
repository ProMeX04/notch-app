import { randomBytes } from 'node:crypto'

import type {
  AuthDeviceInput,
  DatabaseClient,
  LogoutRequestBody,
  NotchAuthPayload,
  RefreshRequestBody,
  SessionUser,
} from '@/lib/auth/auth-types'
import {
  buildNormalizedDevice,
  enforceActiveDeviceLimit,
  markExpiredSessions,
  MAX_ACTIVE_DEVICES,
  revokeSessionsByIds,
  resolveTrustedDevice,
} from '@/lib/auth/device-service'
import {
  createBridgeBackedSessionToken,
  hashToken,
  readBearerToken,
} from '@/lib/auth/token-service'
import { readCookie } from '@/lib/auth/token-service'
import { serializeUser } from '@/lib/auth/user-service'
import { getAuthenticatedUser } from '@/lib/auth/session-query-service'
import prisma from '@/lib/prisma'

const ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000
const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000
const BRIDGE_TOKEN_TTL_MS = 5 * 60 * 1000
const ACCESS_COOKIE = 'notch_access_token'

async function buildAuthPayload(args: {
  accessToken: string
  accessExpiresAt: Date
  refreshToken: string
  refreshExpiresAt: Date
  user: SessionUser
  session: {
    id: string
    deviceId: string
    deviceName: string
    platform: string
    trustedAt: Date | null
  }
  sessionToken?: string
}): Promise<NotchAuthPayload> {
  const expiresAt = args.accessExpiresAt.toISOString()
  const refreshExpiresAt = args.refreshExpiresAt.toISOString()

  const payload: NotchAuthPayload = {
    access_token: args.accessToken,
    token_type: 'Bearer',
    expires_at: expiresAt,
    refresh_token: args.refreshToken,
    refresh_expires_at: refreshExpiresAt,
    user: await serializeUser(args.user),
    session: {
      id: args.session.id,
      device_id: args.session.deviceId,
      device_name: args.session.deviceName,
      platform: args.session.platform,
      trusted_at: args.session.trustedAt?.toISOString() ?? null,
    },
    max_active_devices: MAX_ACTIVE_DEVICES,
  }

  if (args.sessionToken) {
    payload.session_token = args.sessionToken
  }

  return payload
}

export async function issueDeviceBoundAuthPayload(args: {
  tx: DatabaseClient
  user: SessionUser
  req?: Request
  device?: AuthDeviceInput | null
  issueSessionToken?: boolean
}): Promise<NotchAuthPayload> {
  const { tx, user, req } = args
  const now = new Date()
  const accessToken = randomBytes(32).toString('base64url')
  const refreshToken = randomBytes(48).toString('base64url')
  const accessExpiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_MS)
  const refreshExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS)

  const { trustedDevice, normalizedDevice } = await resolveTrustedDevice({
    tx,
    userId: user.id,
    req,
    input: args.device,
    userKey: user.id,
  })

  const existingActiveSessions = await tx.authSession.findMany({
    where: {
      userId: user.id,
      deviceId: normalizedDevice.deviceId,
      revokedAt: null,
      expiresAt: { gt: now },
    },
    select: { id: true },
  })
  await revokeSessionsByIds(
    tx,
    existingActiveSessions.map((session) => session.id),
    'replaced',
  )

  await enforceActiveDeviceLimit(tx, user.id, normalizedDevice.deviceId)

  const trustedAt = normalizedDevice.trustDevice ? now : trustedDevice?.trustedAt ?? null
  const session = await tx.authSession.create({
    data: {
      tokenHash: hashToken(refreshToken),
      accessTokenHash: hashToken(accessToken),
      expiresAt: refreshExpiresAt,
      accessExpiresAt,
      lastSeenAt: now,
      trustedAt,
      deviceId: normalizedDevice.deviceId,
      deviceName: normalizedDevice.deviceName,
      platform: normalizedDevice.platform,
      revokedAt: null,
      revokedReason: null,
      userId: user.id,
    },
    select: {
      id: true,
      deviceId: true,
      deviceName: true,
      platform: true,
      trustedAt: true,
    },
  })

  let sessionToken: string | undefined
  if (args.issueSessionToken) {
    const bridgeToken = randomBytes(24).toString('base64url')
    const bridgeExpiresAt = new Date(Date.now() + BRIDGE_TOKEN_TTL_MS)

    await tx.authBridgeToken.create({
      data: {
        tokenHash: hashToken(bridgeToken),
        expiresAt: bridgeExpiresAt,
        userId: user.id,
      },
    })

    sessionToken = createBridgeBackedSessionToken(bridgeToken, bridgeExpiresAt.toISOString())
  }

  return buildAuthPayload({
    accessToken,
    accessExpiresAt,
    refreshToken,
    refreshExpiresAt,
    sessionToken,
    user,
    session: {
      id: session.id,
      deviceId: session.deviceId ?? normalizedDevice.deviceId,
      deviceName: session.deviceName ?? normalizedDevice.deviceName,
      platform: session.platform ?? normalizedDevice.platform,
      trustedAt: session.trustedAt,
    },
  })
}

async function rotateExistingSession(args: {
  tx: DatabaseClient
  user: SessionUser
  req?: Request
  sessionId: string
  device?: AuthDeviceInput | null
  issueSessionToken?: boolean
}): Promise<NotchAuthPayload> {
  const { tx, user, sessionId, req } = args
  const existing = await tx.authSession.findUnique({
    where: { id: sessionId },
    select: {
      id: true,
      userId: true,
      deviceId: true,
      deviceName: true,
      platform: true,
      trustedAt: true,
    },
  })

  if (!existing || existing.userId !== user.id) {
    throw new Error('Session not found.')
  }

  const normalizedDevice = buildNormalizedDevice({
    req,
    input: args.device,
    userKey: `${user.id}:${sessionId}`,
    existingDevice: existing,
  })

  const accessToken = randomBytes(32).toString('base64url')
  const refreshToken = randomBytes(48).toString('base64url')
  const accessExpiresAt = new Date(Date.now() + ACCESS_TOKEN_TTL_MS)
  const refreshExpiresAt = new Date(Date.now() + REFRESH_TOKEN_TTL_MS)
  const trustedAt = normalizedDevice.trustDevice ? new Date() : existing.trustedAt

  const session = await tx.authSession.update({
    where: { id: sessionId },
    data: {
      tokenHash: hashToken(refreshToken),
      accessTokenHash: hashToken(accessToken),
      expiresAt: refreshExpiresAt,
      accessExpiresAt,
      lastSeenAt: new Date(),
      trustedAt,
      deviceId: normalizedDevice.deviceId,
      deviceName: normalizedDevice.deviceName,
      platform: normalizedDevice.platform,
      revokedAt: null,
      revokedReason: null,
    },
    select: {
      id: true,
      deviceId: true,
      deviceName: true,
      platform: true,
      trustedAt: true,
    },
  })

  let sessionToken: string | undefined
  if (args.issueSessionToken) {
    const bridgeToken = randomBytes(24).toString('base64url')
    const bridgeExpiresAt = new Date(Date.now() + BRIDGE_TOKEN_TTL_MS)

    await tx.authBridgeToken.create({
      data: {
        tokenHash: hashToken(bridgeToken),
        expiresAt: bridgeExpiresAt,
        userId: user.id,
      },
    })

    sessionToken = createBridgeBackedSessionToken(bridgeToken, bridgeExpiresAt.toISOString())
  }

  return buildAuthPayload({
    accessToken,
    accessExpiresAt,
    refreshToken,
    refreshExpiresAt,
    sessionToken,
    user,
    session: {
      id: session.id,
      deviceId: session.deviceId ?? normalizedDevice.deviceId,
      deviceName: session.deviceName ?? normalizedDevice.deviceName,
      platform: session.platform ?? normalizedDevice.platform,
      trustedAt: session.trustedAt,
    },
  })
}

export async function createAuthPayload(
  user: SessionUser,
  options: {
    sessionId?: string
    req?: Request
    device?: AuthDeviceInput | null
    issueSessionToken?: boolean
  } = {},
): Promise<NotchAuthPayload> {
  return prisma.$transaction((tx) => createAuthPayloadInTransaction(tx, user, options))
}

export async function createAuthPayloadInTransaction(
  tx: DatabaseClient,
  user: SessionUser,
  options: {
    sessionId?: string
    req?: Request
    device?: AuthDeviceInput | null
    issueSessionToken?: boolean
  } = {},
): Promise<NotchAuthPayload> {
  await markExpiredSessions(tx, user.id)

  if (options.sessionId) {
    return rotateExistingSession({
      tx,
      user,
      req: options.req,
      sessionId: options.sessionId,
      device: options.device,
      issueSessionToken: options.issueSessionToken,
    })
  }

  return issueDeviceBoundAuthPayload({
    tx,
    user,
    req: options.req,
    device: options.device,
    issueSessionToken: options.issueSessionToken,
  })
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
  const cookieToken = readCookie(req, ACCESS_COOKIE)
  const body = await req.clone().json().catch(() => null) as LogoutRequestBody | null
  const tokens = normalizedLogoutTokens(body, bearerToken || cookieToken)

  if (!body?.device_id && !body?.session_id && tokens.length === 0) {
    return {
      hasTokens: false,
      revokedCount: 0,
    }
  }

  const auth = await getAuthenticatedUser(req)
  const now = new Date()
  let eventUserId = auth?.user.id ?? null
  let eventSessionId = auth?.sessionId ?? null
  let eventDeviceId = body?.device_id?.trim() || null

  let revokedCount = 0
  if (tokens.length > 0) {
    const tokenHashes = tokens.map(hashToken)
    const eventSession = await prisma.authSession.findFirst({
      where: {
        OR: [
          { tokenHash: { in: tokenHashes } },
          { accessTokenHash: { in: tokenHashes } },
        ],
      },
      select: {
        id: true,
        userId: true,
        deviceId: true,
      },
    })
    eventUserId = eventUserId ?? eventSession?.userId ?? null
    eventSessionId = eventSessionId ?? eventSession?.id ?? null
    eventDeviceId = eventDeviceId ?? eventSession?.deviceId ?? null

    const result = await prisma.authSession.updateMany({
      where: {
        OR: [
          { tokenHash: { in: tokenHashes } },
          { accessTokenHash: { in: tokenHashes } },
        ],
        revokedAt: null,
      },
      data: {
        revokedAt: now,
        revokedReason: 'logout',
      },
    })
    revokedCount += result.count
  }

  if (auth && body?.session_id) {
    const result = await prisma.authSession.updateMany({
      where: {
        id: body.session_id.trim(),
        userId: auth.user.id,
        revokedAt: null,
      },
      data: {
        revokedAt: now,
        revokedReason: 'logout',
      },
    })
    revokedCount += result.count
  }

  if (auth && body?.device_id?.trim()) {
    const result = await prisma.authSession.updateMany({
      where: {
        userId: auth.user.id,
        deviceId: body.device_id.trim(),
        revokedAt: null,
      },
      data: {
        revokedAt: now,
        revokedReason: 'logout',
      },
    })
    revokedCount += result.count
  }

  return {
    hasTokens: true,
    revokedCount,
    userId: eventUserId,
    sessionId: eventSessionId,
    deviceId: eventDeviceId,
  }
}

export async function refreshAuthSessionWithToken(
  req: Request,
  refreshToken: string,
  device?: AuthDeviceInput | null,
) {
  const normalizedRefreshToken = refreshToken.trim()
  if (!normalizedRefreshToken) return null

  const session = await prisma.authSession.findUnique({
    where: { tokenHash: hashToken(normalizedRefreshToken) },
    include: { user: true },
  })

  if (!session) return null

  if (session.revokedAt || session.expiresAt <= new Date()) {
    if (!session.revokedAt) {
      await prisma.authSession.update({
        where: { id: session.id },
        data: {
          revokedAt: new Date(),
          revokedReason: 'expired',
        },
      }).catch(() => {})
    }
    return null
  }

  return createAuthPayload(session.user, {
    sessionId: session.id,
    req,
    device,
  })
}

export async function refreshAuthSession(req: Request) {
  const body = await req.clone().json().catch(() => null) as RefreshRequestBody | null
  return refreshAuthSessionWithToken(req, body?.refresh_token ?? '', body)
}
