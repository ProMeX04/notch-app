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
    const timer = setTimeout(() => {
      void initialLoad()
    }, 0)
    startPolling()
    return () => {
      clearTimeout(timer)
      stopPolling()
    }
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
    <div className="space-y-8">
      {/* Accessibility: announce polling updates to screen readers */}
      <span aria-live="polite" className="sr-only">
        {updating ? 'Đang cập nhật danh sách người dùng...' : data ? 'Đã cập nhật danh sách người dùng' : ''}
      </span>
      <div className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-center">
        <div className="min-w-0">
          <h1 className="text-3xl font-medium tracking-tight text-[#202124]">Người dùng</h1>
          <p className="mt-1 text-sm text-[#5f6368]">Xem tài khoản, gói đang dùng, lần hoạt động gần nhất và lịch sử thanh toán.</p>
        </div>
        <button
          type="button"
          onClick={() => void loadUsers()}
          disabled={loading}
          className="inline-flex w-full items-center justify-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] transition-colors disabled:opacity-60 sm:w-auto cursor-pointer"
        >
          <RefreshCw size={16} className={loading ? 'animate-spin' : ''} />
          Làm mới
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="md:col-span-3 lg:col-span-1 rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <label className="text-xs font-medium uppercase tracking-wider text-[#5f6368]">Tìm kiếm</label>
          <div className="mt-2 flex items-center gap-3 rounded border border-[#dadce0] bg-[#f8f9fa] px-4 py-3">
            <Search size={18} className="text-slate-400" />
            <input
              value={query}
              onChange={event => updateFilter(setQuery, event.target.value)}
              placeholder="Tên hoặc email"
              className="w-full bg-transparent outline-none text-sm text-slate-800 placeholder:text-slate-400"
            />
          </div>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <label className="text-xs font-medium uppercase tracking-wider text-[#5f6368]">Gói cước</label>
          <select
            value={plan}
            onChange={event => updateFilter(setPlan, event.target.value)}
            className="mt-2 w-full rounded border border-[#dadce0] bg-[#f8f9fa] px-4 py-3 text-sm font-medium outline-none"
          >
            <option value="all">Tất cả</option>
            <option value="pro">Pro</option>
            <option value="free">Free</option>
          </select>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <label className="text-xs font-medium uppercase tracking-wider text-[#5f6368]">Quyền & sắp xếp</label>
          <div className="mt-2 grid grid-cols-1 gap-2 sm:grid-cols-2">
            <select
              value={role}
              onChange={event => updateFilter(setRole, event.target.value)}
              className="rounded border border-[#dadce0] bg-[#f8f9fa] px-3 py-3 text-sm font-medium outline-none"
            >
              <option value="all">Mọi quyền</option>
              <option value="admin">Admin</option>
              <option value="user">User</option>
            </select>
            <select
              value={sort}
              onChange={event => updateFilter(setSort, event.target.value)}
              className="rounded border border-[#dadce0] bg-[#f8f9fa] px-3 py-3 text-sm font-medium outline-none"
            >
              <option value="newest">Mới nhất</option>
              <option value="oldest">Cũ nhất</option>
              <option value="updated">Vừa cập nhật</option>
              <option value="name">Theo tên</option>
              <option value="email">Theo email</option>
            </select>
          </div>
        </div>
      </div>

      {error && (
        <div className="rounded border border-rose-200 bg-rose-50 p-4 text-sm font-medium text-rose-700">
          {error}
        </div>
      )}

      <div className="overflow-hidden rounded border border-[#dadce0] bg-white shadow-sm">
        <div className="flex items-center justify-between gap-3 border-b border-[#dadce0] bg-[#f8f9fa] px-4 py-4 sm:px-6">
          <div className="flex items-center gap-3">
            <Users className="text-indigo-500" size={20} />
            <div>
              <p className="font-bold text-slate-900">{data?.pagination.total ?? 0} người dùng</p>
              <p className="text-xs text-slate-500">Trang {data?.pagination.page ?? page} / {data?.pagination.totalPages ?? 1}</p>
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
                <th className="text-right">Chi tiết</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-200">
              {data?.users.length === 0 && !loading ? (
                <tr>
                  <td colSpan={7} className="px-6 py-14 text-center text-sm text-slate-500">Không tìm thấy người dùng phù hợp.</td>
                </tr>
              ) : data?.users.map(user => (
                <tr key={user.id} className="odd:bg-white even:bg-slate-50/70 hover:bg-indigo-50/80 transition-colors group">
                  <td>
                    <div className="flex items-center gap-3">
                      <div className="flex h-9 w-9 items-center justify-center rounded-full bg-[#e8f0fe] text-sm font-semibold uppercase text-[#1967d2]">
                        {user.name?.[0] || user.email?.[0] || '?'}
                      </div>
                      <div className="min-w-0">
                        <p className="truncate font-medium text-[#202124]">{user.name || 'Chưa đặt tên'}</p>
                        <p className="truncate text-xs text-[#5f6368]">{user.email || 'Không có email'}</p>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div className="flex flex-wrap gap-2">
                      <span className={`admin-pill ${user.isPro ? 'admin-pill-blue' : 'admin-pill-gray'}`}>{user.isPro ? 'Pro' : 'Miễn phí'}</span>
                      <span className={`admin-pill ${user.isAdmin ? 'admin-pill-yellow' : 'admin-pill-gray'}`}>{user.isAdmin ? 'Quản trị' : 'Người dùng'}</span>
                    </div>
                  </td>
                  <td>
                    <p className="font-medium text-[#202124]">{formatDateTime(user.lastSeenAt)}</p>
                    <p className="text-xs text-[#5f6368]">Lần gần nhất mở ứng dụng hoặc website</p>
                  </td>
                  <td>
                    <p className="font-medium text-[#202124]">{user.activeSessionCount} đang hoạt động</p>
                    <p className="text-xs text-[#5f6368]">{user.totalSessionCount} tổng phiên · {user.trustedDeviceCount} thiết bị tin cậy</p>
                  </td>
                  <td>
                    <p className="font-medium text-[#137333]">{formatCurrency(user.totalPaidRevenue)}</p>
                    <p className="text-xs text-[#5f6368]">{user.paidPaymentCount} lần thanh toán · mới nhất {formatDate(user.latestPaymentAt)}</p>
                  </td>
                  <td>
                    <span>{formatDate(user.createdAt)}</span>
                  </td>
                  <td className="text-right">
                    <Link
                      to="/admin/users/$id"
                      params={{ id: user.id }}
                      className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] transition-colors"
                    >
                      Xem chi tiết
                      <ArrowRight size={16} />
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        <div className="flex flex-col gap-4 border-t border-[#dadce0] px-4 py-4 sm:px-6">
          <div className="text-center text-sm text-slate-500 sm:text-left">
            <p className="font-semibold">Trang {data?.pagination.page ?? page} / {data?.pagination.totalPages ?? 1}</p>
            <p>{data?.pagination.total ?? 0} người dùng · {data?.users.length ?? 0} hiển thị</p>
          </div>
          <div className="flex flex-wrap items-center justify-center gap-2 sm:justify-between">
            <button
              type="button"
              onClick={() => setPage(current => Math.max(current - 1, 1))}
              disabled={page <= 1 || loading}
              className="inline-flex items-center justify-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#3c4043] transition-colors hover:bg-[#f8f9fa] disabled:opacity-40"
            >
              <ChevronLeft size={16} />
              Trước
            </button>
            <div className="flex flex-wrap items-center justify-center gap-2">
              {paginationPages.map((pageItem, index) =>
                pageItem === 'ellipsis' ? (
                  <span key={`ellipsis-${index}`} className="px-2 text-sm font-medium text-slate-400">...</span>
                ) : (
                  <button
                    key={pageItem}
                    type="button"
                    onClick={() => setPage(pageItem)}
                    disabled={loading || pageItem === (data?.pagination.page ?? page)}
                    className={`inline-flex h-9 min-w-9 items-center justify-center rounded border px-3 text-sm font-semibold transition-colors disabled:opacity-100 ${
                      pageItem === (data?.pagination.page ?? page)
                        ? 'border-[#1a73e8] bg-[#e8f0fe] text-[#1967d2]'
                        : 'border-[#dadce0] bg-white text-[#3c4043] hover:bg-[#f8f9fa]'
                    }`}
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
              className="inline-flex items-center justify-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#3c4043] transition-colors hover:bg-[#f8f9fa] disabled:opacity-40"
            >
              Sau
              <ChevronRight size={16} />
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
