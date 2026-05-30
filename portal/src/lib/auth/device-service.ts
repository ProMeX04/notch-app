import type { Prisma } from '@prisma/client'

import { hashToken } from '@/lib/auth/token-service'
import type {
  AuthDeviceInput,
  AuthDeviceSummary,
  DatabaseClient,
  NormalizedDevice,
} from '@/lib/auth/auth-types'
import { AuthDeviceLimitError } from '@/lib/auth/auth-types'
import prisma from '@/lib/prisma'

const DEFAULT_MAX_ACTIVE_DEVICES = 3

function resolvedPositiveInt(rawValue: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(rawValue ?? '', 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
}

export const MAX_ACTIVE_DEVICES = resolvedPositiveInt(
  process.env.NOTCH_MAX_ACTIVE_DEVICES,
  DEFAULT_MAX_ACTIVE_DEVICES,
)

export function isWebSession(device: { platform: string | null; deviceName: string | null }) {
  const platform = device.platform?.toLowerCase() ?? ''
  const deviceName = device.deviceName?.toLowerCase() ?? ''
  return platform === 'web' || deviceName.includes('browser')
}

function normalizeText(value: unknown, maxLength: number) {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  if (!trimmed) return null
  return trimmed.slice(0, maxLength)
}

function normalizeBoolean(value: unknown) {
  if (typeof value === 'boolean') return value
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase()
    return normalized === '1' || normalized === 'true' || normalized === 'yes'
  }
  return false
}

export function resolveStoredDeviceSelector(deviceId: string) {
  const trimmed = deviceId.trim()
  if (trimmed.startsWith('session:')) {
    const sessionId = trimmed.slice('session:'.length).trim()
    return sessionId ? { id: sessionId } : null
  }

  return trimmed ? { deviceId: trimmed } : null
}

function inferPlatform(userAgent: string) {
  const normalized = userAgent.toLowerCase()
  if (!normalized) return 'unknown'
  if (normalized.includes('mac os')) return 'macOS'
  if (normalized.includes('windows')) return 'Windows'
  if (normalized.includes('iphone') || normalized.includes('ipad') || normalized.includes('ios')) return 'iOS'
  if (normalized.includes('android')) return 'Android'
  if (normalized.includes('linux')) return 'Linux'
  return 'Browser'
}

function inferDeviceName(platform: string, userAgent: string) {
  if (platform === 'Browser') {
    if (userAgent.includes('Chrome')) return 'Chrome Browser'
    if (userAgent.includes('Safari')) return 'Safari Browser'
    if (userAgent.includes('Firefox')) return 'Firefox Browser'
    return 'Web Browser'
  }
  if (platform === 'unknown') return 'Unknown device'
  return platform
}

export function buildNormalizedDevice(args: {
  req?: Request
  input?: AuthDeviceInput | null
  userKey: string
  existingDevice?: { deviceId: string | null; deviceName: string | null; platform: string | null; trustedAt: Date | null } | null
}): NormalizedDevice {
  const userAgent = args.req?.headers.get('user-agent')?.trim() ?? ''
  const rawDeviceId = normalizeText(args.input?.device_id, 128)
  const deviceId =
    rawDeviceId ??
    args.existingDevice?.deviceId ??
    `generated_${hashToken(`${args.userKey}:${userAgent || 'unknown-device'}`).slice(0, 24)}`

  const platform =
    normalizeText(args.input?.platform, 64) ??
    args.existingDevice?.platform ??
    inferPlatform(userAgent)

  const deviceName =
    normalizeText(args.input?.device_name, 120) ??
    args.existingDevice?.deviceName ??
    inferDeviceName(platform, userAgent)

  return {
    deviceId,
    deviceName,
    platform,
    trustDevice: normalizeBoolean(args.input?.trust_device),
  }
}

export async function markExpiredSessions(tx: DatabaseClient, userId?: string) {
  const now = new Date()
  await tx.authSession.updateMany({
    where: {
      revokedAt: null,
      expiresAt: { lte: now },
      ...(userId ? { userId } : {}),
    },
    data: {
      revokedAt: now,
      revokedReason: 'expired',
    },
  })
}

async function findTrustedDeviceState(tx: DatabaseClient, userId: string, deviceId: string) {
  return tx.authSession.findFirst({
    where: {
      userId,
      deviceId,
      trustedAt: { not: null },
    },
    orderBy: [{ trustedAt: 'desc' }, { updatedAt: 'desc' }],
    select: {
      trustedAt: true,
      deviceId: true,
      deviceName: true,
      platform: true,
    },
  })
}

export async function revokeSessionsByIds(
  tx: DatabaseClient,
  sessionIds: string[],
  reason: string,
) {
  if (sessionIds.length === 0) return
  await tx.authSession.updateMany({
    where: {
      id: { in: sessionIds },
      revokedAt: null,
    },
    data: {
      revokedAt: new Date(),
      revokedReason: reason,
    },
  })
}

export async function enforceActiveDeviceLimit(
  tx: DatabaseClient,
  userId: string,
  currentDevice: { deviceId: string; platform: string | null; deviceName: string | null },
) {
  if (isWebSession(currentDevice)) {
    return
  }

  const activeSessions = await tx.authSession.findMany({
    where: {
      userId,
      revokedAt: null,
      expiresAt: { gt: new Date() },
      deviceId: { not: currentDevice.deviceId },
    },
    select: {
      id: true,
      deviceId: true,
      deviceName: true,
      platform: true,
      trustedAt: true,
      lastSeenAt: true,
      createdAt: true,
    },
    orderBy: [{ lastSeenAt: 'asc' }, { createdAt: 'asc' }],
  })

  const deviceMap = new Map<
    string,
    {
      sessionIds: string[]
      trustedAt: Date | null
      lastSeenAt: Date
    }
  >()

  for (const session of activeSessions) {
    if (isWebSession(session)) {
      continue
    }

    const key = session.deviceId ?? `session:${session.id}`
    const existing = deviceMap.get(key)
    if (existing) {
      existing.sessionIds.push(session.id)
      if (session.trustedAt && (!existing.trustedAt || session.trustedAt > existing.trustedAt)) {
        existing.trustedAt = session.trustedAt
      }
      if (session.lastSeenAt < existing.lastSeenAt) {
        existing.lastSeenAt = session.lastSeenAt
      }
      continue
    }

    deviceMap.set(key, {
      sessionIds: [session.id],
      trustedAt: session.trustedAt,
      lastSeenAt: session.lastSeenAt,
    })
  }

  const activeDeviceCount = deviceMap.size + 1
  if (activeDeviceCount <= MAX_ACTIVE_DEVICES) return

  const overflow = activeDeviceCount - MAX_ACTIVE_DEVICES
  const evictionCandidates = [...deviceMap.values()]
    .filter((entry) => !entry.trustedAt)
    .sort((a, b) => a.lastSeenAt.getTime() - b.lastSeenAt.getTime())

  if (evictionCandidates.length < overflow) {
    throw new AuthDeviceLimitError(MAX_ACTIVE_DEVICES)
  }

  const sessionIdsToRevoke = evictionCandidates
    .slice(0, overflow)
    .flatMap((entry) => entry.sessionIds)

  await revokeSessionsByIds(tx, sessionIdsToRevoke, 'device_limit')
}

export async function resolveTrustedDevice(args: {
  tx: DatabaseClient
  userId: string
  req?: Request
  input?: AuthDeviceInput | null
  userKey: string
}) {
  const hintedDevice = buildNormalizedDevice({
    req: args.req,
    input: args.input,
    userKey: args.userKey,
  })
  const trustedDevice = await findTrustedDeviceState(args.tx, args.userId, hintedDevice.deviceId)
  const normalizedDevice = buildNormalizedDevice({
    req: args.req,
    input: args.input,
    userKey: args.userKey,
    existingDevice: trustedDevice,
  })

  return {
    trustedDevice,
    normalizedDevice,
  }
}

export async function listUserDevices(userId: string, currentSessionId?: string | null) {
  await markExpiredSessions(prisma as unknown as DatabaseClient, userId)

  const sessions = await prisma.authSession.findMany({
    where: { userId },
    orderBy: [{ lastSeenAt: 'desc' }, { createdAt: 'desc' }],
    select: {
      id: true,
      deviceId: true,
      deviceName: true,
      platform: true,
      trustedAt: true,
      createdAt: true,
      lastSeenAt: true,
      revokedAt: true,
      revokedReason: true,
      expiresAt: true,
    },
  })

  const devices = new Map<string, AuthDeviceSummary>()

  for (const session of sessions) {
    const key = session.deviceId ?? `session:${session.id}`
    const active = !session.revokedAt && session.expiresAt > new Date()
    const existing = devices.get(key)

    if (!existing) {
      devices.set(key, {
        device_id: session.deviceId ?? key,
        device_name: session.deviceName ?? 'Unknown device',
        platform: session.platform ?? 'unknown',
        trusted_at: session.trustedAt?.toISOString() ?? null,
        created_at: session.createdAt.toISOString(),
        last_seen_at: session.lastSeenAt.toISOString(),
        revoked_at: session.revokedAt?.toISOString() ?? null,
        revoked_reason: session.revokedReason ?? null,
        active,
        current: session.id === currentSessionId,
        active_session_count: active ? 1 : 0,
      })
      continue
    }

    existing.current = existing.current || session.id === currentSessionId
    existing.active = existing.active || active
    existing.active_session_count += active ? 1 : 0

    if (session.trustedAt && (!existing.trusted_at || session.trustedAt.toISOString() > existing.trusted_at)) {
      existing.trusted_at = session.trustedAt.toISOString()
    }
    if (session.lastSeenAt.toISOString() > existing.last_seen_at) {
      existing.last_seen_at = session.lastSeenAt.toISOString()
      existing.device_name = session.deviceName ?? existing.device_name
      existing.platform = session.platform ?? existing.platform
      existing.revoked_at = session.revokedAt?.toISOString() ?? existing.revoked_at
      existing.revoked_reason = session.revokedReason ?? existing.revoked_reason
    }
  }

  return {
    max_active_devices: MAX_ACTIVE_DEVICES,
    devices: [...devices.values()].sort((a, b) => {
      if (a.current !== b.current) return a.current ? -1 : 1
      if (a.active !== b.active) return a.active ? -1 : 1
      return Date.parse(b.last_seen_at) - Date.parse(a.last_seen_at)
    }),
  }
}

export async function setTrustedDevice(args: {
  userId: string
  deviceId: string
  trusted: boolean
}) {
  const selector = resolveStoredDeviceSelector(args.deviceId)
  if (!selector) return

  const trustedAt = args.trusted ? new Date() : null
  await prisma.authSession.updateMany({
    where: {
      userId: args.userId,
      ...selector,
    },
    data: {
      trustedAt,
    },
  })
}

export async function revokeDeviceSessions(args: {
  userId: string
  deviceId: string
  exceptSessionId?: string | null
}) {
  const selector = resolveStoredDeviceSelector(args.deviceId)
  if (!selector) return

  const where: Prisma.AuthSessionWhereInput = {
    userId: args.userId,
    revokedAt: null,
    ...('deviceId' in selector ? selector : {}),
  }

  if ('id' in selector) {
    where.id = args.exceptSessionId
      ? {
          equals: selector.id,
          not: args.exceptSessionId,
        }
      : selector.id
  } else if (args.exceptSessionId) {
    where.id = { not: args.exceptSessionId }
  }

  await prisma.authSession.updateMany({
    where,
    data: {
      revokedAt: new Date(),
      revokedReason: 'manual_revoke',
    },
  })
}
