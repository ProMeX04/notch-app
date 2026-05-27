import { NextResponse } from 'next/server'

import { readFocusSummary } from '@/lib/focus-ranking'
import { getAuthenticatedUser } from '@/lib/notch-auth'

export async function GET(req: Request) {
  const auth = await getAuthenticatedUser(req)
  if (!auth) {
    return NextResponse.json({ detail: 'Invalid or expired session token.' }, { status: 401 })
  }

  const summary = await readFocusSummary(auth.user.id)
  return NextResponse.json({
    user: {
      id: auth.user.id,
      display_name: auth.user.displayName ?? auth.user.name ?? null,
      leaderboard_opt_in: auth.user.leaderboardOptIn,
    },
    ...summary,
  })
}
