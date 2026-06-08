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
    <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between gap-4">
        <div>
          <p className="text-xs font-medium text-[#5f6368]">{title}</p>
          <p className="mt-2 text-2xl font-normal text-[#202124]">{value}</p>
          {note && <p className="mt-1 text-xs text-[#5f6368]">{note}</p>}
        </div>
        <div className="rounded border border-[#d2e3fc] bg-[#e8f0fe] p-2 text-[#1967d2]">
          <Icon size={20} />
        </div>
      </div>
    </div>
  )
}

function EmptyState({ text }: { text: string }) {
  return <div className="rounded border border-[#e8eaed] bg-[#f8f9fa] p-4 text-sm text-[#5f6368]">{text}</div>
}

function DataTable({ title, description, icon: Icon, children }: { title: string; description: string; icon: React.ComponentType<{ size?: number; className?: string }>; children: React.ReactNode }) {
  return (
    <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
      <div className="mb-5 flex items-center justify-between">
        <div>
          <h2 className="text-base font-medium text-[#202124]">{title}</h2>
          <p className="text-sm text-[#5f6368]">{description}</p>
        </div>
        <Icon className="text-[#1a73e8]" size={20} />
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
    const timer = setTimeout(() => {
      void initialLoad()
    }, 0)
    startPolling()
    return () => {
      clearTimeout(timer)
      stopPolling()
    }
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

  const latestPayment = useMemo(() => (data?.payments || [])[0] ?? null, [data])
  const eventsTotalPages = Math.max(Math.ceil((data?.events?.length ?? 0) / tablePageSize), 1)
  const activeEventsPage = Math.min(eventsPage, eventsTotalPages)
  const pagedEvents = useMemo(() => {
    if (!data || !data.events) return []
    const start = (activeEventsPage - 1) * tablePageSize
    return data.events.slice(start, start + tablePageSize)
  }, [data, activeEventsPage])

  if (loading && !data) {
    return (
      <div className="h-full w-full flex items-center justify-center">
        <Loader2 className="animate-spin text-indigo-500" size={48} />
      </div>
    )
  }

  if (error && !data) {
    return (
      <div className="rounded border border-[#dadce0] bg-white p-8 text-center shadow-sm">
        <h1 className="text-2xl font-medium text-[#202124]">Không tải được user</h1>
        <p className="mt-2 text-[#5f6368]">{error}</p>
        <div className="mt-6 flex justify-center gap-3">
          <Link
            to="/admin/users"
            className="rounded border border-[#dadce0] bg-white px-5 py-3 font-medium text-[#3c4043] inline-flex items-center justify-center"
          >
            Quay lại
          </Link>
          <button
            type="button"
            onClick={() => void loadUser()}
            className="rounded bg-[#1a73e8] px-5 py-3 font-medium text-white cursor-pointer"
          >
            Thử lại
          </button>
        </div>
      </div>
    )
  }

  if (!data) return null

  return (
    <div className="space-y-6 bg-[#f8f9fa] font-sans text-[#202124]">
      <div className="flex items-center justify-between gap-4 border-b border-[#dadce0] pb-4">
        <div className="flex items-center gap-4">
          <Link
            to="/admin/users"
            className="rounded border border-[#dadce0] bg-white p-3 text-[#5f6368] hover:bg-[#f8f9fa] hover:text-[#1a73e8] transition-colors"
          >
            <ArrowLeft size={20} />
          </Link>
          <div>
            <h1 className="text-3xl font-medium tracking-tight text-[#202124]">{data.user.name || 'Người dùng không tên'}</h1>
            <p className="mt-1 text-sm text-[#5f6368]">{data.user.email || 'Không có email'}</p>
          </div>
        </div>
        <button
          type="button"
          onClick={() => void loadUser()}
          disabled={loading || updating}
          className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] transition-colors disabled:opacity-60 cursor-pointer"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Làm mới
        </button>
      </div>

      {error && (
        <div className="rounded border border-rose-200 bg-rose-50 p-4 text-sm font-medium text-rose-700">
          {error}
        </div>
      )}

      <div className="rounded border border-[#dadce0] bg-white p-6 shadow-sm">
        <div className="flex flex-col gap-6 lg:flex-row lg:items-center lg:justify-between">
          <div className="flex items-center gap-5">
            <div className="flex h-20 w-20 items-center justify-center rounded bg-[#e8f0fe] text-3xl font-medium uppercase text-[#1967d2]">
              {data.user.name?.[0] || data.user.email?.[0] || '?'}
            </div>
            <div>
              <div className="flex flex-wrap gap-2">
                <span className={`admin-pill ${data.user.isPro ? 'admin-pill-blue' : 'admin-pill-gray'}`}>{data.user.isPro ? 'Pro' : 'Free'}</span>
                <span className={`admin-pill ${data.user.isAdmin ? 'admin-pill-yellow' : 'admin-pill-gray'}`}>{data.user.isAdmin ? 'Admin' : 'User'}</span>
              </div>
              <p className="mt-3 text-sm text-[#5f6368]">Tham gia {formatDate(data.user.createdAt)} · cập nhật {formatDateTime(data.user.updatedAt)}</p>
              <p className="mt-1 text-sm text-[#5f6368]">Hoạt động gần nhất: <span className="font-medium text-[#202124]">{formatDateTime(data.summary.lastSeenAt)}</span></p>
            </div>
          </div>

          <div className="rounded border border-[#e8eaed] bg-[#f8f9fa] p-4 text-sm text-[#5f6368]">
            <p className="font-medium text-[#202124]">Tài khoản {data.summary.accountAgeDays} ngày tuổi</p>
            <p className="mt-1">{data.summary.activeSessionCount} phiên đang hoạt động · {data.summary.trustedDeviceCount} thiết bị tin cậy</p>
            
            {/* Role Switches */}
            <div className="flex gap-4 mt-3 border-t border-[#dadce0] pt-3">
              <label className="flex items-center gap-2 cursor-pointer text-xs font-semibold text-[#5f6368] hover:text-[#202124]">
                <input 
                  type="checkbox" 
                  checked={data.user.isPro} 
                  disabled={updating}
                  onChange={e => void updateUserRole(e.target.checked, data.user.isAdmin)}
                  className="cursor-pointer"
                />
                Kích hoạt Pro
              </label>
              <label className="flex items-center gap-2 cursor-pointer text-xs font-semibold text-[#5f6368] hover:text-[#202124]">
                <input 
                  type="checkbox" 
                  checked={data.user.isAdmin} 
                  disabled={updating}
                  onChange={e => void updateUserRole(data.user.isPro, e.target.checked)}
                  className="cursor-pointer"
                />
                Quyền Admin
              </label>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <InfoCard title="Active sessions" value={data.summary.activeSessionCount} note={`${data.summary.expiredSessionCount} expired · ${data.summary.revokedSessionCount} revoked`} icon={Laptop} />
        <InfoCard title="Trusted devices" value={data.summary.trustedDeviceCount} note="Dựa trên trustedAt" icon={ShieldCheck} />
        <InfoCard title="Paid revenue" value={formatCurrency(data.summary.totalPaidRevenue)} note={`${data.summary.paidPaymentCount} paid payments`} icon={CreditCard} />
        <InfoCard title="Failure/rejected events" value={data.summary.recentFailureEventCount} note="50 event gần nhất" icon={Database} />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <div className="mb-5 flex items-center justify-between">
            <h2 className="text-base font-medium text-[#202124]">Thiết bị & phiên đăng nhập</h2>
            <Laptop className="text-[#1a73e8]" size={20} />
          </div>
          {!data.sessions || data.sessions.length === 0 ? <EmptyState text="User chưa có session nào." /> : (
            <div className="space-y-3">
              {data.sessions.slice(0, 5).map(session => (
                <div key={session.id} className="flex items-center justify-between gap-4 rounded border border-[#e8eaed] bg-[#f8f9fa] p-3">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-[#202124]">{session.deviceName || 'Thiết bị chưa đặt tên'}</p>
                    <p className="mt-1 text-xs text-[#5f6368]">{session.platform || 'Không rõ nền tảng'} · Hoạt động {formatDateTime(session.lastSeenAt)}</p>
                  </div>
                  <div className="flex flex-wrap justify-end gap-2">
                    <span className={`admin-pill ${statusClass(session.status)}`}>{humanSessionStatus(session.status)}</span>
                    {session.trustedAt && <span className="admin-pill admin-pill-blue">Tin cậy</span>}
                  </div>
                </div>
              ))}
              {data.sessions.length > 5 && <p className="text-xs text-[#5f6368]">Còn {data.sessions.length - 5} phiên cũ hơn được ẩn để dễ đọc.</p>}
            </div>
          )}
        </div>

        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <div className="mb-5 flex items-center justify-between">
            <div>
              <h2 className="text-base font-medium text-[#202124]">Event phổ biến</h2>
              <p className="text-sm text-[#5f6368]">Từ hoạt động gần đây.</p>
            </div>
            <UserRound className="text-indigo-500" size={24} />
          </div>
          <div className="space-y-3">
            {!data.summary?.topEventTypes || data.summary.topEventTypes.length === 0 ? <EmptyState text="Chưa có event." /> : data.summary.topEventTypes.map(event => (
              <div key={event.eventType} className="flex items-center justify-between rounded border border-[#e8eaed] bg-[#f8f9fa] p-3">
                <span className="truncate text-sm font-bold text-slate-800">{event.eventType}</span>
                <span className="rounded-full bg-slate-100 px-3 py-1 text-xs font-bold text-slate-600">{event.count}</span>
              </div>
            ))}
          </div>
          {latestPayment && (
            <div className="mt-6 rounded border border-[#ceead6] bg-[#e6f4ea] p-4">
              <p className="text-xs font-bold uppercase tracking-wider text-emerald-600">Payment mới nhất</p>
              <p className="mt-2 font-bold text-slate-900">{formatCurrency(latestPayment.amount, latestPayment.currency)}</p>
              <p className="text-sm text-slate-500">{latestPayment.provider} · {latestPayment.status} · {formatDateTime(latestPayment.createdAt)}</p>
            </div>
          )}
        </div>
      </div>

      <DataTable title="Payments" icon={CreditCard} description="Lịch sử thanh toán của người dùng này.">
        {!data.payments || data.payments.length === 0 ? <EmptyState text="User chưa có payment nào." /> : (
          <div className="overflow-x-auto rounded border border-[#dadce0] bg-white">
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
              <tbody className="divide-y divide-slate-200">
                {data.payments.map(payment => (
                  <tr key={payment.id} className="text-sm odd:bg-white even:bg-slate-50/70 hover:bg-indigo-50/70">
                    <td>{formatDateTime(payment.paidAt ?? payment.createdAt)}</td>
                    <td className="font-medium text-[#202124]">{payment.provider.toUpperCase()}</td>
                    <td><span className={`admin-pill ${statusClass(payment.status)}`}>{humanPaymentStatus(payment.status)}</span></td>
                    <td className="font-medium text-[#137333]">{formatCurrency(payment.amount, payment.currency)}</td>
                    <td className="text-[#5f6368]">{payment.orderInfo}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </DataTable>

      <DataTable title="Recent events" icon={CalendarDays} description="Nhật ký hoạt động gần đây của tài khoản này.">
        {!data.events || data.events.length === 0 ? <EmptyState text="User chưa có AppEvent nào." /> : (
          <>
            <div className="overflow-x-auto rounded border border-[#dadce0] bg-white">
              <table className="admin-console-table min-w-[1100px]">
                <thead>
                  <tr>
                    <th>Thời gian</th>
                    <th>Hoạt động</th>
                    <th>Kết quả</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {pagedEvents.map(event => (
                    <tr key={event.id} className="align-top hover:bg-[#f8fafd]">
                      <td className="whitespace-nowrap text-[#3c4043]">{formatDateTime(event.createdAt)}</td>
                      <td className="font-medium text-[#202124]">{humanEventName(event.eventType)}</td>
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
              <div className="mt-4 flex flex-col gap-3 border-t border-[#dadce0] pt-4 sm:flex-row sm:items-center sm:justify-between">
                <p className="text-sm text-[#5f6368]">Trang {activeEventsPage} / {eventsTotalPages} · {data.events.length} event gần đây</p>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setEventsPage(current => Math.max(current - 1, 1))}
                    disabled={activeEventsPage <= 1 || loading}
                    className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#3c4043] hover:bg-[#f8f9fa] disabled:opacity-40 cursor-pointer"
                  >
                    <ChevronLeft size={16} />
                    Trước
                  </button>
                  <button
                    type="button"
                    onClick={() => setEventsPage(current => Math.min(current + 1, eventsTotalPages))}
                    disabled={activeEventsPage >= eventsTotalPages || loading}
                    className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#3c4043] hover:bg-[#f8f9fa] disabled:opacity-40 cursor-pointer"
                  >
                    Sau
                    <ChevronRight size={16} />
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
