"use client";

import React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { 
  LayoutDashboard, 
  Users, 
  BarChart3, 
  Settings, 
  ShieldCheck,
  CreditCard,
  LogOut,
  ChevronRight
} from "lucide-react";
import { PortalLogo } from "@/components/portal/PortalLogo";

const navItems = [
  { label: "Dashboard", icon: LayoutDashboard, href: "/admin" },
  { label: "Người dùng", icon: Users, href: "/admin/users" },
  { label: "Quyền hạn (Pro/Free)", icon: ShieldCheck, href: "/admin/capabilities" },
  { label: "Cài đặt", icon: Settings, href: "/admin/settings" },
];

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="fixed left-0 top-0 h-full w-72 bg-white border-r border-[var(--border)] flex flex-col z-50">
      <div className="p-8">
        <PortalLogo />
        <div className="mt-2 flex items-center gap-2">
          <span className="px-2 py-0.5 rounded-full bg-[var(--accent-soft)] text-[var(--accent)] text-[10px] font-bold uppercase tracking-wider">
            Admin Panel
          </span>
        </div>
      </div>

      <nav className="flex-1 px-4 space-y-1">
        {navItems.map((item) => {
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`
                flex items-center justify-between px-4 py-3 rounded-2xl transition-all duration-200 group
                ${isActive 
                  ? "bg-[var(--accent)] text-white shadow-lg" 
                  : "text-[var(--muted-strong)] hover:bg-[var(--surface-soft)]"}
              `}
            >
              <div className="flex items-center gap-3">
                <item.icon size={20} className={isActive ? "text-white" : "text-[var(--muted)] group-hover:text-[var(--accent)] transition-colors"} />
                <span className="font-semibold text-[0.95rem]">{item.label}</span>
              </div>
              {isActive && <ChevronRight size={16} />}
            </Link>
          );
        })}
      </nav>

      <div className="p-6 border-t border-[var(--border)]">
        <button className="w-full flex items-center gap-3 px-4 py-3 rounded-2xl text-[var(--red)] hover:bg-[var(--red-soft)] transition-colors font-semibold">
          <LogOut size={20} />
          <span>Đăng xuất</span>
        </button>
        
        <div className="mt-6 p-4 rounded-2xl bg-[var(--surface-soft)] border border-[var(--border)]">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500 to-purple-600 flex items-center justify-center text-white font-bold">
              A
            </div>
            <div>
              <p className="text-sm font-bold text-[var(--foreground)]">Admin Pro</p>
              <p className="text-[10px] text-[var(--muted)]">admin@notch.pro</p>
            </div>
          </div>
        </div>
      </div>
    </aside>
  );
}
