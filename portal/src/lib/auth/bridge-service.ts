import { randomBytes } from 'node:crypto'

import type {
  AppLoginBridgeExchangeResult,
  AuthDeviceInput,
  DatabaseClient,
  NotchAppLoginBridgePayload,
  NotchWebBridgePayload,
  SessionUser,
} from '@/lib/auth/auth-types'
import { buildNormalizedDevice } from '@/lib/auth/device-service'
import { issueDeviceBoundAuthPayload } from '@/lib/auth/session-service'
import {
  decodeSessionToken,
  hashToken,
} from '@/lib/auth/token-service'
import { getAuthenticatedUser } from '@/lib/auth/session-query-service'
import prisma from '@/lib/prisma'

const BRIDGE_TOKEN_TTL_MS = 5 * 60 * 1000

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

export async function createAppLoginBridgePayload(args: {
  req?: Request
  device?: AuthDeviceInput | null
} = {}): Promise<NotchAppLoginBridgePayload> {
  const bridgeToken = randomBytes(24).toString('base64url')
  const expiresAt = new Date(Date.now() + BRIDGE_TOKEN_TTL_MS)
  const normalizedDevice = buildNormalizedDevice({
    req: args.req,
    input: args.device,
    userKey: `app-login-bridge:${bridgeToken}`,
  })

  await prisma.authAppBridgeToken.create({
    data: {
      tokenHash: hashToken(bridgeToken),
      deviceId: normalizedDevice.deviceId,
      deviceName: normalizedDevice.deviceName,
      platform: normalizedDevice.platform,
      expiresAt,
    },
  })

  return {
    bridge_token: bridgeToken,
    expires_at: expiresAt.toISOString(),
  }
}

export async function exchangePortableSessionToken(
  req: Request,
  rawToken: string,
  device?: AuthDeviceInput | null,
) {
  const sessionToken = decodeSessionToken(rawToken)
  if (!sessionToken) return null

  if (sessionToken.kind === 'bridge') {
    return exchangeWebBridgeToken(req, sessionToken.bridgeToken, device)
  }

  return prisma.$transaction(async (tx) => {
    const now = new Date()
    const sourceSession = await tx.authSession.findFirst({
      where: {
        tokenHash: hashToken(sessionToken.refreshToken),
        accessTokenHash: hashToken(sessionToken.accessToken),
      },
      include: { user: true },
    })

    if (!sourceSession) return null
    if (sourceSession.revokedAt || sourceSession.expiresAt <= now) {
      if (!sourceSession.revokedAt) {
        await tx.authSession.update({
          where: { id: sourceSession.id },
          data: {
            revokedAt: now,
            revokedReason: 'expired',
          },
        }).catch(() => {})
      }
      return null
    }

    const revoked = await tx.authSession.updateMany({
      where: {
        id: sourceSession.id,
        revokedAt: null,
        expiresAt: { gt: now },
      },
      data: {
        revokedAt: now,
        revokedReason: 'session_token_exchanged',
      },
    })

    if (revoked.count !== 1) {
      return null
    }

    return issueDeviceBoundAuthPayload({
      tx,
      user: sourceSession.user,
      req,
      device,
    })
  })
}

export async function exchangeWebBridgeToken(
  req: Request,
  token: string,
  device?: AuthDeviceInput | null,
) {
  const trimmed = token.trim()
  if (!trimmed) return null

  return prisma.$transaction(async (tx) => {
    const now = new Date()
    const bridge = await tx.authBridgeToken.findUnique({
      where: { tokenHash: hashToken(trimmed) },
      include: { user: true },
    })

    if (!bridge) return null

    if (bridge.consumedAt || bridge.expiresAt <= now) {
      await tx.authBridgeToken.delete({ where: { id: bridge.id } }).catch(() => {})
      return null
    }

    const consumed = await tx.authBridgeToken.updateMany({
      where: {
        id: bridge.id,
        consumedAt: null,
        expiresAt: { gt: now },
      },
      data: { consumedAt: now },
    })

    if (consumed.count !== 1) {
      return null
    }

    return issueDeviceBoundAuthPayload({
      tx,
      user: bridge.user,
      req,
      device,
    })
  })
}

type StoredAppBridge = {
  id: string
  expiresAt: Date
  completedAt: Date | null
  consumedAt: Date | null
  deviceId: string | null
  user: SessionUser | null
}

async function findAppLoginBridge(
  tx: DatabaseClient,
  token: string,
): Promise<StoredAppBridge | null> {
  const bridge = await tx.authAppBridgeToken.findUnique({
    where: { tokenHash: hashToken(token) },
    include: { user: true },
  })

  if (!bridge) return null

  return {
    id: bridge.id,
    expiresAt: bridge.expiresAt,
    completedAt: bridge.completedAt,
    consumedAt: bridge.consumedAt,
    deviceId: bridge.deviceId,
    user: bridge.user,
  }
}

export async function completeAppLoginBridgeToken(req: Request, rawToken: string) {
  const trimmed = rawToken.trim()
  if (!trimmed) return { status: 'invalid' as const }

  const auth = await getAuthenticatedUser(req)
  if (!auth) return { status: 'unauthorized' as const }

  return prisma.$transaction(async (tx) => {
    const now = new Date()
    const bridge = await findAppLoginBridge(tx, trimmed)
    if (!bridge) return { status: 'invalid' as const }

    if (bridge.expiresAt <= now) {
      await tx.authAppBridgeToken.delete({ where: { id: bridge.id } }).catch(() => {})
      return { status: 'expired' as const }
    }

    if (bridge.consumedAt) {
      return { status: 'invalid' as const }
    }

    if (bridge.completedAt) {
      return bridge.user?.id === auth.user.id
        ? { status: 'completed' as const }
        : { status: 'invalid' as const }
    }

    const completed = await tx.authAppBridgeToken.updateMany({
      where: {
        id: bridge.id,
        completedAt: null,
        consumedAt: null,
        expiresAt: { gt: now },
      },
      data: {
        completedAt: now,
        userId: auth.user.id,
      },
    })

    return completed.count === 1
      ? { status: 'completed' as const }
      : { status: 'invalid' as const }
  })
}

export async function exchangeAppLoginBridgeToken(
  req: Request,
  rawToken: string,
  device?: AuthDeviceInput | null,
): Promise<AppLoginBridgeExchangeResult> {
  const trimmed = rawToken.trim()
  if (!trimmed) {
    return { status: 'invalid' }
  }

  return prisma.$transaction(async (tx) => {
    const now = new Date()
    const bridge = await findAppLoginBridge(tx, trimmed)
    if (!bridge) {
      return { status: 'invalid' }
    }

    if (bridge.consumedAt) {
      return { status: 'invalid' }
    }

    if (bridge.expiresAt <= now) {
      await tx.authAppBridgeToken.delete({ where: { id: bridge.id } }).catch(() => {})
      return { status: 'expired' }
    }

    if (!bridge.completedAt || !bridge.user) {
      return {
        status: 'pending',
        expires_at: bridge.expiresAt.toISOString(),
      }
    }

    const normalizedDevice = buildNormalizedDevice({
      req,
      input: device,
      userKey: bridge.user.id,
      existingDevice: bridge.deviceId
        ? {
            deviceId: bridge.deviceId,
            deviceName: null,
            platform: null,
            trustedAt: null,
          }
        : null,
    })

    if (bridge.deviceId && normalizedDevice.deviceId !== bridge.deviceId) {
      return { status: 'invalid' }
    }

    const consumed = await tx.authAppBridgeToken.updateMany({
      where: {
        id: bridge.id,
        completedAt: { not: null },
        consumedAt: null,
        expiresAt: { gt: now },
      },
      data: {
        consumedAt: now,
      },
    })

    if (consumed.count !== 1) {
      return { status: 'invalid' }
    }

    const payload = await issueDeviceBoundAuthPayload({
      tx,
      user: bridge.user,
      req,
      device,
    })

    return {
      status: 'ready',
      payload,
    }
  })
}
