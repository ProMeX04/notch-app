import { useEffect } from 'react'
import { Outlet, useLocation, useNavigate } from '@tanstack/react-router'

import { AdminSidebar } from './AdminSidebar'
import { usePortalAuth } from '@/auth/usePortalAuth'

export function AdminLayout() {
  const location = useLocation()
  const navigate = useNavigate()
  const { status, user } = usePortalAuth()

  useEffect(() => {
    if (status === 'guest' || (status === 'authenticated' && (!user || !user.is_admin))) {
      void navigate({ to: '/' })
    }
  }, [status, user, navigate])

  useEffect(() => {
    const html = document.documentElement
    const body = document.body
    const origColorScheme = html.style.colorScheme

    html.style.colorScheme = 'light'
    body.classList.add('admin-body-bg')

    return () => {
      html.style.colorScheme = origColorScheme
      body.classList.remove('admin-body-bg')
    }
  }, [])

  if (status === 'booting') {
    return (
      <div className="portal-admin-shell portal-admin-shell--loading">
        <div className="portal-admin-loading-inner">
          <div className="portal-admin-loading-logo">N</div>
          <p className="portal-admin-loading-text">Checking admin session…</p>
        </div>
      </div>
    )
  }

  if (status === 'guest' || !user || !user.is_admin) {
    return (
      <div className="portal-admin-shell portal-admin-shell--loading">
        <div className="portal-admin-loading-inner">
          <p className="portal-admin-loading-text" style={{ color: 'var(--muted)', fontSize: '1rem' }}>
            Sign in as an admin to continue.
          </p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#f8fafd] text-[#202124]">
      {/* Top header bar */}
      <div className="fixed left-0 right-0 top-0 z-50 flex h-16 items-center border-b border-[#dadce0] bg-white px-4 shadow-[0_1px_2px_rgba(60,64,67,0.12)] sm:px-6">
        <div className="flex min-w-0 items-center gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg border border-[#dadce0] bg-white text-sm font-black text-[#1a73e8]">N</div>
          <div className="min-w-0">
            <p className="truncate text-sm font-semibold text-[#3c4043]">Notch Admin Console</p>
            <p className="truncate text-xs text-[#5f6368]">Quản lý người dùng và doanh thu</p>
          </div>
        </div>
      </div>

      {/* Body: sidebar + content */}
      <div className="flex flex-col pt-16 lg:flex-row">
        <AdminSidebar pathname={location.pathname} />
        <main className="min-h-[calc(100vh-4rem)] min-w-0 flex-1 lg:pl-64">
          <div className="mx-auto max-w-[1440px] px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-8">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  )
}