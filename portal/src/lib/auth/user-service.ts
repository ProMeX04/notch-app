import { getRemotePermissionPolicy } from '@/lib/capabilities/policy-service'

export async function serializeUser(user: {
  id: string
  email: string | null
  name: string | null
  createdAt: Date
  isPro: boolean
}) {
  const permission_policy = await getRemotePermissionPolicy()
  return {
    id: user.id,
    email: user.email ?? '',
    name: user.name,
    created_at: user.createdAt.toISOString(),
    is_pro: user.isPro,
    permission_policy,
  }
}

export async function authUserResponse(
  user: {
    id: string
    email: string | null
    name: string | null
    createdAt: Date
    isPro: boolean
  },
  sessionId: string | null | undefined,
  maxActiveDevices: number,
) {
  const serialized = await serializeUser(user)
  return {
    ...serialized,
    current_session_id: sessionId ?? null,
    max_active_devices: maxActiveDevices,
  }
}

export function authPayloadUserResponse(
  user: {
    id: string
    email: string
    name: string | null
    created_at: string
    is_pro: boolean
  },
  sessionId: string | null | undefined,
  maxActiveDevices: number,
) {
  return {
    ...user,
    current_session_id: sessionId ?? null,
    max_active_devices: maxActiveDevices,
  }
}
