import { readBearerToken, readCookie } from '@/lib/auth/token-service'
import { findSessionByAccessToken } from '@/lib/auth/session-query-service'

export async function verifyAdminSession(token: string | null): Promise<boolean> {
  if (!token) return false

  try {
    const session = await findSessionByAccessToken(token)
    if (!session?.user) return false

    const accessExpiresAt = session.accessExpiresAt ?? session.expiresAt
    if (session.revokedAt || accessExpiresAt <= new Date()) return false

    return Boolean(session.user.isAdmin)
  } catch {
    return false
  }
}

export async function requireAdminUser(req: Request) {
  const token = readBearerToken(req) ?? readCookie(req, 'notch_access_token')
  if (!token) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const isAdmin = await verifyAdminSession(token)
  if (!isAdmin) {
    return new Response(JSON.stringify({ error: 'Forbidden' }), {
      status: 403,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  return null
}

export async function requireAdminForServerComponent(token: string | null): Promise<boolean> {
  return verifyAdminSession(token)
}
