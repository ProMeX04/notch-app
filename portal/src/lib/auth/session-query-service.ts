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

  const now = new Date()

  // JWTs are signed, but still session-bound so logout and device revocation take effect immediately.
  const payload = verifyJWT(token)
  if (payload) {
    if (payload.deviceId && requestDeviceID !== payload.deviceId) {
      return null
    }

    const session = await prisma.authSession.findUnique({
      where: { id: payload.sessionId },
      include: { user: true },
    })
    const accessExpiresAt = session?.accessExpiresAt ?? session?.expiresAt
    if (
      !session ||
      session.userId !== payload.userId ||
      session.revokedAt ||
      !accessExpiresAt ||
      accessExpiresAt <= now ||
      session.accessTokenHash !== hashToken(token) ||
      (session.deviceId && requestDeviceID !== session.deviceId)
    ) {
      return null
    }

    await prisma.authSession.update({
      where: { id: session.id },
      data: { lastSeenAt: now },
    }).catch(() => {})

    return {
      sessionId: session.id,
      deviceId: session.deviceId,
      user: session.user,
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
