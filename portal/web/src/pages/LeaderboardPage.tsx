import { useQuery } from '@tanstack/react-query'

import { apiClient } from '@/api/client'
import { PageShell } from '@/components/ui/PageShell'

type LeaderboardEntry = {
  rank: number
  user_id: string
  display_name: string
  focus_seconds: number
  session_count: number
}

async function fetchLeaderboard() {
  const response = await apiClient.get<LeaderboardEntry[]>('/api/focus/leaderboard?window=week')
  return response.data
}

export function LeaderboardPage() {
  const leaderboard = useQuery({
    queryKey: ['focus', 'leaderboard', 'week'],
    queryFn: fetchLeaderboard,
    retry: false,
  })

  return (
    <PageShell>
      <section className="portal-card">
        <p className="portal-kicker">Focus</p>
        <h1>Weekly leaderboard</h1>
        {leaderboard.isPending ? <p>Loading leaderboard…</p> : null}
        {leaderboard.isError ? <p>Leaderboard API is not available in the Go scaffold yet.</p> : null}
        {leaderboard.data?.length ? (
          <ol className="portal-list">
            {leaderboard.data.map((entry) => (
              <li key={entry.user_id}>
                <span>#{entry.rank} {entry.display_name}</span>
                <strong>{Math.round(entry.focus_seconds / 60)} min</strong>
              </li>
            ))}
          </ol>
        ) : null}
      </section>
    </PageShell>
  )
}
