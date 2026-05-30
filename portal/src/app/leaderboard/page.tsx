import type { Metadata } from 'next'

import { parseFocusWindow, readFocusLeaderboard } from '@/lib/focus-ranking'
import { Navbar } from '@/components/portal/Navbar'
import { RealtimeLeaderboard, type LeaderboardEntry } from '@/components/portal/RealtimeLeaderboard'

import styles from './leaderboard.module.css'

export const dynamic = 'force-dynamic'

export const metadata: Metadata = {
  title: 'Bảng xếp hạng Focus | Notch',
  description: 'Bảng xếp hạng thời gian tập trung công khai của cộng đồng Notch.',
}

type LeaderboardPageProps = {
  searchParams: Promise<{ window?: string | string[] }>
}

export default async function LeaderboardPage({ searchParams }: LeaderboardPageProps) {
  const params = await searchParams
  const rawWindow = Array.isArray(params.window) ? params.window[0] : params.window
  const window = parseFocusWindow(rawWindow ?? null)
  const leaderboard = await readFocusLeaderboard(window)

  // Map to the client-safe serializable type, converting BigInt/Number to standard numbers
  const mappedLeaderboard: LeaderboardEntry[] = leaderboard.map(entry => ({
    user_id: entry.user_id,
    display_name: entry.display_name,
    focus_seconds: entry.focus_seconds,
    session_count: entry.session_count,
    rank: Number(entry.rank)
  }))

  return (
    <main className={styles.page}>
      <Navbar />

      <section className={styles.shell}>
        <RealtimeLeaderboard initialData={mappedLeaderboard} window={window} />
      </section>
    </main>
  )
}
