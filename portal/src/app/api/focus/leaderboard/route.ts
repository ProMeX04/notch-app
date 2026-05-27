import { NextResponse } from 'next/server'

import { parseFocusWindow, readFocusLeaderboard } from '@/lib/focus-ranking'

export async function GET(req: Request) {
  const url = new URL(req.url)
  const window = parseFocusWindow(url.searchParams.get('window'))
  const leaderboard = await readFocusLeaderboard(window)

  return NextResponse.json({
    window,
    leaderboard,
  })
}
