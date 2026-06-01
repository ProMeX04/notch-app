import { Link } from '@tanstack/react-router'
import {
  Bot,
  LayoutDashboard,
  Settings,
  ShieldCheck,
  Users,
} from 'lucide-react'

const navItems = [
  { label: 'Tổng quan', icon: LayoutDashboard, to: '/admin' as const, exact: true },
  { label: 'Người dùng', icon: Users, to: '/admin/users' as const, exact: false },
  { label: 'Quyền truy cập', icon: ShieldCheck, to: '/admin/capabilities' as const, exact: false },
  { label: 'Gemini Live', icon: Bot, to: '/admin/gemini-live' as const, exact: false },
  { label: 'Cài đặt', icon: Settings, to: '/admin/settings' as const, exact: false },
]

function isActive(exact: boolean, to: string, pathname: string) {
  const cleanPath = pathname.endsWith('/') && pathname.length > 1 ? pathname.slice(0, -1) : pathname
  const cleanTo = to.endsWith('/') && to.length > 1 ? to.slice(0, -1) : to
  if (exact) return cleanPath === cleanTo
  return cleanPath.startsWith(cleanTo)
}

interface AdminSidebarProps {
  pathname: string
}

export function AdminSidebar({ pathname }: AdminSidebarProps) {
  return (
    <aside className="relative z-40 w-full border-b border-[#dadce0] bg-white lg:fixed lg:bottom-0 lg:left-0 lg:top-16 lg:w-64 lg:border-b-0 lg:border-r">
      <div className="border-b border-[#e8eaed] px-4 py-3 lg:px-5 lg:py-4">
        <p className="text-xs font-semibold uppercase tracking-[0.12em] text-[#5f6368]">Console</p>
        <p className="mt-1 text-sm text-[#3c4043]">Không gian quản trị</p>
      </div>

      <nav className="flex flex-wrap gap-2 px-3 py-3 lg:block">
        {navItems.map((item) => {
          const active = isActive(item.exact, item.to, pathname)
          return (
            <Link
              key={item.to}
              to={item.to}
              className={`flex h-10 w-full items-center gap-3 rounded-full px-4 text-sm font-medium transition-colors sm:w-auto lg:mb-1 lg:w-full lg:rounded-r-full ${
                active
                  ? 'bg-[#e8f0fe] text-[#1967d2]'
                  : 'text-[#3c4043] hover:bg-[#f1f3f4] hover:text-[#202124]'
              }`}
            >
              <item.icon size={18} className={active ? 'text-[#1a73e8]' : 'text-[#5f6368]'} />
              <span>{item.label}</span>
            </Link>
          )
        })}
      </nav>

      {/* Return to portal button */}
      <div className="absolute bottom-4 left-4 hidden lg:block">
        <Link
          to="/"
          className="flex h-9 w-9 items-center justify-center rounded-full bg-[#202124] text-sm font-black text-white hover:bg-black transition-colors shadow-sm"
          aria-label="Quay lại Portal"
        >
          N
        </Link>
      </div>
    </aside>
  )
}