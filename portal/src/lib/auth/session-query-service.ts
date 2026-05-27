import prisma from '@/lib/prisma'
import { hashToken, readBearerToken, readCookie } from '@/lib/auth/token-service'

function readDeviceIDHeader(req: Request): string | null {
  const value = req.headers.get('x-notch-device-id')?.trim()
  return value ? value : null
}

export async function findSessionByAccessToken(token: string) {
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
    deviceId: session.deviceId,
    user: session.user,
  }
}
