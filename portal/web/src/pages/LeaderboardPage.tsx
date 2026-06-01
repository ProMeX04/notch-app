import { useState, type CSSProperties } from 'react'
import { useQuery } from '@tanstack/react-query'
import { Trophy, Crown, User } from 'lucide-react'

import { apiClient } from '@/api/client'
import { PageShell } from '@/components/ui/PageShell'

// ─── Types ───────────────────────────────────────────────────────────────────

export type FocusWindow = 'week' | 'all'

export type LeaderboardEntry = {
  rank: number
  user_id: string
  display_name: string
  avatar_url?: string | null
  focus_seconds: number
  session_count: number
}

type LeaderboardResponse = {
  window: FocusWindow
  leaderboard: LeaderboardEntry[]
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

export function formatFocusTime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  const secs = seconds % 60

  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(hrs)}:${pad(mins)}:${pad(secs)}`
}

function initials(displayName: string): string {
  const words = displayName.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return 'N'
  return words
    .slice(-2)
    .map((word) => word.charAt(0).toUpperCase())
    .join('')
}

// ─── Podium ──────────────────────────────────────────────────────────────────

type PodiumCardProps = {
  entry: LeaderboardEntry | undefined
  rank: number
}

function PodiumCard({ entry, rank }: PodiumCardProps) {
  const isFirst = rank === 1

  const cardStyle: CSSProperties = {
    position: 'relative',
    height: isFirst ? 200 : 160,
    padding: '28px 16px 16px',
    borderRadius: '12px 12px 0 0',
    background: isFirst
      ? 'linear-gradient(180deg, rgba(245,158,11,0.15) 0%, rgba(255,255,255,0.03) 100%)'
      : 'rgba(255,255,255,0.015)',
    border: `1px solid ${isFirst ? 'rgba(245,158,11,0.3)' : 'rgba(255,255,255,0.08)'}`,
    borderBottom: 'none',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: 6,
    opacity: entry ? 1 : 0.45,
    transition: 'opacity 200ms ease',
  }

  const medalStyle: CSSProperties = {
    position: 'absolute',
    top: -16,
    left: '50%',
    transform: 'translateX(-50%)',
    width: 32,
    height: 32,
    borderRadius: '50%',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: isFirst ? 'rgba(245,158,11,0.12)' : 'rgba(255,255,255,0.06)',
    border: `1px solid ${isFirst ? 'rgba(245,158,11,0.5)' : 'rgba(255,255,255,0.15)'}`,
    color: isFirst ? '#f59e0b' : '#a1a1aa',
    fontSize: '0.8rem',
    fontWeight: 700,
    boxShadow: isFirst ? '0 4px 16px rgba(183,131,35,0.18)' : 'none',
  }

  const avatarSize = isFirst ? 56 : 44
  const avatarStyle: CSSProperties = {
    position: 'relative',
    width: avatarSize,
    height: avatarSize,
    borderRadius: '50%',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: isFirst ? 'rgba(56,189,248,0.12)' : 'rgba(255,255,255,0.06)',
    color: isFirst ? '#38bdf8' : '#ffffff',
    fontSize: isFirst ? '1rem' : '0.85rem',
    fontWeight: 700,
    marginBottom: 4,
    overflow: 'hidden',
  }

  return (
    <article style={cardStyle}>
      <span style={medalStyle}>
        {isFirst ? <Crown size={16} /> : rank}
      </span>
      <div style={avatarStyle}>
        {entry ? (
          entry.avatar_url ? (
            <img src={entry.avatar_url} alt={entry.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          ) : entry.display_name === 'Ẩn danh' ? (
            <User size={isFirst ? 24 : 20} />
          ) : (
            initials(entry.display_name)
          )
        ) : (
          '–'
        )}
      </div>
      <strong
        style={{
          maxWidth: '100%',
          overflow: 'hidden',
          whiteSpace: 'nowrap',
          textOverflow: 'ellipsis',
          fontSize: '0.9rem',
          fontWeight: 600,
          color: '#ffffff',
        }}
      >
        {entry?.display_name ?? 'Chưa có hạng'}
      </strong>
      <span style={{ color: '#ffffff', fontSize: '1rem', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
        {entry ? formatFocusTime(entry.focus_seconds) : '–'}
      </span>
      <span style={{ color: '#a1a1aa', fontSize: '0.72rem', fontWeight: 500 }}>Hạng {rank}</span>
    </article>
  )
}

// ─── Main Component ───────────────────────────────────────────────────────────

export function LeaderboardPage() {
  const [window, setWindow] = useState<FocusWindow>('week')

  const { data, isPending, isError } = useQuery({
    queryKey: ['focus', 'leaderboard', window],
    queryFn: async () => {
      const response = await apiClient.get<LeaderboardResponse>(
        `/api/focus/leaderboard?window=${window}`,
      )
      return response.data
    },
    retry: false,
  })

  const leaderboard = data?.leaderboard ?? []
  const hasPodium = leaderboard.length >= 3
  const tableEntries = hasPodium ? leaderboard.slice(3) : leaderboard
  const topSeconds = Math.max(leaderboard[0]?.focus_seconds ?? 0, 1)

  // ─── Styles ────────────────────────────────────────────────────────────────

  const pageStyle: CSSProperties = {
    minHeight: '100vh',
    background: '#0a0a0f',
    color: '#ffffff',
  }

  const shellStyle: CSSProperties = {
    maxWidth: 1040,
    margin: '0 auto',
    padding: '52px 24px 64px',
  }

  const headingRowStyle: CSSProperties = {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginBottom: 36,
    flexWrap: 'wrap',
    gap: 16,
  }

  const h1Style: CSSProperties = {
    fontSize: 'clamp(1.6rem, 4vw, 2.4rem)',
    fontWeight: 700,
    letterSpacing: '-0.02em',
    margin: 0,
  }

  const segmentsStyle: CSSProperties = {
    display: 'inline-flex',
    gap: 4,
    background: 'rgba(255,255,255,0.05)',
    borderRadius: 10,
    padding: 4,
  }

  function segmentStyle(active: boolean): CSSProperties {
    return {
      minWidth: 140,
      height: 38,
      padding: '0 16px',
      borderRadius: 7,
      border: 'none',
      cursor: 'pointer',
      fontSize: '0.88rem',
      fontWeight: 560,
      transition: 'background 160ms ease, color 160ms ease',
      background: active ? 'rgba(255,255,255,0.1)' : 'transparent',
      color: active ? '#ffffff' : '#a1a1aa',
    }
  }

  const podiumStyle: CSSProperties = {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    alignItems: 'flex-end',
    gap: 24,
    background: 'rgba(255,255,255,0.03)',
    border: '1px solid rgba(255,255,255,0.08)',
    borderRadius: 12,
    padding: '24px 48px 0',
    marginBottom: 24,
  }

  const rankingCardStyle: CSSProperties = {
    background: 'rgba(255,255,255,0.03)',
    border: '1px solid rgba(255,255,255,0.08)',
    borderRadius: 12,
    overflow: 'hidden',
  }

  const tableHeadStyle: CSSProperties = {
    display: 'grid',
    gridTemplateColumns: '74px minmax(180px, 1fr) 280px 76px',
    alignItems: 'center',
    gap: 16,
    padding: '0 24px',
    height: 44,
    color: '#71717a',
    background: 'rgba(255,255,255,0.02)',
    fontSize: '0.72rem',
    fontWeight: 700,
    textTransform: 'uppercase',
    letterSpacing: '0.05em',
    borderBottom: '1px solid rgba(255,255,255,0.08)',
  }

  return (
    <div style={pageStyle}>
      <PageShell>
        <main style={shellStyle}>
          <style>{`
            @keyframes spin { to { transform: rotate(360deg) } }
            @keyframes presencePulse {
              0%, 100% { opacity: 1; transform: scale(1); }
              50% { opacity: 0.6; transform: scale(0.82); }
            }
          `}</style>
          {/* ── Header ── */}
          <div style={headingRowStyle}>
            <h1 style={h1Style}>Bảng xếp hạng Focus</h1>

            <div style={segmentsStyle} role="group" aria-label="Khoảng thời gian">
              <button
                type="button"
                style={segmentStyle(window === 'week')}
                onClick={() => setWindow('week')}
                aria-current={window === 'week' ? 'true' : undefined}
              >
                Tuần này
              </button>
              <button
                type="button"
                style={segmentStyle(window === 'all')}
                onClick={() => setWindow('all')}
                aria-current={window === 'all' ? 'true' : undefined}
              >
                Tất cả thời gian
              </button>
            </div>
          </div>

          {/* ── Loading ── */}
          {isPending && (
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 16,
                height: 300,
                color: '#a1a1aa',
              }}
            >
              <div
                style={{
                  width: 40,
                  height: 40,
                  borderRadius: '50%',
                  border: '3px solid rgba(255,255,255,0.08)',
                  borderTopColor: '#38bdf8',
                  animation: 'spin 0.8s linear infinite',
                }}
              />
              <span style={{ fontSize: '0.95rem' }}>Đang tải...</span>
            </div>
          )}

          {/* ── Error ── */}
          {isError && (
            <div
              style={{
                display: 'flex',
                flexDirection: 'column',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 12,
                height: 300,
                background: 'rgba(239,68,68,0.06)',
                border: '1px solid rgba(239,68,68,0.2)',
                borderRadius: 12,
                color: '#f87171',
                textAlign: 'center',
                padding: 24,
              }}
            >
              <span style={{ fontSize: '1.5rem' }}>⚠</span>
              <p style={{ margin: 0, fontWeight: 600 }}>
                Không thể tải bảng xếp hạng. Vui lòng thử lại.
              </p>
            </div>
          )}

          {/* ── Data ── */}
          {!isPending && !isError && (
            <>
              {leaderboard.length === 0 ? (
                /* Empty state */
                <div
                  style={{
                    height: 320,
                    background: 'rgba(255,255,255,0.03)',
                    border: '1px solid rgba(255,255,255,0.08)',
                    borderRadius: 12,
                    display: 'flex',
                    flexDirection: 'column',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: 14,
                    color: '#71717a',
                  }}
                >
                  <Trophy size={28} />
                  <h2 style={{ margin: 0, color: '#a1a1aa', fontSize: '1.05rem', fontWeight: 580 }}>
                    Chưa có thứ hạng
                  </h2>
                  <p style={{ margin: 0, fontSize: '0.9rem' }}>
                    Hãy là người đầu tiên lên bảng xếp hạng!
                  </p>
                </div>
              ) : (
                <>
                  {/* Podium */}
                  {hasPodium && (
                    <div style={podiumStyle} aria-label="Ba thứ hạng cao nhất">
                      <PodiumCard
                        entry={leaderboard[1]}
                        rank={2}
                      />
                      <PodiumCard
                        entry={leaderboard[0]}
                        rank={1}
                      />
                      <PodiumCard
                        entry={leaderboard[2]}
                        rank={3}
                      />
                    </div>
                  )}

                  {/* Rank table */}
                  {tableEntries.length > 0 && (
                    <section style={rankingCardStyle}>
                      <div style={{ padding: '0 24px', height: 64, display: 'flex', alignItems: 'center', borderBottom: '1px solid rgba(255,255,255,0.08)' }}>
                        <h2 style={{ margin: 0, fontSize: '1.05rem', fontWeight: 620, letterSpacing: 0 }}>
                          Xếp hạng
                        </h2>
                      </div>

                      <div style={tableHeadStyle} aria-hidden="true">
                        <span>Hạng</span>
                        <span>Người dùng</span>
                        <span style={{ textAlign: 'right' }}>Thời gian focus</span>
                        <span style={{ textAlign: 'right' }}>Phiên</span>
                      </div>

                      <ol style={{ listStyle: 'none', margin: 0, padding: 0 }}>
                        {tableEntries.map((entry, index) => {
                          const progress = Math.max((entry.focus_seconds / topSeconds) * 100, 4)

                          return (
                            <li
                              key={entry.user_id}
                              style={{
                                display: 'grid',
                                gridTemplateColumns: '74px minmax(180px, 1fr) 280px 76px',
                                alignItems: 'center',
                                gap: 16,
                                padding: '0 24px',
                                minHeight: 64,
                                borderTop: '1px solid rgba(255,255,255,0.06)',
                                fontSize: '0.9rem',
                                transition: 'background 160ms ease',
                                '--row-order': index,
                              } as CSSProperties}
                              onMouseEnter={(e) => {
                                ;(e.currentTarget as HTMLLIElement).style.background =
                                  'rgba(255,255,255,0.04)'
                              }}
                              onMouseLeave={(e) => {
                                ;(e.currentTarget as HTMLLIElement).style.background = 'transparent'
                              }}
                            >
                              {/* Rank */}
                              <span
                                style={{
                                  color: '#d4d4d8',
                                  fontWeight: 620,
                                  fontVariantNumeric: 'tabular-nums',
                                }}
                              >
                                {entry.rank}
                              </span>

                              {/* Person */}
                              <span
                                style={{
                                  minWidth: 0,
                                  display: 'flex',
                                  alignItems: 'center',
                                  gap: 12,
                                }}
                              >
                                <span
                                  style={{
                                    position: 'relative',
                                    flexShrink: 0,
                                    width: 34,
                                    height: 34,
                                    borderRadius: '50%',
                                    display: 'inline-flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    background: 'rgba(255,255,255,0.06)',
                                    color: '#ffffff',
                                    fontSize: '0.72rem',
                                    fontWeight: 700,
                                    overflow: 'hidden',
                                  }}
                                >
                                  {entry.avatar_url ? (
                                    <img src={entry.avatar_url} alt={entry.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                  ) : entry.display_name === 'Ẩn danh' ? (
                                    <User size={16} />
                                  ) : (
                                    initials(entry.display_name)
                                  )}
                                </span>
                                <strong
                                  style={{
                                    overflow: 'hidden',
                                    textOverflow: 'ellipsis',
                                    whiteSpace: 'nowrap',
                                    fontWeight: 560,
                                  }}
                                >
                                  {entry.display_name}
                                </strong>
                              </span>

                              {/* Focus time + progress bar */}
                              <span
                                style={{
                                  display: 'flex',
                                  alignItems: 'center',
                                  justifyContent: 'flex-end',
                                  gap: 14,
                                  color: '#a1a1aa',
                                  fontVariantNumeric: 'tabular-nums',
                                }}
                              >
                                <span
                                  style={{
                                    position: 'relative',
                                    width: 128,
                                    height: 5,
                                    borderRadius: 4,
                                    background: 'rgba(255,255,255,0.1)',
                                    overflow: 'hidden',
                                    flexShrink: 0,
                                  }}
                                >
                                  <span
                                    style={{
                                      position: 'absolute',
                                      inset: '0 auto 0 0',
                                      width: `${progress}%`,
                                      background: '#38bdf8',
                                      borderRadius: 'inherit',
                                    }}
                                  />
                                </span>
                                <strong style={{ width: 68, textAlign: 'right', fontWeight: 560 }}>
                                  {formatFocusTime(entry.focus_seconds)}
                                </strong>
                              </span>

                              {/* Sessions */}
                              <span
                                style={{
                                  textAlign: 'right',
                                  color: '#a1a1aa',
                                  fontVariantNumeric: 'tabular-nums',
                                }}
                              >
                                {entry.session_count.toLocaleString('vi-VN')}
                              </span>
                            </li>
                          )
                        })}
                      </ol>
                    </section>
                  )}
                </>
              )}
            </>
          )}
        </main>
      </PageShell>
    </div>
  )
}
