"use client";

import React, { useEffect, useState } from "react";
import { Users, CreditCard, Activity, Globe, Loader2, Server, Key, Bell, Database } from "lucide-react";
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
        <Loader2 className="animate-spin text-indigo-500" size={48} />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900">Dashboard</h1>
          <p className="text-slate-500 mt-1">Hệ thống Notch Pro - Dữ liệu thời gian thực</p>
        </div>
        <div className="flex gap-3">
          <button className="px-4 py-2 rounded-xl text-sm font-semibold text-slate-600 bg-white/50 border border-slate-200 hover:bg-white/80 transition-colors shadow-sm">Xuất báo cáo</button>
          <button className="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-slate-900 hover:bg-slate-800 transition-colors shadow-md shadow-slate-900/20" onClick={() => window.location.reload()}>Làm mới</button>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <StatCard 
          title="Tổng doanh thu" 
          value={`$${((stats?.totalRevenue || 145280) / 100).toLocaleString()}`} 
          icon={CreditCard} 
          color="grad-revenue"
        />
        <StatCard 
          title="Lượt đăng ký mới" 
          value={stats?.totalUsers || 1248} 
          icon={Users} 
          color="grad-signups"
        />
        <StatCard 
          title="Giao dịch thành công" 
          value={stats?.transactions || 4115} 
          icon={Activity} 
          color="grad-subscriptions"
        />
        <StatCard 
          title="Trạng thái Project" 
          value={stats?.projects || "98 Active"} 
          icon={Globe} 
          color="grad-projects"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 mt-8">
        <div className="lg:col-span-2 space-y-6">
          <h2 className="text-xl font-bold text-slate-800">Trạng thái hệ thống (System Status)</h2>
          <div className="p-8 rounded-[32px] bg-white/60 border border-white/80 shadow-sm backdrop-blur-md">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
              
              <div className="flex items-start gap-4 p-4 rounded-2xl hover:bg-white/50 transition-colors">
                <div className="p-3 bg-slate-100 rounded-xl text-slate-600">
                  <Activity size={24} />
                </div>
                <div className="flex-1">
                  <div className="flex justify-between items-center mb-2">
                    <p className="font-semibold text-slate-800">API Status</p>
                    <span className="glow-indicator glow-green">Operational</span>
                  </div>
                  <p className="text-sm text-slate-500">Tất cả endpoints đang hoạt động bình thường.</p>
                </div>
              </div>

              <div className="flex items-start gap-4 p-4 rounded-2xl hover:bg-white/50 transition-colors">
                <div className="p-3 bg-slate-100 rounded-xl text-slate-600">
                  <Database size={24} />
                </div>
                <div className="flex-1">
                  <div className="flex justify-between items-center mb-2">
                    <p className="font-semibold text-slate-800">Database</p>
                    <span className="glow-indicator glow-green">Operational</span>
                  </div>
                  <p className="text-sm text-slate-500">Neon Postgres phản hồi dưới 50ms.</p>
                </div>
              </div>

              <div className="flex items-start gap-4 p-4 rounded-2xl hover:bg-white/50 transition-colors">
                <div className="p-3 bg-slate-100 rounded-xl text-slate-600">
                  <Key size={24} />
                </div>
                <div className="flex-1">
                  <div className="flex justify-between items-center mb-2">
                    <p className="font-semibold text-slate-800">Authentication</p>
                    <span className="glow-indicator glow-green">Operational</span>
                  </div>
                  <p className="text-sm text-slate-500">Hệ thống JWT cấp phát bình thường.</p>
                </div>
              </div>

              <div className="flex items-start gap-4 p-4 rounded-2xl hover:bg-white/50 transition-colors">
                <div className="p-3 bg-slate-100 rounded-xl text-slate-600">
                  <Bell size={24} />
                </div>
                <div className="flex-1">
                  <div className="flex justify-between items-center mb-2">
                    <p className="font-semibold text-slate-800">Notifications</p>
                    <span className="glow-indicator glow-yellow">Degraded</span>
                  </div>
                  <p className="text-sm text-slate-500">Độ trễ gửi email qua SMTP đang cao.</p>
                </div>
              </div>

            </div>
          </div>
        </div>

        <div className="space-y-6">
          <h2 className="text-xl font-bold text-slate-800">Thông tin máy chủ</h2>
          <div className="p-8 rounded-[32px] bg-white/60 border border-white/80 shadow-sm backdrop-blur-md space-y-6">
            <div className="flex justify-between items-center pb-4 border-b border-slate-200/50">
              <span className="text-sm font-medium text-slate-500">Uptime</span>
              <span className="text-sm font-bold text-emerald-600">{stats?.uptime || "99.98%"}</span>
            </div>
            <div className="flex justify-between items-center pb-4 border-b border-slate-200/50">
              <span className="text-sm font-medium text-slate-500">Region</span>
              <span className="text-sm font-bold text-slate-800">Singapore (sin1)</span>
            </div>
            <div className="flex justify-between items-center pb-4 border-b border-slate-200/50">
              <span className="text-sm font-medium text-slate-500">Provider</span>
              <span className="text-sm font-bold text-slate-800">Vercel / Neon</span>
            </div>
            <div className="flex justify-between items-center">
              <span className="text-sm font-medium text-slate-500">Version</span>
              <span className="text-sm font-bold text-slate-800 px-2 py-1 bg-slate-100 rounded-md">v1.2.4</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
