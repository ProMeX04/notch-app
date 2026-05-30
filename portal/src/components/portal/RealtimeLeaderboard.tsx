'use client'

import { useEffect, useState, type CSSProperties } from 'react'
import { Crown, Trophy } from 'lucide-react'
import { createClient } from '@supabase/supabase-js'
import Link from 'next/link'

import styles from '@/app/leaderboard/leaderboard.module.css'

export type LeaderboardEntry = {
  user_id: string
  display_name: string
  focus_seconds: number
  session_count: number
  rank: number
}

type RealtimeLeaderboardProps = {
  initialData: LeaderboardEntry[]
  window: 'week' | 'all'
}

function formatFocusTime(seconds: number) {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)

  if (hours > 0) {
    return minutes > 0 ? `${hours}g ${minutes}p` : `${hours}g`
  }

  return `${Math.max(minutes, 1)}p`
}

function initials(displayName: string) {
  const words = displayName.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return 'N'
  return words.slice(-2).map((word) => word.charAt(0).toUpperCase()).join('')
}

function PodiumPlace({ entry, rank }: { entry: LeaderboardEntry | undefined; rank: number }) {
  const isWinner = rank === 1
  const className = [
    styles.place,
    isWinner ? styles.firstPlace : '',
    !entry ? styles.unfilledPlace : '',
  ].join(' ')

  return (
    <article className={className}>
      <span className={styles.medal}>
        {isWinner ? <Crown size={16} /> : rank}
      </span>
      <div className={styles.avatar}>{entry ? initials(entry.display_name) : '-'}</div>
      <strong>{entry?.display_name ?? 'Chưa có hạng'}</strong>
      <span className={styles.placeTime}>{entry ? formatFocusTime(entry.focus_seconds) : '-'}</span>
      <span className={styles.placeRank}>Hạng {rank}</span>
    </article>
  )
}

export function RealtimeLeaderboard({ initialData, window }: RealtimeLeaderboardProps) {
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>(initialData)
  const [isLive, setIsLive] = useState(false)

  // Sync state if server data changes (e.g. tab segments clicked)
  useEffect(() => {
    setLeaderboard(initialData)
  }, [initialData])

  useEffect(() => {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

    if (!supabaseUrl || !supabaseAnonKey) {
      console.warn('Supabase URL or Anon Key is missing in client environment.')
      return
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey)
    setIsLive(true)

    const fetchLatestData = async () => {
      try {
        const response = await fetch(`/api/focus/leaderboard?window=${window}`)
        if (response.ok) {
          const data = await response.json()
          if (data && Array.isArray(data.leaderboard)) {
            setLeaderboard(data.leaderboard)
          }
        }
      } catch (err) {
        console.error('Failed to fetch realtime leaderboard data:', err)
      }
    }

    // Subscribe to FocusDailyStat changes
    const channel = supabase
      .channel('public:FocusDailyStat')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'FocusDailyStat' },
        (payload) => {
          console.log('Detected database change, reloading leaderboard...', payload)
          fetchLatestData()
        }
      )
      .subscribe((status) => {
        if (status === 'SUBSCRIBED') {
          console.log('Successfully subscribed to FocusDailyStat realtime channel.')
        } else {
          setIsLive(false)
        }
      })

    return () => {
      supabase.removeChannel(channel)
    }
  }, [window])

  const hasPodium = leaderboard.length >= 3
  const tableEntries = hasPodium ? leaderboard.slice(3) : leaderboard
  const topSeconds = Math.max(leaderboard[0]?.focus_seconds ?? 0, 1)

  return (
    <>
      <div className={styles.heading}>
        <div style={{ display: 'flex', alignItems: 'center' }}>
          <h1>Bảng xếp hạng Focus</h1>
          {isLive && (
            <div className={styles.liveIndicator} title="Kết nối trực tiếp thời gian thực">
              <span className={styles.liveDot} />
              <span>Trực tiếp</span>
            </div>
          )}
        </div>
        <div className={styles.segments} aria-label="Khoảng thời gian">
          <Link
            href="/leaderboard?window=week"
            className={window === 'week' ? styles.activeSegment : styles.segment}
            aria-current={window === 'week' ? 'page' : undefined}
          >
            Tuần này
          </Link>
          <Link
            href="/leaderboard?window=all"
            className={window === 'all' ? styles.activeSegment : styles.segment}
            aria-current={window === 'all' ? 'page' : undefined}
          >
            Tất cả thời gian
          </Link>
        </div>
      </div>

      {leaderboard.length === 0 ? (
        <div className={styles.emptyState}>
          <Trophy size={25} />
          <h2>Chưa có thứ hạng</h2>
        </div>
      ) : (
        <>
          {hasPodium && (
            <div className={styles.podium} aria-label="Ba thứ hạng cao nhất">
              <PodiumPlace entry={leaderboard[1]} rank={2} />
              <PodiumPlace entry={leaderboard[0]} rank={1} />
              <PodiumPlace entry={leaderboard[2]} rank={3} />
            </div>
          )}

          {tableEntries.length > 0 && (
            <section className={styles.ranking}>
              <div className={styles.rankingTitle}>
                <h2>Xếp hạng</h2>
              </div>
              <div className={styles.tableHead} aria-hidden="true">
                <span>Hạng</span>
                <span>Người dùng</span>
                <span>Thời gian focus</span>
                <span>Phiên</span>
              </div>
              <ol className={styles.rows}>
                {tableEntries.map((entry, index) => (
                  <li
                    key={entry.user_id}
                    className={styles.row}
                    style={{
                      '--row-order': index,
                      '--progress': `${Math.max((entry.focus_seconds / topSeconds) * 100, 4)}%`,
                    } as CSSProperties}
                  >
                    <span className={styles.rank}>{entry.rank}</span>
                    <span className={styles.person}>
                      <span className={styles.smallAvatar}>{initials(entry.display_name)}</span>
                      <strong>{entry.display_name}</strong>
                    </span>
                    <span className={styles.focusValue}>
                      <span className={styles.bar} />
                      <strong>{formatFocusTime(entry.focus_seconds)}</strong>
                    </span>
                    <span className={styles.sessions}>{entry.session_count.toLocaleString('vi-VN')}</span>
                  </li>
                ))}
              </ol>
            </section>
          )}
        </>
      )}
    </>
  )
}
