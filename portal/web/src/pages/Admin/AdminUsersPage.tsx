import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link } from '@tanstack/react-router'
import { ArrowRight, ChevronLeft, ChevronRight, Loader2, RefreshCw, Search, Users } from 'lucide-react'

import { apiClient } from '@/api/client'

type AdminUserRow = {
  id: string
  name: string | null
  email: string | null
  isPro: boolean
  isAdmin: boolean
  createdAt: string
  updatedAt: string
  lastSeenAt: string | null
  latestEventAt: string | null
  latestPaymentAt: string | null
  activeSessionCount: number
  totalSessionCount: number
  trustedDeviceCount: number
  paidPaymentCount: number
  totalPaidRevenue: number
}

type UsersResponse = {
  users: AdminUserRow[]
  pagination: {
    page: number
    limit: number
    total: number
    totalPages: number
  }
}

function formatDate(value: string | null) {
  if (!value) return 'Chưa có'
  return new Date(value).toLocaleDateString('vi-VN')
}

function formatDateTime(value: string | null) {
  if (!value) return 'Chưa có'
  return new Date(value).toLocaleString('vi-VN', { dateStyle: 'short', timeStyle: 'short' })
}

function formatCurrency(value: number) {
  return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND', maximumFractionDigits: 0 }).format(value)
}

export function AdminUsersPage() {
  const [data, setData] = useState<UsersResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [updating, setUpdating] = useState(false)
  const [query, setQuery] = useState('')
  const [plan, setPlan] = useState('all')
  const [role, setRole] = useState('all')
  const [sort, setSort] = useState('newest')
  const [page, setPage] = useState(1)
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null)

  const params = useMemo(() => {
    const search = new URLSearchParams()
    if (query.trim()) search.set('q', query.trim())
    if (plan !== 'all') search.set('plan', plan)
    if (role !== 'all') search.set('role', role)
    if (sort !== 'newest') search.set('sort', sort)
    search.set('page', String(page))
    search.set('limit', '25')
    return search
  }, [query, plan, role, sort, page])

  const loadUsers = useCallback(async () => {
    setError(null)
    setUpdating(true)
    try {
      const response = await apiClient.get<UsersResponse>(`/api/admin/users?${params.toString()}`)
      setData(response.data)
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Không tải được danh sách người dùng')
    } finally {
      setLoading(false)
      setUpdating(false)
    }
  }, [params])

  const initialLoad = useCallback(async () => {
    setLoading(true)
    await loadUsers()
  }, [loadUsers])

  const startPolling = useCallback(() => {
    if (pollRef.current) return
    pollRef.current = setInterval(() => {
      void loadUsers()
    }, 5000)
  }, [loadUsers])

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

  const updateFilter = (setter: (value: string) => void, value: string) => {
    setter(value)
    setPage(1)
  }

  const paginationPages = useMemo<(number | 'ellipsis')[]>(() => {
    const totalPages = data?.pagination.totalPages ?? 1
    const currentPage = data?.pagination.page ?? page
    const pages = new Set([1, totalPages])

    for (let candidate = currentPage - 1; candidate <= currentPage + 1; candidate += 1) {
      if (candidate > 1 && candidate < totalPages) pages.add(candidate)
    }

    return Array.from(pages)
      .sort((a, b) => a - b)
      .flatMap((pageNumber, index, sortedPages): (number | 'ellipsis')[] => {
        if (index === 0) return [pageNumber]
        return pageNumber - sortedPages[index - 1] > 1 ? ['ellipsis', pageNumber] : [pageNumber]
      })
  }, [data?.pagination.page, data?.pagination.totalPages, page])

  return (
    <div className="space-y-6">
      <span aria-live="polite" className="sr-only">
        {updating ? 'Đang cập nhật danh sách người dùng...' : data ? 'Đã cập nhật danh sách người dùng' : ''}
      </span>
      <div style={{ display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: '16px', borderBottom: '1px solid var(--border)', paddingBottom: '16px' }}>
        <div>
          <h1 style={{ fontSize: '1.75rem', fontWeight: 700, margin: 0 }}>Quản lý người dùng</h1>
          <p style={{ color: 'var(--muted)', fontSize: '0.9rem', margin: '4px 0 0 0' }}>Xem tài khoản, gói đang dùng, lần hoạt động gần nhất và lịch sử thanh toán.</p>
        </div>
        <button
          type="button"
          onClick={() => void loadUsers()}
          disabled={loading}
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

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: '16px' }}>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <label style={{ fontSize: '0.75rem', fontWeight: 600, textTransform: 'uppercase', color: 'var(--muted)' }}>Tìm kiếm</label>
          <div style={{ marginTop: '8px', display: 'flex', alignItems: 'center', gap: '8px', border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 12px', borderRadius: '12px' }}>
            <Search size={16} style={{ color: 'var(--muted)' }} />
            <input
              value={query}
              onChange={event => updateFilter(setQuery, event.target.value)}
              placeholder="Tên hoặc email"
              style={{ width: '100%', background: 'transparent', border: 'none', outline: 'none', color: 'var(--foreground)', fontSize: '0.9rem' }}
            />
          </div>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <label style={{ fontSize: '0.75rem', fontWeight: 600, textTransform: 'uppercase', color: 'var(--muted)' }}>Gói cước</label>
          <select 
            value={plan} 
            onChange={event => updateFilter(setPlan, event.target.value)} 
            style={{ marginTop: '8px', width: '100%', border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 12px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
          >
            <option value="all" style={{ background: '#18181b' }}>Tất cả</option>
            <option value="pro" style={{ background: '#18181b' }}>Pro</option>
            <option value="free" style={{ background: '#18181b' }}>Free</option>
          </select>
        </div>
        <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '16px', padding: '16px' }}>
          <label style={{ fontSize: '0.75rem', fontWeight: 600, textTransform: 'uppercase', color: 'var(--muted)' }}>Quyền & sắp xếp</label>
          <div style={{ marginTop: '8px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' }}>
            <select 
              value={role} 
              onChange={event => updateFilter(setRole, event.target.value)} 
              style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 8px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
            >
              <option value="all" style={{ background: '#18181b' }}>Mọi quyền</option>
              <option value="admin" style={{ background: '#18181b' }}>Admin</option>
              <option value="user" style={{ background: '#18181b' }}>User</option>
            </select>
            <select 
              value={sort} 
              onChange={event => updateFilter(setSort, event.target.value)} 
              style={{ border: '1px solid var(--border)', background: 'rgba(0,0,0,0.2)', padding: '10px 8px', borderRadius: '12px', color: 'var(--foreground)', fontSize: '0.9rem', outline: 'none' }}
            >
              <option value="newest" style={{ background: '#18181b' }}>Mới nhất</option>
              <option value="oldest" style={{ background: '#18181b' }}>Cũ nhất</option>
              <option value="updated" style={{ background: '#18181b' }}>Vừa cập nhật</option>
              <option value="name" style={{ background: '#18181b' }}>Theo tên</option>
              <option value="email" style={{ background: '#18181b' }}>Theo email</option>
            </select>
          </div>
        </div>
      </div>

      {error && (
        <div style={{ background: 'rgba(239, 68, 68, 0.1)', border: '1px solid rgba(239, 68, 68, 0.2)', color: '#ef4444', padding: '12px 16px', borderRadius: '12px', fontSize: '0.9rem' }}>
          {error}
        </div>
      )}

      <div style={{ background: 'var(--card)', border: '1px solid var(--border)', borderRadius: '24px', overflow: 'hidden' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '16px 24px', borderBottom: '1px solid var(--border)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
            <Users className="text-indigo-500" size={20} />
            <div>
              <p style={{ margin: 0, fontWeight: 700, color: 'var(--foreground)' }}>{data?.pagination.total ?? 0} người dùng</p>
              <p style={{ margin: '2px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>Trang {data?.pagination.page ?? page} / {data?.pagination.totalPages ?? 1}</p>
            </div>
          </div>
          {loading && <Loader2 className="animate-spin text-indigo-500" size={20} />}
        </div>

        <div className="overflow-x-auto">
          <table className="admin-console-table min-w-[1040px]">
            <thead>
              <tr>
                <th>Người dùng</th>
                <th>Gói & quyền</th>
                <th>Hoạt động gần nhất</th>
                <th>Thiết bị</th>
                <th>Thanh toán</th>
                <th>Ngày tham gia</th>
                <th style={{ textAlign: 'right' }}>Chi tiết</th>
              </tr>
            </thead>
            <tbody>
              {data?.users.length === 0 && !loading ? (
                <tr>
                  <td colSpan={7} style={{ textAlign: 'center', padding: '40px', color: 'var(--muted)' }}>Không tìm thấy người dùng phù hợp.</td>
                </tr>
              ) : data?.users.map(user => (
                <tr key={user.id}>
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                      <div style={{ display: 'flex', height: '36px', width: '36px', alignItems: 'center', justifyContent: 'center', borderRadius: '50%', background: 'rgba(56, 189, 248, 0.1)', fontSize: '0.9rem', fontWeight: 600, color: 'var(--accent)', textTransform: 'uppercase' }}>
                        {user.name?.[0] || user.email?.[0] || '?'}
                      </div>
                      <div style={{ minWidth: 0 }}>
                        <p className="truncate" style={{ margin: 0, fontWeight: 600, color: 'var(--foreground)' }}>{user.name || 'Chưa đặt tên'}</p>
                        <p className="truncate" style={{ margin: '2px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{user.email || 'Không có email'}</p>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
                      <span className={`admin-pill ${user.isPro ? 'admin-pill-blue' : 'admin-pill-gray'}`}>{user.isPro ? 'Pro' : 'Miễn phí'}</span>
                      <span className={`admin-pill ${user.isAdmin ? 'admin-pill-yellow' : 'admin-pill-gray'}`}>{user.isAdmin ? 'Quản trị' : 'Người dùng'}</span>
                    </div>
                  </td>
                  <td>
                    <p style={{ margin: 0, fontWeight: 600 }}>{formatDateTime(user.lastSeenAt)}</p>
                    <p style={{ margin: '2px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>Lần gần nhất mở ứng dụng hoặc website</p>
                  </td>
                  <td>
                    <p style={{ margin: 0, fontWeight: 600 }}>{user.activeSessionCount} đang hoạt động</p>
                    <p style={{ margin: '2px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{user.totalSessionCount} tổng phiên · {user.trustedDeviceCount} thiết bị tin cậy</p>
                  </td>
                  <td>
                    <p style={{ margin: 0, fontWeight: 600, color: '#10b981' }}>{formatCurrency(user.totalPaidRevenue)}</p>
                    <p style={{ margin: '2px 0 0 0', fontSize: '0.75rem', color: 'var(--muted)' }}>{user.paidPaymentCount} lần thanh toán · mới nhất {formatDate(user.latestPaymentAt)}</p>
                  </td>
                  <td>
                    <span>{formatDate(user.createdAt)}</span>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    <Link 
                      to="/admin/users/$id" 
                      params={{ id: user.id }}
                      className="portal-button-ghost" 
                      style={{ 
                        display: 'inline-flex', 
                        alignItems: 'center', 
                        gap: '6px',
                        padding: '8px 12px',
                        borderRadius: '10px',
                        border: '1px solid var(--border)',
                        fontSize: '0.85rem',
                        fontWeight: 600,
                        cursor: 'pointer'
                      }}
                    >
                      Chi tiết
                      <ArrowRight size={14} />
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '16px', borderTop: '1px solid var(--border)', padding: '16px 24px' }}>
          <div style={{ textAlign: 'center', fontSize: '0.85rem', color: 'var(--muted)' }}>
            <p style={{ margin: 0, fontWeight: 600 }}>Trang {data?.pagination.page ?? page} / {data?.pagination.totalPages ?? 1}</p>
            <p style={{ margin: '2px 0 0 0' }}>{data?.pagination.total ?? 0} người dùng · {data?.users.length ?? 0} hiển thị</p>
          </div>
          <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'center', gap: '8px' }}>
            <button
              type="button"
              onClick={() => setPage(current => Math.max(current - 1, 1))}
              disabled={page <= 1 || loading}
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
            <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
              {paginationPages.map((pageItem, index) =>
                pageItem === 'ellipsis' ? (
                  <span key={`ellipsis-${index}`} style={{ padding: '0 4px', fontSize: '0.85rem', color: 'var(--muted)' }}>...</span>
                ) : (
                  <button
                    key={pageItem}
                    type="button"
                    onClick={() => setPage(pageItem)}
                    disabled={loading || pageItem === (data?.pagination.page ?? page)}
                    style={{
                      display: 'inline-flex',
                      height: '32px',
                      minWidth: '32px',
                      alignItems: 'center',
                      justifyContent: 'center',
                      borderRadius: '8px',
                      border: '1px solid var(--border)',
                      fontSize: '0.85rem',
                      fontWeight: 600,
                      cursor: 'pointer',
                      background: pageItem === (data?.pagination.page ?? page) ? 'rgba(56, 189, 248, 0.15)' : 'rgba(255,255,255,0.02)',
                      color: pageItem === (data?.pagination.page ?? page) ? '#38bdf8' : 'var(--foreground)'
                    }}
                  >
                    {pageItem}
                  </button>
                )
              )}
            </div>
            <button
              type="button"
              onClick={() => setPage(current => Math.min(current + 1, data?.pagination.totalPages ?? current))}
              disabled={loading || page >= (data?.pagination.totalPages ?? 1)}
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
      </div>
    </div>
  )
}
