"use client";

import React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  Bot,
  LayoutDashboard,
  Users,
  Settings,
  ShieldCheck,
} from "lucide-react";

const navItems = [
  { label: "Tổng quan", icon: LayoutDashboard, href: "/admin" },
  { label: "Người dùng", icon: Users, href: "/admin/users" },
  { label: "Quyền truy cập", icon: ShieldCheck, href: "/admin/capabilities" },
  { label: "Gemini Live", icon: Bot, href: "/admin/gemini-live" },
  { label: "Cài đặt", icon: Settings, href: "/admin/settings" },
];

export function AdminSidebar() {
  const pathname = usePathname();

  return (
    <aside className="relative z-40 w-full border-b border-slate-200 bg-black/95 lg:fixed lg:bottom-0 lg:left-0 lg:top-16 lg:w-64 lg:border-b-0 lg:border-r lg:border-slate-200">
      <div className="border-b border-slate-200 px-4 py-3 lg:px-5 lg:py-4">
        <p className="text-xs font-semibold uppercase tracking-[0.12em] text-slate-500">Console</p>
        <p className="mt-1 text-sm text-slate-200">Không gian quản trị</p>
      </div>

      <nav className="flex flex-wrap gap-2 px-3 py-3 lg:block">
        {navItems.map((item) => {
          const isActive = item.href === "/admin" ? pathname === item.href : pathname.startsWith(item.href);
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`flex h-10 w-full items-center gap-3 rounded-full px-4 text-sm font-medium transition-colors sm:w-auto lg:mb-1 lg:w-full lg:rounded-r-full ${
                isActive
                  ? "bg-sky-500/10 text-sky-400"
                  : "text-slate-400 hover:bg-white/5 hover:text-white"
              }`}
            >
              <item.icon size={18} className={isActive ? "text-sky-400" : "text-slate-400"} />
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>
    </aside>
  );
}
