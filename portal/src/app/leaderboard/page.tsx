import type { Metadata } from 'next'
import Link from 'next/link'
import type { CSSProperties } from 'react'
import { ArrowRight, Crown, Trophy } from 'lucide-react'

import { PortalLogo } from '@/components/portal/PortalLogo'
import { parseFocusWindow, readFocusLeaderboard } from '@/lib/focus-ranking'

import styles from './leaderboard.module.css'

export const dynamic = 'force-dynamic'

export const metadata: Metadata = {
  title: 'Bảng xếp hạng Focus | Notch',
  description: 'Bảng xếp hạng thời gian tập trung công khai của cộng đồng Notch.',
}

type LeaderboardPageProps = {
  searchParams: Promise<{ window?: string | string[] }>
}

type LeaderboardEntry = Awaited<ReturnType<typeof readFocusLeaderboard>>[number]

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

export default async function LeaderboardPage({ searchParams }: LeaderboardPageProps) {
  const params = await searchParams
  const rawWindow = Array.isArray(params.window) ? params.window[0] : params.window
  const window = parseFocusWindow(rawWindow ?? null)
  const leaderboard = await readFocusLeaderboard(window)
  const hasPodium = leaderboard.length >= 3
  const tableEntries = hasPodium ? leaderboard.slice(3) : leaderboard
  const topSeconds = Math.max(leaderboard[0]?.focus_seconds ?? 0, 1)

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <PortalLogo />
          <nav className={styles.primaryNavigation} aria-label="Điều hướng chính">
            <Link href="/">Sản phẩm</Link>
            <Link href="/leaderboard" className={styles.activeNav} aria-current="page">
              Bảng xếp hạng
            </Link>
          </nav>
          <div className={styles.actions}>
            <Link href="/api/auth/google" className={styles.signIn}>Đăng nhập</Link>
            <Link href="/pro" className={styles.openPortal}>
              Portal
              <ArrowRight size={15} />
            </Link>
          </div>
        </div>
      </header>

      <section className={styles.shell}>
        <div className={styles.heading}>
          <h1>Bảng xếp hạng Focus</h1>
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
                      style={{ '--row-order': index, '--progress': `${Math.max((entry.focus_seconds / topSeconds) * 100, 4)}%` } as CSSProperties}
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
      </section>
    </main>
  )
}
