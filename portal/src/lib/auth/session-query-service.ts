import prisma from '@/lib/prisma'
import { hashToken, readBearerToken, readCookie, verifyJWT } from '@/lib/auth/token-service'

function readDeviceIDHeader(req: Request): string | null {
  const value = req.headers.get('x-notch-device-id')?.trim()
  return value ? value : null
}

export async function findSessionByAccessToken(token: string) {
  const payload = verifyJWT(token)
  if (payload) {
    return prisma.authSession.findUnique({
      where: { id: payload.sessionId },
      include: { user: true },
    })
  }

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

  // Try decoding as JWT first (offline verification)
  const payload = verifyJWT(token)
  if (payload) {
    if (payload.deviceId && requestDeviceID !== payload.deviceId) {
      return null
    }

    return {
      sessionId: payload.sessionId,
      deviceId: payload.deviceId,
      user: {
        id: payload.userId,
        email: payload.email,
        name: payload.name,
        displayName: payload.displayName,
        avatarUrl: payload.avatarUrl,
        createdAt: new Date(payload.userCreatedAt),
        isPro: payload.isPro,
        isAdmin: payload.isAdmin,
        leaderboardOptIn: payload.leaderboardOptIn,
      },
    }
  }

  // Fallback to database lookup for old opaque sessions
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
    deviceId: session.deviceId,
    user: session.user,
  }
}
