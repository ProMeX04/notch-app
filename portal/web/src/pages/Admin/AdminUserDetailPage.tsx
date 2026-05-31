import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useParams } from '@tanstack/react-router'
import { ArrowLeft, CalendarDays, ChevronLeft, ChevronRight, CreditCard, Database, Laptop, Loader2, RefreshCw, ShieldCheck, UserRound } from 'lucide-react'

import { apiClient } from '@/api/client'

const tablePageSize = 10

type SessionDetail = {
  id: string
  deviceId: string | null
  deviceName: string | null
  platform: string | null
  status: string
  expiresAt: string
  accessExpiresAt: string | null
  createdAt: string
  lastSeenAt: string
  trustedAt: string | null
  updatedAt: string
  revokedAt: string | null
  revokedReason: string | null
}

type PaymentDetail = {
  id: string
  provider: string
  status: string
  amount: number
  currency: string
  orderId: string
  requestId: string
  providerRef: string | null
  orderInfo: string
  createdAt: string
  updatedAt: string
  paidAt: string | null
  guestEmail: string | null
}

type EventDetail = {
  id: string
  createdAt: string
  eventType: string
  outcome: string
  source: string
  sessionId: string | null
  deviceId: string | null
  requestPath: string | null
  requestMethod: string | null
  statusCode: number | null
  userAgent: string | null
  metadata: unknown
}

type UserDetail = {
  user: {
    id: string
    name: string | null
    email: string | null
    isPro: boolean
    isAdmin: boolean
    createdAt: string
    updatedAt: string
  }
  summary: {
    accountAgeDays: number
    lastSeenAt: string | null
    activeSessionCount: number
    revokedSessionCount: number
    expiredSessionCount: number
    trustedDeviceCount: number
    paidPaymentCount: number
    totalPaidRevenue: number
    latestPaymentAt: string | null
    recentFailureEventCount: number
    topEventTypes: { eventType: string; count: number }[]
  }
  sessions: SessionDetail[]
  payments: PaymentDetail[]
  events: EventDetail[]
}

function formatDateTime(value: string | null) {
  if (!value) return 'Chưa có'
  return new Date(value).toLocaleString('vi-VN', { dateStyle: 'medium', timeStyle: 'short' })
}

function formatDate(value: string | null) {
  if (!value) return 'Chưa có'
  return new Date(value).toLocaleDateString('vi-VN')
}

function formatCurrency(value: number, currency = 'VND') {
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency, maximumFractionDigits: 0 }).format(value)
}

function statusClass(status: string) {
  if (status === 'active' || status === 'paid' || status === 'success') return 'admin-pill-green'
  if (status === 'pending' || status === 'expired' || status === 'rejected') return 'admin-pill-yellow'
  return 'admin-pill-red'
}

function humanSessionStatus(status: string) {
  if (status === 'active') return 'Đang hoạt động'
  if (status === 'expired') return 'Đã hết hạn'
  if (status === 'revoked') return 'Đã thu hồi'
  return 'Không rõ'
}

function humanPaymentStatus(status: string) {
  if (status === 'paid') return 'Đã thanh toán'
  if (status === 'pending') return 'Đang chờ'
  if (status === 'failed') return 'Thất bại'
  return status
}

function humanEventName(eventType: string) {
  if (eventType.includes('focus.sync')) return 'Đồng bộ Focus'
  if (eventType.includes('focus.leaderboard_profile')) return 'Cập nhật xếp hạng Focus'
  if (eventType.includes('login')) return 'Đăng nhập'
  if (eventType.includes('signup')) return 'Đăng ký tài khoản'
  if (eventType.includes('logout')) return 'Đăng xuất'
  if (eventType.includes('payment')) return 'Thanh toán'
  if (eventType.includes('session_token')) return 'Lấy quyền dùng Gemini Live'
  if (eventType.includes('oauth')) return 'Kết nối ứng dụng'
  return 'Hoạt động hệ thống'
}

function humanOutcome(outcome: string) {
  if (outcome === 'success') return 'Thành công'
  if (outcome === 'rejected') return 'Bị từ chối'
  return 'Thất bại'
}

function InfoCard({ title, value, note, icon: Icon }: { title: string; value: string | number; note?: string; icon: React.ComponentType<{ size?: number; className?: string }> }) {
  return (
    <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '16px' }}>
        <div>
          <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)', fontWeight: 600 }}>{title}</p>
          <p style={{ margin: '8px 0 0 0', fontSize: '1.75rem', fontWeight: 800 }}>{value}</p>
          {note && <p style={{ margin: '4px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{note}</p>}
        </div>
        <div style={{ padding: '8px', borderRadius: '8px', background: 'rgba(56, 189, 248, 0.1)', color: 'var(--accent)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icon size={20} />
        </div>
      </div>
    </div>
  )
}

function EmptyState({ text }: { text: string }) {
  return <div style={{ border: '1px solid var(--border)', background: 'rgba(255,255,255,0.02)', borderRadius: '12px', padding: '16px', color: 'var(--muted)', fontSize: '0.9rem' }}>{text}</div>
}

function DataTable({ title, description, icon: Icon, children }: { title: string; description: string; icon: React.ComponentType<{ size?: number; className?: string }>; children: React.ReactNode }) {
  return (
    <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', padding: '20px', display: 'grid', gap: '16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h2 style={{ fontSize: '1.1rem', fontWeight: 700, margin: 0 }}>{title}</h2>
          <p style={{ fontSize: '0.8rem', color: 'var(--muted)', margin: '2px 0 0 0' }}>{description}</p>
        </div>
        <Icon className="text-indigo-500" size={20} />
      </div>
      {children}
    </div>
  )
}

export function AdminUserDetailPage() {
  const { id } = useParams({ from: '/admin/users/$id' })
  const [data, setData] = useState<UserDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [updating, setUpdating] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [eventsPage, setEventsPage] = useState(1)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const loadUser = useCallback(async () => {
    setError(null)
    try {
      const response = await apiClient.get<UserDetail>(`/api/admin/users/${id}`)
      setData(response.data)
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Không tải được chi tiết user')
    } finally {
      setLoading(false)
    }
  }, [id])

  const initialLoad = useCallback(async () => {
    setLoading(true)
    await loadUser()
  }, [loadUser])

  const startPolling = useCallback(() => {
    if (pollRef.current) return
    pollRef.current = setInterval(() => {
      void loadUser()
    }, 5000)
  }, [loadUser])

  const stopPolling = useCallback(() => {
    if (pollRef.current) {
      clearInterval(pollRef.current)
      pollRef.current = null
    }
  }, [])

  useEffect(() => {
    void initialLoad()
    startPolling()
    return () => stopPolling()
  }, [initialLoad, startPolling, stopPolling])

  const updateUserRole = async (isPro: boolean, isAdmin: boolean) => {
    setUpdating(true)
    setError(null)
    try {
      const response = await apiClient.patch(`/api/admin/users/${id}`, { isPro, isAdmin })
      // Update UI with response or reload
      if (response.status === 200) {
        await loadUser()
      }
    } catch (patchErr) {
      setError(patchErr instanceof Error ? patchErr.message : 'Không cập nhật được quyền người dùng')
    } finally {
      setUpdating(false)
    }
  }

  const latestPayment = useMemo(() => data?.payments[0] ?? null, [data])
  const eventsTotalPages = Math.max(Math.ceil((data?.events.length ?? 0) / tablePageSize), 1)
  const pagedEvents = useMemo(() => {
    if (!data) return []
    const start = (eventsPage - 1) * tablePageSize
    return data.events.slice(start, start + tablePageSize)
  }, [data, eventsPage])

  useEffect(() => {
    if (eventsPage > eventsTotalPages) setEventsPage(eventsTotalPages)
  }, [eventsPage, eventsTotalPages])

  if (loading && !data) {
    return (
      <div style={{ display: 'flex', height: '300px', alignItems: 'center', justifyContent: 'center' }}>
        <Loader2 className="animate-spin text-[#1a73e8]" size={36} />
      </div>
    )
  }

  if (error && !data) {
    return (
      <div style={{ border: '1px solid var(--border)', background: 'var(--card)', borderRadius: '24px', padding: '40px', textAlign: 'center' }}>
        <h1 style={{ fontSize: '1.5rem', fontWeight: 700, margin: 0 }}>Không tải được user</h1>
        <p style={{ color: 'var(--muted)', marginTop: '8px' }}>{error}</p>
        <div style={{ marginTop: '24px', display: 'flex', justifyContent: 'center', gap: '12px' }}>
          <Link to="/admin/users" className="portal-button-ghost" style={{ border: '1px solid var(--border)', padding: '10px 16px', borderRadius: '12px', fontWeight: 600, display: 'inline-flex', alignItems: 'center' }}>Quay lại</Link>
          <button type="button" onClick={() => void loadUser()} className="portal-button" style={{ padding: '10px 16px', borderRadius: '12px', fontWeight: 600 }}>Thử lại</button>
        </div>
      </div>
    )
  }

  if (!data) return null

  return (
    <div className="space-y-6">
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '16px', borderBottom: '1px solid var(--border)', paddingBottom: '16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px' }}>
          <Link 
            to="/admin/users" 
            className="portal-button-ghost" 
            style={{ 
              display: 'flex', 
              alignItems: 'center', 
              justifyContent: 'center', 
              padding: '10px', 
              borderRadius: '12px', 
              border: '1px solid var(--border)' 
            }}
          >
            <ArrowLeft size={20} />
          </Link>
          <div>
            <h1 style={{ fontSize: '1.75rem', fontWeight: 700, margin: 0 }}>{data.user.name || 'Người dùng không tên'}</h1>
            <p style={{ color: 'var(--muted)', fontSize: '0.9rem', margin: '4px 0 0 0' }}>{data.user.email || 'Không có email'}</p>
          </div>
        </div>
        <button 
          type="button"
          onClick={() => void loadUser()} 
          disabled={loading || updating} 
          className="portal-button"
          style={{ 
            display: 'inline-flex', 
            alignItems: 'center', 
            gap: '6px',
            padding: '10px 16px',
            borderRadius: '12px',
            fontWeight: 600,
            fontSize: '0.9rem',
            cursor: 'pointer'
          }}
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Làm mới
        </button>
      </div>

      {error && (
        <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)', color: '#ef4444', padding: '12px 16px', borderRadius: '12px', fontSize: '0.9rem' }}>
          {error}
        </div>
      )}

      <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', padding: '24px' }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '24px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '20px' }}>
            <div style={{ display: 'flex', height: '80px', width: '80px', alignItems: 'center', justifyContent: 'center', borderRadius: '8px', background: 'rgba(56, 189, 248, 0.1)', fontSize: '2.5rem', fontWeight: 600, color: 'var(--accent)', textTransform: 'uppercase' }} className="h-20 w-20">
              {data.user.name?.[0] || data.user.email?.[0] || '?'}
            </div>
            <div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                <span className={`admin-pill ${data.user.isPro ? 'admin-pill-blue' : 'admin-pill-gray'}`}>{data.user.isPro ? 'Pro' : 'Miễn phí'}</span>
                <span className={`admin-pill ${data.user.isAdmin ? 'admin-pill-yellow' : 'admin-pill-gray'}`}>{data.user.isAdmin ? 'Admin' : 'User'}</span>
              </div>
              <p style={{ color: 'var(--muted)', fontSize: '0.85rem', margin: '12px 0 0 0' }}>Tham gia {formatDate(data.user.createdAt)} · cập nhật {formatDateTime(data.user.updatedAt)}</p>
              <p style={{ color: 'var(--muted)', fontSize: '0.85rem', margin: '4px 0 0 0' }}>Hoạt động gần nhất: <span style={{ color: 'var(--foreground)', fontWeight: 600 }}>{formatDateTime(data.summary.lastSeenAt)}</span></p>
            </div>
          </div>

          <div style={{ border: '1px solid var(--border)', background: 'rgba(255,255,255,0.02)', borderRadius: '16px', padding: '16px', fontSize: '0.9rem', color: 'var(--muted)', display: 'grid', gap: '8px' }}>
            <p style={{ margin: 0, color: 'var(--foreground)', fontWeight: 600 }}>Tài khoản {data.summary.accountAgeDays} ngày tuổi</p>
            <p style={{ margin: 0 }}>{data.summary.activeSessionCount} phiên đang hoạt động · {data.summary.trustedDeviceCount} thiết bị tin cậy</p>
            
            {/* Role Switches */}
            <div style={{ display: 'flex', gap: '16px', marginTop: '8px', borderTop: '1px solid var(--border)', paddingTop: '12px' }}>
              <label style={{ display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: 'var(--foreground)' }}>
                <input 
                  type="checkbox" 
                  checked={data.user.isPro} 
                  disabled={updating}
                  onChange={e => void updateUserRole(e.target.checked, data.user.isAdmin)}
                  style={{ cursor: 'pointer' }}
                />
                Kích hoạt Pro
              </label>
              <label style={{ display: 'flex', alignItems: 'center', gap: '6px', cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem', color: 'var(--foreground)' }}>
                <input 
                  type="checkbox" 
                  checked={data.user.isAdmin} 
                  disabled={updating}
                  onChange={e => void updateUserRole(data.user.isPro, e.target.checked)}
                  style={{ cursor: 'pointer' }}
                />
                Quyền Admin
              </label>
            </div>
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px' }}>
        <InfoCard title="Active sessions" value={data.summary.activeSessionCount} note={`${data.summary.expiredSessionCount} expired · ${data.summary.revokedSessionCount} revoked`} icon={Laptop} />
        <InfoCard title="Trusted devices" value={data.summary.trustedDeviceCount} note="Dựa trên trustedAt" icon={ShieldCheck} />
        <InfoCard title="Paid revenue" value={formatCurrency(data.summary.totalPaidRevenue)} note={`${data.summary.paidPaymentCount} paid payments`} icon={CreditCard} />
        <InfoCard title="Failure/rejected events" value={data.summary.recentFailureEventCount} note="50 event gần nhất" icon={Database} />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(360px, 1fr))', gap: '24px' }}>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', padding: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <h2 style={{ fontSize: '1rem', fontWeight: 600, margin: 0 }}>Thiết bị & phiên đăng nhập</h2>
            <Laptop className="text-indigo-500" size={20} />
          </div>
          {data.sessions.length === 0 ? <EmptyState text="User chưa có session nào." /> : (
            <div style={{ display: 'grid', gap: '12px' }}>
              {data.sessions.slice(0, 5).map(session => (
                <div key={session.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: '16px', border: '1px solid var(--border)', background: 'rgba(255,255,255,0.01)', padding: '12px', borderRadius: '12px' }}>
                  <div style={{ minWidth: 0 }}>
                    <p className="truncate" style={{ margin: 0, fontWeight: 600, fontSize: '0.9rem' }}>{session.deviceName || 'Thiết bị chưa đặt tên'}</p>
                    <p style={{ margin: '4px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{session.platform || 'Không rõ nền tảng'} · Hoạt động {formatDateTime(session.lastSeenAt)}</p>
                  </div>
                  <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px', justifyContent: 'flex-end', flexShrink: 0 }}>
                    <span className={`admin-pill ${statusClass(session.status)}`}>{humanSessionStatus(session.status)}</span>
                    {session.trustedAt && <span className="admin-pill admin-pill-blue">Tin cậy</span>}
                  </div>
                </div>
              ))}
              {data.sessions.length > 5 && <p style={{ margin: 0, fontSize: '0.75rem', color: 'var(--muted)' }}>Còn {data.sessions.length - 5} phiên cũ hơn được ẩn để dễ đọc.</p>}
            </div>
          )}
        </div>

        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', padding: '20px' }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
            <div>
              <h2 style={{ fontSize: '1rem', fontWeight: 600, margin: 0 }}>Event phổ biến</h2>
              <p style={{ fontSize: '0.75rem', color: 'var(--muted)', margin: '2px 0 0 0' }}>Từ hoạt động gần đây.</p>
            </div>
            <UserRound className="text-indigo-500" size={24} />
          </div>
          <div style={{ display: 'grid', gap: '12px' }}>
            {data.summary.topEventTypes.length === 0 ? <EmptyState text="Chưa có event." /> : data.summary.topEventTypes.map(event => (
              <div key={event.eventType} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', border: '1px solid var(--border)', background: 'rgba(255,255,255,0.01)', padding: '12px', borderRadius: '12px' }}>
                <span className="truncate" style={{ fontSize: '0.85rem', fontWeight: 600 }}>{event.eventType}</span>
                <span style={{ background: 'rgba(255,255,255,0.05)', borderRadius: '99px', padding: '2px 8px', fontSize: '0.75rem', fontWeight: 700 }}>{event.count}</span>
              </div>
            ))}
          </div>
          {latestPayment && (
            <div style={{ marginTop: '24px', border: '1px solid rgba(16, 185, 129, 0.2)', background: 'rgba(16, 185, 129, 0.05)', padding: '16px', borderRadius: '16px' }}>
              <p style={{ margin: 0, fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', color: '#10b981', letterSpacing: '0.05em' }}>Payment mới nhất</p>
              <p style={{ margin: '8px 0 4px 0', fontSize: '1.25rem', fontWeight: 800 }}>{formatCurrency(latestPayment.amount, latestPayment.currency)}</p>
              <p style={{ margin: 0, fontSize: '0.8rem', color: 'var(--muted)' }}>{latestPayment.provider} · {latestPayment.status} · {formatDateTime(latestPayment.createdAt)}</p>
            </div>
          )}
        </div>
      </div>

      <DataTable title="Payments" icon={CreditCard} description="Lịch sử thanh toán của người dùng này.">
        {data.payments.length === 0 ? <EmptyState text="User chưa có payment nào." /> : (
          <div className="overflow-x-auto" style={{ border: '1px solid var(--border)', borderRadius: '16px' }}>
            <table className="admin-console-table min-w-[900px]">
              <thead>
                <tr>
                  <th>Thời gian</th>
                  <th>Cổng thanh toán</th>
                  <th>Trạng thái</th>
                  <th>Số tiền</th>
                  <th>Nội dung</th>
                </tr>
              </thead>
              <tbody>
                {data.payments.map(payment => (
                  <tr key={payment.id}>
                    <td>{formatDateTime(payment.paidAt ?? payment.createdAt)}</td>
                    <td style={{ fontWeight: 600 }}>{payment.provider.toUpperCase()}</td>
                    <td><span className={`admin-pill ${statusClass(payment.status)}`}>{humanPaymentStatus(payment.status)}</span></td>
                    <td style={{ fontWeight: 600, color: '#10b981' }}>{formatCurrency(payment.amount, payment.currency)}</td>
                    <td style={{ color: 'var(--muted)' }}>{payment.orderInfo}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </DataTable>

      <DataTable title="Recent events" icon={CalendarDays} description="Nhật ký hoạt động gần đây của tài khoản này.">
        {data.events.length === 0 ? <EmptyState text="User chưa có AppEvent nào." /> : (
          <>
            <div className="overflow-x-auto" style={{ border: '1px solid var(--border)', borderRadius: '16px' }}>
              <table className="admin-console-table min-w-[1100px]">
                <thead>
                  <tr>
                    <th>Thời gian</th>
                    <th>Hoạt động</th>
                    <th>Kết quả</th>
                  </tr>
                </thead>
                <tbody>
                  {pagedEvents.map(event => (
                    <tr key={event.id} className="align-top">
                      <td style={{ whiteSpace: 'nowrap', color: 'var(--muted)' }}>{formatDateTime(event.createdAt)}</td>
                      <td style={{ fontWeight: 600 }}>{humanEventName(event.eventType)}</td>
                      <td>
                        <span className={`admin-pill ${statusClass(event.outcome)}`}>
                          {event.statusCode ? `${humanOutcome(event.outcome)} · Code ${event.statusCode}` : humanOutcome(event.outcome)}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {data.events.length > tablePageSize && (
              <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', borderTop: '1px solid var(--border)', paddingTop: '16px', gap: '12px' }}>
                <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--muted)' }}>Trang {eventsPage} / {eventsTotalPages} · {data.events.length} event gần đây</p>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button
                    type="button"
                    onClick={() => setEventsPage(current => Math.max(current - 1, 1))}
                    disabled={eventsPage <= 1 || loading}
                    className="portal-button-ghost"
                    style={{ 
                      display: 'inline-flex', 
                      alignItems: 'center', 
                      gap: '6px',
                      padding: '8px 14px',
                      borderRadius: '10px',
                      border: '1px solid var(--border)',
                      fontSize: '0.85rem',
                      fontWeight: 600,
                      cursor: 'pointer'
                    }}
                  >
                    <ChevronLeft size={14} />
                    Trước
                  </button>
                  <button
                    type="button"
                    onClick={() => setEventsPage(current => Math.min(current + 1, eventsTotalPages))}
                    disabled={eventsPage >= eventsTotalPages || loading}
                    className="portal-button-ghost"
                    style={{ 
                      display: 'inline-flex', 
                      alignItems: 'center', 
                      gap: '6px',
                      padding: '8px 14px',
                      borderRadius: '10px',
                      border: '1px solid var(--border)',
                      fontSize: '0.85rem',
                      fontWeight: 600,
                      cursor: 'pointer'
                    }}
                  >
                    Sau
                    <ChevronRight size={14} />
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </DataTable>
    </div>
  )
}
