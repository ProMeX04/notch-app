"use client";

import React, { useEffect, useState } from "react";
import { Users, CreditCard, Activity, Globe, ArrowUpRight, Clock, Shield, Loader2 } from "lucide-react";
import { StatCard } from "./components/StatCard";

export default function AdminDashboard() {
  const [stats, setStats] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/stats")
      .then(res => res.json())
      .then(data => {
        setStats(data);
        setLoading(false);
      })
      .catch(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div className="h-full w-full flex items-center justify-center">
        <Loader2 className="animate-spin text-[var(--accent)]" size={48} />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Hệ thống Notch Pro</h1>
          <p className="text-[var(--muted)] mt-1">Dữ liệu thực tế từ cơ sở dữ liệu hệ thống.</p>
        </div>
        <div className="flex gap-3">
          <button className="portal-button-ghost">Xuất báo cáo</button>
          <button className="portal-button" onClick={() => window.location.reload()}>Làm mới</button>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard 
          title="Tổng người dùng" 
          value={stats?.totalUsers || 0} 
          icon={Users} 
          color="bg-blue-600"
        />
        <StatCard 
          title="Người dùng Pro" 
          value={stats?.proUsers || 0} 
          icon={Shield} 
          color="bg-purple-600"
        />
        <StatCard 
          title="Giao dịch thành công" 
          value={stats?.transactions || 0} 
          icon={CreditCard} 
          color="bg-green-600"
        />
        <StatCard 
          title="Doanh thu tổng" 
          value={`$${((stats?.totalRevenue || 0) / 100).toLocaleString()}`} 
          icon={Globe} 
          color="bg-orange-600"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 space-y-6">
          <h2 className="text-xl font-bold">Trạng thái vận hành</h2>
          <div className="p-8 rounded-[32px] border border-[var(--border)] bg-[var(--surface-soft)]">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-8">
              <div>
                <p className="text-xs text-[var(--muted)] uppercase font-bold mb-1">Database</p>
                <p className="font-bold text-green-600">Connected</p>
              </div>
              <div>
                <p className="text-xs text-[var(--muted)] uppercase font-bold mb-1">API Status</p>
                <p className="font-bold text-green-600">Operational</p>
              </div>
              <div>
                <p className="text-xs text-[var(--muted)] uppercase font-bold mb-1">Sync Service</p>
                <p className="font-bold text-blue-600">Active</p>
              </div>
            </div>
          </div>
        </div>

        <div className="space-y-6">
          <h2 className="text-xl font-bold">Thông tin máy chủ</h2>
          <div className="p-8 rounded-[32px] border border-[var(--border)] space-y-4">
            <div className="flex justify-between items-center">
              <span className="text-sm font-medium">Uptime</span>
              <span className="text-sm font-bold text-green-600">{stats?.uptime}</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm font-medium">Region</span>
              <span className="text-sm font-bold">Singapore</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm font-medium">Provider</span>
              <span className="text-sm font-bold">Vercel / Neon</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
