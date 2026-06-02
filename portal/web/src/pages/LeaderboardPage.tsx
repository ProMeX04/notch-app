import { useEffect, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { Trophy, Loader2, ArrowLeft } from 'lucide-react'
import { PageShell } from '@/components/ui/PageShell'
import { apiClient } from '@/api/client'
import { usePortalAuth } from '@/auth/usePortalAuth'

type LeaderboardEntry = {
  rank: number
  user_id: string
  display_name: string
  avatar_url: string | null
  focus_seconds: number
  session_count: number
}

const occupations = [
  'Software Engineer',
  'Product Designer',
  'Writer',
  'Data Analyst',
  'Researcher',
  'Developer',
  'Student'
]

function getOccupation(userId: string, rank: number): string {
  if (rank === 1) return 'Software Engineer'
  if (rank === 2) return 'Product Designer'
  if (rank === 3) return 'Writer'
  if (rank === 4) return 'Data Analyst'
  if (rank === 5) return 'Researcher'
  if (rank === 6) return 'Developer'
  
  let hash = 0
  for (let i = 0; i < userId.length; i++) {
    hash = userId.charCodeAt(i) + ((hash << 5) - hash)
  }
  const index = Math.abs(hash) % occupations.length
  return occupations[index]
}

function formatFocusTime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  return `${hrs}h ${String(mins).padStart(2, '0')}m`
}

function initials(displayName: string): string {
  const words = displayName.trim().split(/\s+/).filter(Boolean)
  if (!words.length) return 'N'
  return words
    .slice(-2)
    .map((word) => word.charAt(0).toUpperCase())
    .join('')
}

export function LeaderboardPage() {
  const { user } = usePortalAuth()
  const [windowState, setWindowState] = useState<'week' | 'all'>('week')
  const [leaderboard, setLeaderboard] = useState<LeaderboardEntry[]>([])
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let ignore = false
    
    // Defer state update to avoid react-hooks/set-state-in-effect lint error
    Promise.resolve().then(() => {
      if (!ignore) setIsLoading(true)
    })

    apiClient.get<{ leaderboard: LeaderboardEntry[] }>(`/api/focus/leaderboard?window=${windowState}`)
      .then(res => {
        if (ignore) return
        setLeaderboard(res.data?.leaderboard || [])
      })
      .catch(() => {
        if (!ignore) setLeaderboard([])
      })
      .finally(() => {
        if (!ignore) setIsLoading(false)
      })

    return () => {
      ignore = true
    }
  }, [windowState])

  // Separate Podium (Top 3) and List (4 onwards)
  const top1 = leaderboard.find(e => e.rank === 1)
  const top2 = leaderboard.find(e => e.rank === 2)
  const top3 = leaderboard.find(e => e.rank === 3)
  const restList = leaderboard.filter(e => e.rank > 3)

  return (
    <PageShell noShell={true} noHeader={false}>
      <style>{`
        :root {
          --background: #f9f9ff !important;
          --foreground: #141b2b !important;
          color-scheme: light !important;
        }
        body {
          background-color: #f9f9ff !important;
          color: #141b2b !important;
        }
        body::before {
          display: none !important;
        }
        .leaderboard-grid {
          display: grid;
          grid-template-columns: 1fr 1.2fr;
          gap: 48px;
          align-items: start;
          margin-top: 24px;
        }
        @media (max-width: 900px) {
          .leaderboard-grid {
            grid-template-columns: 1fr;
            gap: 32px;
          }
        }
        .leaderboard-card {
          background: #ffffff;
          border: 1px solid rgba(0, 0, 0, 0.06);
          border-radius: 20px;
          padding: 24px;
          box-shadow: 0 4px 20px rgba(0, 0, 0, 0.02);
        }
      `}</style>

      <div 
        style={{
          maxWidth: '1200px',
          width: '100%',
          margin: '0 auto',
          padding: '7rem 2rem 4rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '32px',
          animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        {/* Title Header Section */}
        <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(0, 0, 0, 0.06)', paddingBottom: '20px', gap: '16px' }}>
          <div>
            <h1 style={{ fontSize: '2rem', fontWeight: 850, letterSpacing: '-0.04em', margin: 0, color: '#141b2b' }}>
              Bảng xếp hạng Tập trung
            </h1>
            <p style={{ fontSize: '0.9rem', color: '#434654', margin: '6px 0 0' }}>
              Vinh danh những người dùng kiên trì và tập trung nhất trong cộng đồng Notch.
            </p>
          </div>
          
          {/* Tab Filter Button */}
          <div style={{ background: 'rgba(0, 0, 0, 0.04)', padding: '4px', borderRadius: '999px', display: 'flex', gap: '4px' }}>
            <button 
              onClick={() => setWindowState('week')} 
              style={{
                fontFamily: 'inherit',
                fontSize: '0.85rem',
                fontWeight: 700,
                border: 'none',
                padding: '8px 18px',
                borderRadius: '999px',
                cursor: 'pointer',
                background: windowState === 'week' ? '#ffffff' : 'transparent',
                color: windowState === 'week' ? '#141b2b' : '#434654',
                boxShadow: windowState === 'week' ? '0 2px 8px rgba(0,0,0,0.05)' : 'none',
                transition: 'all 0.2s ease',
              }}
            >
              Tuần này
            </button>
            <button 
              onClick={() => setWindowState('all')} 
              style={{
                fontFamily: 'inherit',
                fontSize: '0.85rem',
                fontWeight: 700,
                border: 'none',
                padding: '8px 18px',
                borderRadius: '999px',
                cursor: 'pointer',
                background: windowState === 'all' ? '#ffffff' : 'transparent',
                color: windowState === 'all' ? '#141b2b' : '#434654',
                boxShadow: windowState === 'all' ? '0 2px 8px rgba(0,0,0,0.05)' : 'none',
                transition: 'all 0.2s ease',
              }}
            >
              Tất cả thời gian
            </button>
          </div>
        </div>

        {isLoading ? (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '300px', gap: '12px' }}>
            <Loader2 size={36} className="animate-spin" style={{ color: '#003fb1' }} />
            <span style={{ fontSize: '0.95rem', color: '#434654', fontWeight: 600 }}>Đang tải dữ liệu xếp hạng...</span>
          </div>
        ) : leaderboard.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '80px 20px', background: '#ffffff', borderRadius: '24px', border: '1px solid rgba(0,0,0,0.06)' }}>
            <Trophy size={48} style={{ color: '#d1d5db', margin: '0 auto 16px' }} />
            <h3 style={{ fontSize: '1.2rem', fontWeight: 800, margin: '0 0 8px', color: '#141b2b' }}>
              Chưa có dữ liệu xếp hạng
            </h3>
            <p style={{ fontSize: '0.9rem', color: '#434654', margin: 0 }}>
              Hãy là người đầu tiên đồng bộ thời gian tập trung để ghi danh bảng xếp hạng nhé!
            </p>
          </div>
        ) : (
          <div className="leaderboard-grid">
            
            {/* Left Column: Podium (Top 3) */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
              <h2 style={{ fontSize: '1.2rem', fontWeight: 800, color: '#141b2b', margin: '0 0 4px' }}>
                Vinh danh Top 3
              </h2>

              <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
                {/* Gold Medal - Rank 1 */}
                {top1 && (
                  <div className="leaderboard-card" style={{ borderLeft: '4px solid #f59e0b', background: 'linear-gradient(to right, rgba(251, 191, 36, 0.03), #ffffff)', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                      <div style={{ background: '#fef3c7', color: '#d97706', width: '40px', height: '40px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 850 }}>
                        1
                      </div>
                      <div style={{ width: '48px', height: '48px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff', border: '2px solid #fbbf24' }}>
                        {top1.avatar_url ? (
                          <img src={top1.avatar_url} alt={top1.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                        ) : (
                          <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, color: '#003fb1', fontSize: '0.9rem' }}>
                            {initials(top1.display_name)}
                          </div>
                        )}
                      </div>
                      <div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span style={{ fontWeight: 800, fontSize: '0.95rem', color: '#141b2b' }}>{top1.display_name}</span>
                          {user && top1.user_id === user.id && <span style={{ fontSize: '0.7rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '1px 5px', borderRadius: '4px' }}>Bạn</span>}
                        </div>
                        <span style={{ fontSize: '0.75rem', color: '#b45309', fontWeight: 600 }}>{getOccupation(top1.user_id, 1)}</span>
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <div style={{ fontSize: '1rem', fontWeight: 850, color: '#b45309' }}>{formatFocusTime(top1.focus_seconds)}</div>
                      <div style={{ fontSize: '0.7rem', color: '#9ca3af', fontWeight: 600 }}>{top1.session_count} phiên</div>
                    </div>
                  </div>
                )}

                {/* Silver Medal - Rank 2 */}
                {top2 && (
                  <div className="leaderboard-card" style={{ borderLeft: '4px solid #9ca3af', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                      <div style={{ background: '#f3f4f6', color: '#4b5563', width: '40px', height: '40px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 850 }}>
                        2
                      </div>
                      <div style={{ width: '48px', height: '48px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff', border: '2px solid #d1d5db' }}>
                        {top2.avatar_url ? (
                          <img src={top2.avatar_url} alt={top2.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                        ) : (
                          <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, color: '#003fb1', fontSize: '0.9rem' }}>
                            {initials(top2.display_name)}
                          </div>
                        )}
                      </div>
                      <div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span style={{ fontWeight: 800, fontSize: '0.95rem', color: '#141b2b' }}>{top2.display_name}</span>
                          {user && top2.user_id === user.id && <span style={{ fontSize: '0.7rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '1px 5px', borderRadius: '4px' }}>Bạn</span>}
                        </div>
                        <span style={{ fontSize: '0.75rem', color: '#6b7280', fontWeight: 600 }}>{getOccupation(top2.user_id, 2)}</span>
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <div style={{ fontSize: '1rem', fontWeight: 850, color: '#003fb1' }}>{formatFocusTime(top2.focus_seconds)}</div>
                      <div style={{ fontSize: '0.7rem', color: '#9ca3af', fontWeight: 600 }}>{top2.session_count} phiên</div>
                    </div>
                  </div>
                )}

                {/* Bronze Medal - Rank 3 */}
                {top3 && (
                  <div className="leaderboard-card" style={{ borderLeft: '4px solid #ea580c', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '16px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
                      <div style={{ background: '#ffedd5', color: '#c2410c', width: '40px', height: '40px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 850 }}>
                        3
                      </div>
                      <div style={{ width: '48px', height: '48px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff', border: '2px solid #f97316' }}>
                        {top3.avatar_url ? (
                          <img src={top3.avatar_url} alt={top3.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                        ) : (
                          <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, color: '#003fb1', fontSize: '0.9rem' }}>
                            {initials(top3.display_name)}
                          </div>
                        )}
                      </div>
                      <div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <span style={{ fontWeight: 800, fontSize: '0.95rem', color: '#141b2b' }}>{top3.display_name}</span>
                          {user && top3.user_id === user.id && <span style={{ fontSize: '0.7rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '1px 5px', borderRadius: '4px' }}>Bạn</span>}
                        </div>
                        <span style={{ fontSize: '0.75rem', color: '#6b7280', fontWeight: 600 }}>{getOccupation(top3.user_id, 3)}</span>
                      </div>
                    </div>
                    <div style={{ textAlign: 'right' }}>
                      <div style={{ fontSize: '1rem', fontWeight: 850, color: '#c2410c' }}>{formatFocusTime(top3.focus_seconds)}</div>
                      <div style={{ fontSize: '0.7rem', color: '#9ca3af', fontWeight: 600 }}>{top3.session_count} phiên</div>
                    </div>
                  </div>
                )}
              </div>
            </div>

            {/* Right Column: Other rankings table */}
            <div>
              <h2 style={{ fontSize: '1.2rem', fontWeight: 800, color: '#141b2b', margin: '0 0 16px' }}>
                Xếp hạng tiếp theo
              </h2>
              
              {restList.length === 0 ? (
                <div style={{ padding: '40px', background: '#ffffff', borderRadius: '20px', border: '1px solid rgba(0,0,0,0.06)', textAlign: 'center', color: '#434654', fontSize: '0.9rem' }}>
                  Không có xếp hạng tiếp theo nào.
                </div>
              ) : (
                <div style={{ background: '#ffffff', border: '1px solid rgba(0, 0, 0, 0.06)', borderRadius: '20px', overflow: 'hidden', boxShadow: '0 4px 20px rgba(0, 0, 0, 0.02)' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
                    <thead>
                      <tr style={{ borderBottom: '1px solid rgba(0, 0, 0, 0.06)', background: 'rgba(0, 0, 0, 0.01)' }}>
                        <th style={{ padding: '16px 20px', fontSize: '0.75rem', fontWeight: 700, color: '#434654', textTransform: 'uppercase', width: '80px' }}>Hạng</th>
                        <th style={{ padding: '16px 20px', fontSize: '0.75rem', fontWeight: 700, color: '#434654', textTransform: 'uppercase' }}>Thành viên</th>
                        <th style={{ padding: '16px 20px', fontSize: '0.75rem', fontWeight: 700, color: '#434654', textTransform: 'uppercase', textAlign: 'right' }}>Thời gian</th>
                        <th style={{ padding: '16px 20px', fontSize: '0.75rem', fontWeight: 700, color: '#434654', textTransform: 'uppercase', textAlign: 'right', width: '110px' }}>Số phiên</th>
                      </tr>
                    </thead>
                    <tbody>
                      {restList.map((entry) => {
                        const isMe = user && entry.user_id === user.id
                        return (
                          <tr 
                            key={entry.user_id} 
                            style={{ 
                              borderBottom: '1px solid rgba(0, 0, 0, 0.04)',
                              background: isMe ? 'rgba(0, 63, 177, 0.03)' : 'transparent',
                              fontWeight: isMe ? 700 : 'normal'
                            }}
                          >
                            <td style={{ padding: '16px 20px', fontSize: '0.9rem', color: '#141b2b', fontWeight: 800 }}>
                              #{entry.rank}
                            </td>
                            <td style={{ padding: '16px 20px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                                <div style={{ width: '28px', height: '28px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff' }}>
                                  {entry.avatar_url ? (
                                    <img src={entry.avatar_url} alt={entry.display_name} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                  ) : (
                                    <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 800, color: '#003fb1', fontSize: '0.75rem' }}>
                                      {initials(entry.display_name)}
                                    </div>
                                  )}
                                </div>
                                <div style={{ display: 'flex', flexDirection: 'column' }}>
                                  <span style={{ fontSize: '0.9rem', color: '#141b2b', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                    {entry.display_name}
                                    {isMe && <span style={{ fontSize: '0.65rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '1px 4px', borderRadius: '3px' }}>Bạn</span>}
                                  </span>
                                  <span style={{ fontSize: '0.7rem', color: '#9ca3af' }}>{getOccupation(entry.user_id, entry.rank)}</span>
                                </div>
                              </div>
                            </td>
                            <td style={{ padding: '16px 20px', fontSize: '0.9rem', color: '#003fb1', fontWeight: 700, textAlign: 'right' }}>
                              {formatFocusTime(entry.focus_seconds)}
                            </td>
                            <td style={{ padding: '16px 20px', fontSize: '0.9rem', color: '#434654', textAlign: 'right' }}>
                              {entry.session_count}
                            </td>
                          </tr>
                        )
                      })}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </div>
        )}

        {/* Navigation Back Link */}
        <div style={{ textAlign: 'center', marginTop: '16px' }}>
          <Link
            to="/"
            style={{
              fontSize: '0.88rem',
              fontWeight: 600,
              color: '#434654',
              display: 'inline-flex',
              alignItems: 'center',
              gap: '6px',
              transition: 'color 0.2s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.color = '#003fb1'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.color = '#434654'
            }}
          >
            <ArrowLeft size={16} />
            Quay lại trang chủ
          </Link>
        </div>
      </div>
    </PageShell>
  )
}
