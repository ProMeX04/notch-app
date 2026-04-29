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
  { label: "Quyền hạn", icon: ShieldCheck, href: "/admin/capabilities" },
  { label: "Cài đặt", icon: Settings, href: "/admin/settings" },
];

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="fixed left-0 top-0 h-full w-64 glass-panel flex flex-col z-50 border-r-0 border-r-transparent border-white/20">
      <div className="p-8 pb-4">
        <PortalLogo />
        <div className="mt-4 flex items-center gap-2">
          <span className="px-3 py-1 rounded-full bg-indigo-500/10 text-indigo-600 border border-indigo-500/20 text-[10px] font-bold uppercase tracking-wider">
            Admin Panel
          </span>
        </div>
      </div>

      <nav className="flex-1 px-4 py-4 space-y-2">
        {navItems.map((item) => {
          const isActive = pathname === item.href;
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`
                flex items-center justify-between px-4 py-3 rounded-2xl transition-all duration-300 group
                ${isActive 
                  ? "sidebar-item-active" 
                  : "text-slate-600 hover:bg-white/50 hover:text-slate-900"}
              `}
            >
              <div className="flex items-center gap-3">
                <item.icon size={20} className={isActive ? "text-white" : "text-slate-500 group-hover:text-indigo-500 transition-colors"} />
                <span className="font-semibold text-sm">{item.label}</span>
              </div>
              {isActive && <ChevronRight size={16} className="opacity-80" />}
            </Link>
          );
        })}
      </nav>

      <div className="p-4 border-t border-white/20">
        <div className="mb-4 p-4 rounded-2xl bg-white/40 backdrop-blur-sm border border-white/50 transition-all hover:bg-white/60 cursor-default">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center text-white font-bold shadow-inner">
              A
            </div>
            <div className="overflow-hidden">
              <p className="text-sm font-bold text-slate-800 truncate">Admin Pro</p>
              <p className="text-[11px] text-slate-500 truncate">admin@notch.pro</p>
            </div>
          </div>
        </div>

        <button className="w-full flex items-center gap-3 px-4 py-3 rounded-2xl text-red-500 hover:bg-red-50 hover:text-red-600 transition-colors font-semibold">
          <LogOut size={20} />
          <span className="text-sm">Đăng xuất</span>
        </button>
      </div>
    </aside>
  );
}
