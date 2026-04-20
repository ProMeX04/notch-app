import { createHash, randomBytes } from 'node:crypto'

import type { Prisma } from '@prisma/client'

import prisma from '@/lib/prisma'

const ACCESS_TOKEN_TTL_MS = 60 * 60 * 1000
const REFRESH_TOKEN_TTL_MS = 30 * 24 * 60 * 60 * 1000
const BRIDGE_TOKEN_TTL_MS = 5 * 60 * 1000
const PORTABLE_SESSION_TOKEN_PREFIX = 'nts_'
const DEFAULT_MAX_ACTIVE_DEVICES = 3
const MAX_ACTIVE_DEVICES = resolvedPositiveInt(process.env.NOTCH_MAX_ACTIVE_DEVICES, DEFAULT_MAX_ACTIVE_DEVICES)

export type DatabaseClient = Prisma.TransactionClient

export type SessionUser = {
  id: string
  email: string | null
  name: string | null
  createdAt: Date
  isPro: boolean
}

export type AuthDeviceInput = {
  device_id?: string
  device_name?: string
  platform?: string
  trust_device?: boolean
}

type NormalizedDevice = {
  deviceId: string
  deviceName: string
  platform: string
  trustDevice: boolean
}

type LogoutRequestBody = AuthDeviceInput & {
  token?: string
  tokens?: string[]
  refresh_token?: string
  session_id?: string
  device_id?: string
}

type RefreshRequestBody = AuthDeviceInput & {
  refresh_token?: string
}

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

type DecodedSessionToken =
  | {
      kind: 'bridge'
      bridgeToken: string
    }
  | {
      kind: 'portable'
      accessToken: string
      refreshToken: string
    }

export type NotchAuthPayload = {
  access_token: string
  token_type: 'Bearer'
  expires_at: string
  refresh_token: string
  refresh_expires_at: string
  session_token?: string
  user: {
    id: string
    email: string
    name: string | null
    created_at: string
    is_pro: boolean
  }
  session: {
    id: string
    device_id: string
    device_name: string
    platform: string
    trusted_at: string | null
  }
  max_active_devices: number
}

export type NotchWebBridgePayload = {
  bridge_token: string
  expires_at: string
}

export type NotchAppLoginBridgePayload = {
  bridge_token: string
  expires_at: string
}

export type AppLoginBridgeExchangeResult =
  | {
      status: 'ready'
      payload: NotchAuthPayload
    }
  | {
      status: 'pending'
      expires_at: string
    }
  | {
      status: 'expired' | 'invalid'
    }

export type AuthDeviceSummary = {
  device_id: string
  device_name: string
  platform: string
  trusted_at: string | null
  created_at: string
  last_seen_at: string
  revoked_at: string | null
  revoked_reason: string | null
  active: boolean
  current: boolean
  active_session_count: number
}

export class AuthDeviceLimitError extends Error {
  readonly statusCode = 409

  constructor(readonly maxActiveDevices: number) {
    super(`Too many active devices. You can use up to ${maxActiveDevices} devices at the same time.`)
    this.name = 'AuthDeviceLimitError'
  }
}

function resolvedPositiveInt(rawValue: string | undefined, fallback: number): number {
  const parsed = Number.parseInt(rawValue ?? '', 10)
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback
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

function encodeSessionToken(payload: NotchPortableSession | BridgeBackedSessionToken): string {
  const raw = Buffer.from(JSON.stringify(payload)).toString('base64url')
  return `${PORTABLE_SESSION_TOKEN_PREFIX}${raw}`
}

function createBridgeBackedSessionToken(bridgeToken: string, expiresAt: string): string {
  return encodeSessionToken({
    token_kind: 'bridge',
    bridge_token: bridgeToken,
    access_token: '',
    expires_at: expiresAt,
    refresh_token: '',
    refresh_expires_at: expiresAt,
  })
}

function decodeSessionToken(token: string): DecodedSessionToken | null {
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

function resolveStoredDeviceSelector(deviceId: string) {
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

function buildNormalizedDevice(args: {
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
    `legacy_${hashToken(`${args.userKey}:${userAgent || 'unknown-device'}`).slice(0, 24)}`

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

function buildAuthPayload(args: {
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
}): NotchAuthPayload {
  const expiresAt = args.accessExpiresAt.toISOString()
  const refreshExpiresAt = args.refreshExpiresAt.toISOString()

  const payload: NotchAuthPayload = {
    access_token: args.accessToken,
    token_type: 'Bearer',
    expires_at: expiresAt,
    refresh_token: args.refreshToken,
    refresh_expires_at: refreshExpiresAt,
    user: serializeUser(args.user),
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

async function markExpiredSessions(tx: DatabaseClient, userId?: string) {
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

async function revokeSessionsByIds(
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

async function enforceActiveDeviceLimit(
  tx: DatabaseClient,
  userId: string,
  currentDeviceId: string,
) {
  const activeSessions = await tx.authSession.findMany({
    where: {
      userId,
      revokedAt: null,
      expiresAt: { gt: new Date() },
      deviceId: { not: currentDeviceId },
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

async function issueDeviceBoundAuthPayload(args: {
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

  const hintedDevice = buildNormalizedDevice({
    req,
    input: args.device,
    userKey: user.id,
  })
  const trustedDevice = await findTrustedDeviceState(tx, user.id, hintedDevice.deviceId)
  const normalizedDevice = buildNormalizedDevice({
    req,
    input: args.device,
    userKey: user.id,
    existingDevice: trustedDevice,
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

export function readBearerToken(req: Request): string | null {
  const authHeader = req.headers.get('authorization')?.trim()
  if (!authHeader) return null

  const [scheme, token] = authHeader.split(/\s+/, 2)
  if (!scheme || !token || scheme.toLowerCase() !== 'bearer') {
    return null
  }

  return token
}

function readDeviceIDHeader(req: Request): string | null {
  const value = req.headers.get('x-notch-device-id')?.trim()
  return value ? value : null
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
  const token = readBearerToken(req) ?? readCookie(req, 'notch_access_token')
  if (!token) return null
  const requestDeviceID = readDeviceIDHeader(req)

  const session = await findSessionByAccessToken(token)
  if (!session) return null

  if (session.deviceId && requestDeviceID !== session.deviceId) {
    return null
  }

  const accessExpiresAt = session.accessExpiresAt ?? session.expiresAt
  if (session.revokedAt || accessExpiresAt <= new Date()) {
    if (!session.revokedAt) {
      await prisma.authSession.update({
        where: { id: session.id },
        data: {
          revokedAt: new Date(),
          revokedReason: accessExpiresAt <= new Date() ? 'expired' : 'invalid',
        },
      }).catch(() => {})
    }
    return null
  }

  await prisma.authSession.update({
    where: { id: session.id },
    data: { lastSeenAt: new Date() },
  }).catch(() => {})

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

  if (!body?.device_id && !body?.session_id && tokens.length === 0) {
    return {
      hasTokens: false,
      revokedCount: 0,
    }
  }

  const auth = bearerToken ? await getAuthenticatedUser(req) : null
  const now = new Date()

  let revokedCount = 0
  if (tokens.length > 0) {
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

export function authUserResponse(user: SessionUser, sessionId?: string | null) {
  return {
    ...serializeUser(user),
    current_session_id: sessionId ?? null,
    max_active_devices: MAX_ACTIVE_DEVICES,
  }
}

export function authPayloadUserResponse(
  user: NotchAuthPayload['user'],
  sessionId?: string | null,
) {
  return {
    ...user,
    current_session_id: sessionId ?? null,
    max_active_devices: MAX_ACTIVE_DEVICES,
  }
}
