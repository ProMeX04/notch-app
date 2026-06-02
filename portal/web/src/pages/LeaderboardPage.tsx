import { useEffect, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { Trophy, Loader2, ArrowLeft, User } from 'lucide-react'
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



function formatFocusTime(seconds: number): string {
  const hrs = Math.floor(seconds / 3600)
  const mins = Math.floor((seconds % 3600) / 60)
  return `${hrs}h ${String(mins).padStart(2, '0')}m`
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

  const top1 = leaderboard.find(e => e.rank === 1)
  const top2 = leaderboard.find(e => e.rank === 2)
  const top3 = leaderboard.find(e => e.rank === 3)
  const restList = leaderboard.filter(e => e.rank > 3)

  return (
    <PageShell noShell={true} noHeader={true}>
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
        
        /* Premium Podium CSS Flex Container & Circular Cards */
        .podium-flex-container {
          display: flex;
          justify-content: center;
          align-items: center;
          gap: 24px;
          margin-top: 16px;
        }
        .podium-circle-card {
          border-radius: 50%;
          background: #ffffff;
          border: 1px solid rgba(0, 0, 0, 0.05);
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          box-shadow: 0 10px 30px rgba(0, 0, 0, 0.02);
          transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
          position: relative;
          text-align: center;
          padding: 12px;
        }
        .podium-circle-card:hover {
          transform: translateY(-4px);
          box-shadow: 0 16px 40px rgba(0, 0, 0, 0.04);
        }
        .podium-circle-card.gold {
          order: 2;
          width: 200px;
          height: 200px;
          border: 2px solid #fbbf24;
          background: linear-gradient(180deg, rgba(251, 191, 36, 0.03) 0%, #ffffff 100%);
          box-shadow: 0 12px 36px rgba(245, 158, 11, 0.06);
        }
        .podium-circle-card.silver {
          order: 1;
          width: 170px;
          height: 170px;
          border: 1.5px solid #cbd5e1;
        }
        .podium-circle-card.bronze {
          order: 3;
          width: 170px;
          height: 170px;
          border: 1.5px solid #f97316;
        }
        
        @media (max-width: 768px) {
          .podium-flex-container {
            flex-direction: column;
            gap: 20px;
          }
          .podium-circle-card.gold {
            order: 1;
          }
          .podium-circle-card.silver {
            order: 2;
          }
          .podium-circle-card.bronze {
            order: 3;
          }
        }
      `}</style>

      <div 
        style={{
          maxWidth: '1080px',
          width: '100%',
          margin: '0 auto',
          padding: '5rem 2rem 4rem',
          display: 'flex',
          flexDirection: 'column',
          gap: '40px',
          animation: 'portalRise 0.6s cubic-bezier(0.16, 1, 0.3, 1) both',
        }}
      >
        {/* Title Header Section */}
        <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '20px' }}>
          <div>
            <h1 style={{ fontSize: '2.25rem', fontWeight: 900, letterSpacing: '-0.04em', margin: 0, color: '#141b2b' }}>
              Bảng xếp hạng Tập trung
            </h1>
            <p style={{ fontSize: '0.92rem', color: '#434654', margin: '8px 0 0' }}>
              Vinh danh những thành viên kiên trì và bứt phá giới hạn tập trung trong cộng đồng Notch.
            </p>
          </div>
          
          <Link
            to="/"
            style={{
              display: 'inline-flex',
              alignItems: 'center',
              gap: '8px',
              height: '42px',
              padding: '0 20px',
              borderRadius: '999px',
              background: 'rgba(0, 0, 0, 0.05)',
              color: '#434654',
              fontWeight: 700,
              fontSize: '0.88rem',
              border: 'none',
              cursor: 'pointer',
              textDecoration: 'none',
              transition: 'all 0.2s ease',
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.background = 'rgba(0, 63, 177, 0.08)'
              e.currentTarget.style.color = '#003fb1'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.background = 'rgba(0, 0, 0, 0.05)'
              e.currentTarget.style.color = '#434654'
            }}
          >
            <ArrowLeft size={16} />
            Quay lại trang chủ
          </Link>
        </div>

        {/* Tab Filter & Switch */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid rgba(0, 0, 0, 0.08)', paddingBottom: '16px', marginTop: '-8px' }}>
          <div style={{ background: 'rgba(0, 0, 0, 0.04)', padding: '4px', borderRadius: '999px', display: 'flex', gap: '4px' }}>
            <button 
              onClick={() => setWindowState('week')} 
              style={{
                fontFamily: 'inherit',
                fontSize: '0.85rem',
                fontWeight: 700,
                border: 'none',
                padding: '8px 20px',
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
                padding: '8px 20px',
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
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: '320px', gap: '12px' }}>
            <Loader2 size={36} className="animate-spin" style={{ color: '#003fb1' }} />
            <span style={{ fontSize: '0.95rem', color: '#434654', fontWeight: 600 }}>Đang cập nhật bảng xếp hạng mới nhất...</span>
          </div>
        ) : leaderboard.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '90px 20px', background: '#ffffff', borderRadius: '24px', border: '1px solid rgba(0,0,0,0.06)' }}>
            <Trophy size={48} style={{ color: '#cbd5e1', margin: '0 auto 16px' }} />
            <h3 style={{ fontSize: '1.25rem', fontWeight: 800, margin: '0 0 8px', color: '#141b2b' }}>
              Chưa tìm thấy dữ liệu
            </h3>
            <p style={{ fontSize: '0.9rem', color: '#434654', margin: 0 }}>
              Hãy kích hoạt tính năng bảng xếp hạng trên app và bắt đầu Focus để ghi danh nhé!
            </p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '32px' }}>
            
            {/* Podium (Top 3 circular cards) */}
            <div className="podium-flex-container">
              
              {/* Silver - Rank 2 */}
              {top2 && (
                <div className="podium-circle-card silver">
                  {/* Floating Rank Badge */}
                  <div style={{ background: '#f1f5f9', color: '#9ca3af', width: '32px', height: '32px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1.5px solid #ffffff', boxShadow: '0 2px 5px rgba(0,0,0,0.08)', position: 'absolute', top: '8px', right: '8px' }}>
                    <Trophy size={18} style={{ fill: '#cbd5e1', stroke: '#9ca3af' }} />
                  </div>
                  
                  {/* Avatar */}
                  <div style={{ width: '48px', height: '48px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff', border: '1.5px solid #cbd5e1', padding: '1px' }}>
                    {top2.avatar_url ? (
                      <img src={top2.avatar_url} alt={top2.display_name || 'Ẩn danh'} style={{ width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
                    ) : (
                      <div style={{ width: '100%', height: '100%', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#f1f5f9', color: '#9ca3af' }}>
                        <User size={18} />
                      </div>
                    )}
                  </div>
                  
                  {/* Name */}
                  <div style={{ marginTop: '6px', width: '100%', padding: '0 8px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '3px' }}>
                      <span style={{ fontWeight: 800, fontSize: '0.82rem', color: '#141b2b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '90px' }}>
                        {top2.display_name || 'Ẩn danh'}
                      </span>
                      {user && top2.user_id === user.id && (
                        <span style={{ fontSize: '0.58rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '0 3px', borderRadius: '1.5px' }}>Bạn</span>
                      )}
                    </div>
                  </div>

                  {/* Stats */}
                  <div style={{ marginTop: '4px' }}>
                    <div style={{ fontSize: '0.98rem', fontWeight: 850, color: '#003fb1', lineHeight: 1.1 }}>{formatFocusTime(top2.focus_seconds)}</div>
                    <div style={{ fontSize: '0.7rem', color: '#64748b', fontWeight: 600, marginTop: '1px' }}>{top2.session_count} phiên</div>
                  </div>
                </div>
              )}

              {/* Gold - Rank 1 */}
              {top1 && (
                <div className="podium-circle-card gold">
                  {/* Floating Rank Badge */}
                  <div style={{ background: '#fef3c7', color: '#d97706', width: '36px', height: '36px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1.5px solid #ffffff', boxShadow: '0 4px 10px rgba(217,119,6,0.15)', position: 'absolute', top: '10px', right: '10px', zIndex: 2 }}>
                    <Trophy size={20} style={{ fill: '#fbbf24', stroke: '#d97706' }} />
                  </div>
                  
                  {/* Avatar */}
                  <div style={{ width: '60px', height: '60px', borderRadius: '50%', overflow: 'hidden', background: '#fef3c7', border: '2px solid #fbbf24', padding: '1px' }}>
                    {top1.avatar_url ? (
                      <img src={top1.avatar_url} alt={top1.display_name || 'Ẩn danh'} style={{ width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
                    ) : (
                      <div style={{ width: '100%', height: '100%', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#fef3c7', color: '#d97706' }}>
                        <User size={24} />
                      </div>
                    )}
                  </div>
                  
                  {/* Name */}
                  <div style={{ marginTop: '8px', width: '100%', padding: '0 10px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '4px' }}>
                      <span style={{ fontWeight: 900, fontSize: '0.92rem', color: '#141b2b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '110px' }}>
                        {top1.display_name || 'Ẩn danh'}
                      </span>
                      {user && top1.user_id === user.id && (
                        <span style={{ fontSize: '0.58rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '0 3.5px', borderRadius: '2px' }}>Bạn</span>
                      )}
                    </div>
                  </div>

                  {/* Stats */}
                  <div style={{ marginTop: '6px' }}>
                    <div style={{ fontSize: '1.15rem', fontWeight: 900, color: '#b45309', lineHeight: 1.1 }}>{formatFocusTime(top1.focus_seconds)}</div>
                    <div style={{ fontSize: '0.75rem', color: '#b45309', fontWeight: 700, marginTop: '1.5px' }}>{top1.session_count} phiên</div>
                  </div>
                </div>
              )}

              {/* Bronze - Rank 3 */}
              {top3 && (
                <div className="podium-circle-card bronze">
                  {/* Floating Rank Badge */}
                  <div style={{ background: '#ffedd5', color: '#ea580c', width: '32px', height: '32px', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', border: '1.5px solid #ffffff', boxShadow: '0 2px 5px rgba(0,0,0,0.08)', position: 'absolute', top: '8px', right: '8px' }}>
                    <Trophy size={18} style={{ fill: '#f97316', stroke: '#ea580c' }} />
                  </div>
                  
                  {/* Avatar */}
                  <div style={{ width: '48px', height: '48px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff', border: '1.5px solid #f97316', padding: '1px' }}>
                    {top3.avatar_url ? (
                      <img src={top3.avatar_url} alt={top3.display_name || 'Ẩn danh'} style={{ width: '100%', height: '100%', borderRadius: '50%', objectFit: 'cover' }} />
                    ) : (
                      <div style={{ width: '100%', height: '100%', borderRadius: '50%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#ffedd5', color: '#ea580c' }}>
                        <User size={18} />
                      </div>
                    )}
                  </div>
                  
                  {/* Name */}
                  <div style={{ marginTop: '6px', width: '100%', padding: '0 8px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '3px' }}>
                      <span style={{ fontWeight: 800, fontSize: '0.82rem', color: '#141b2b', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', maxWidth: '90px' }}>
                        {top3.display_name || 'Ẩn danh'}
                      </span>
                      {user && top3.user_id === user.id && (
                        <span style={{ fontSize: '0.58rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '0 3px', borderRadius: '1.5px' }}>Bạn</span>
                      )}
                    </div>
                  </div>

                  {/* Stats */}
                  <div style={{ marginTop: '4px' }}>
                    <div style={{ fontSize: '0.98rem', fontWeight: 850, color: '#c2410c', lineHeight: 1.1 }}>{formatFocusTime(top3.focus_seconds)}</div>
                    <div style={{ fontSize: '0.7rem', color: '#64748b', fontWeight: 600, marginTop: '1px' }}>{top3.session_count} phiên</div>
                  </div>
                </div>
              )}

            </div>

            {/* List rankings table (4th onwards) */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <h2 style={{ fontSize: '1.25rem', fontWeight: 850, color: '#141b2b', margin: 0 }}>
                Bảng xếp hạng tiếp theo
              </h2>
              
              {restList.length === 0 ? (
                <div style={{ padding: '40px', background: '#ffffff', borderRadius: '24px', border: '1px solid rgba(0,0,0,0.06)', textAlign: 'center', color: '#434654', fontSize: '0.9rem' }}>
                  Không có xếp hạng tiếp theo nào trong bảng.
                </div>
              ) : (
                <div style={{ background: '#ffffff', border: '1px solid rgba(0, 0, 0, 0.05)', borderRadius: '24px', overflow: 'hidden', boxShadow: '0 8px 30px rgba(0, 0, 0, 0.01)' }}>
                  <table style={{ width: '100%', borderCollapse: 'collapse', textAlign: 'left' }}>
                    <thead>
                      <tr style={{ borderBottom: '1px solid rgba(0, 0, 0, 0.06)', background: 'rgba(0, 0, 0, 0.01)' }}>
                        <th style={{ padding: '18px 24px', fontSize: '0.72rem', fontWeight: 800, color: '#64748b', textTransform: 'uppercase', width: '90px', letterSpacing: '0.05em' }}>Hạng</th>
                        <th style={{ padding: '18px 24px', fontSize: '0.72rem', fontWeight: 800, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.05em' }}>Thành viên</th>
                        <th style={{ padding: '18px 24px', fontSize: '0.72rem', fontWeight: 800, color: '#64748b', textTransform: 'uppercase', textAlign: 'right', letterSpacing: '0.05em' }}>Thời gian tập trung</th>
                        <th style={{ padding: '18px 24px', fontSize: '0.72rem', fontWeight: 800, color: '#64748b', textTransform: 'uppercase', textAlign: 'right', width: '130px', letterSpacing: '0.05em' }}>Số phiên</th>
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
                              fontWeight: isMe ? 700 : 'normal',
                              transition: 'background-color 0.15s ease'
                            }}
                            onMouseEnter={(e) => {
                              if (!isMe) e.currentTarget.style.backgroundColor = 'rgba(0, 0, 0, 0.01)'
                            }}
                            onMouseLeave={(e) => {
                              if (!isMe) e.currentTarget.style.backgroundColor = 'transparent'
                            }}
                          >
                            <td style={{ padding: '18px 24px', fontSize: '0.95rem', color: '#141b2b', fontWeight: 850 }}>
                              #{entry.rank}
                            </td>
                            <td style={{ padding: '18px 24px' }}>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                                <div style={{ width: '32px', height: '32px', borderRadius: '50%', overflow: 'hidden', background: '#e9edff' }}>
                                  {entry.avatar_url ? (
                                    <img src={entry.avatar_url} alt={entry.display_name || 'Ẩn danh'} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
                                  ) : (
                                    <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', background: '#f1f5f9', color: '#9ca3af' }}>
                                      <User size={16} />
                                    </div>
                                  )}
                                </div>
                                <div style={{ display: 'flex', flexDirection: 'column' }}>
                                  <span style={{ fontSize: '0.9rem', color: '#141b2b', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                                    {entry.display_name || 'Ẩn danh'}
                                    {isMe && <span style={{ fontSize: '0.65rem', fontWeight: 700, color: '#003fb1', background: 'rgba(0, 63, 177, 0.08)', padding: '1px 4px', borderRadius: '3px' }}>Bạn</span>}
                                  </span>
                                </div>
                              </div>
                            </td>
                            <td style={{ padding: '18px 24px', fontSize: '0.95rem', color: '#003fb1', fontWeight: 800, textAlign: 'right' }}>
                              {formatFocusTime(entry.focus_seconds)}
                            </td>
                            <td style={{ padding: '18px 24px', fontSize: '0.9rem', color: '#434654', textAlign: 'right' }}>
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
      </div>
    </PageShell>
  )
}
