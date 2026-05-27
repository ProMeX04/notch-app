import { getRemotePermissionPolicy } from '@/lib/capabilities/policy-service'

export async function serializeUser(user: {
  id: string
  email: string | null
  name: string | null
  displayName?: string | null
  avatarUrl?: string | null
  createdAt: Date
  isPro: boolean
  leaderboardOptIn?: boolean
}) {
  const permission_policy = await getRemotePermissionPolicy()
  return {
    id: user.id,
    email: user.email ?? '',
    name: user.name,
    display_name: user.displayName ?? null,
    avatar_url: user.avatarUrl ?? null,
    created_at: user.createdAt.toISOString(),
    is_pro: user.isPro,
    leaderboard_opt_in: user.leaderboardOptIn ?? false,
    permission_policy,
  }
}

export async function authUserResponse(
  user: {
    id: string
    email: string | null
    name: string | null
    displayName?: string | null
    createdAt: Date
    isPro: boolean
    leaderboardOptIn?: boolean
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
    display_name?: string | null
    avatar_url?: string | null
    created_at: string
    is_pro: boolean
    leaderboard_opt_in?: boolean
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
