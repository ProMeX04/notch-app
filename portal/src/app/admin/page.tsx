"use client";

import React, { useEffect, useMemo, useState } from "react";
import { Activity, AlertTriangle, BarChart3, ChevronLeft, ChevronRight, CreditCard, Loader2, RefreshCw, ShieldCheck, TrendingUp, Users } from "lucide-react";
import { StatCard } from "./components/StatCard";
import { apiClient } from "@/lib/api-client";
import { useQuery } from "@tanstack/react-query";

type DailyMetric = {
  date: string;
  users: number;
  paidTransactions: number;
  revenue: number;
  events: number;
};

type RecentEvent = {
  id: string;
  createdAt: string;
  eventType: string;
  outcome: string;
  source: string;
  requestPath: string | null;
  requestMethod: string | null;
  statusCode: number | null;
  actorUserId: string | null;
  actorUser: {
    name: string | null;
    email: string | null;
  } | null;
};

type AdminStats = {
  overview: {
    totalUsers: number;
    proUsers: number;
    freeUsers: number;
    adminUsers: number;
    newUsers7d: number;
    newUsers30d: number;
    activeSessions: number;
    paidTransactions: number;
    failedTransactions: number;
    pendingTransactions: number;
    totalRevenue: number;
    recentRejectedEvents: number;
    recentFailedEvents: number;
  };
  trends: DailyMetric[];
  recentEvents: RecentEvent[];
  systemHealth: string;
  generatedAt: string;
};

const recentEventsPageSize = 5;

function formatCurrency(value: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND", maximumFractionDigits: 0 }).format(value);
}

function formatDateTime(value: string | null) {
  if (!value) return "Chưa có";
  return new Date(value).toLocaleString("vi-VN", { dateStyle: "short", timeStyle: "short" });
}

function humanEventName(eventType: string) {
  if (eventType.includes("focus.sync")) return "Đồng bộ Focus";
  if (eventType.includes("focus.leaderboard_profile")) return "Cập nhật xếp hạng Focus";
  if (eventType.includes("login")) return "Đăng nhập";
  if (eventType.includes("signup")) return "Đăng ký tài khoản";
  if (eventType.includes("logout")) return "Đăng xuất";
  if (eventType.includes("refresh")) return "Gia hạn phiên đăng nhập";
  if (eventType.includes("payment")) return "Thanh toán";
  if (eventType.includes("session_token")) return "Lấy quyền dùng Gemini Live";
  if (eventType.includes("oauth")) return "Kết nối ứng dụng";
  return "Hoạt động hệ thống";
}

function humanOutcome(outcome: string) {
  if (outcome === "success") return "Thành công";
  if (outcome === "rejected") return "Bị từ chối";
  return "Thất bại";
}

function humanOutcomeClass(outcome: string) {
  if (outcome === "success") return "bg-[#e6f4ea] text-[#137333] border-[#ceead6]";
  if (outcome === "rejected") return "bg-[#fef7e0] text-[#b06000] border-[#feefc3]";
  return "bg-[#fce8e6] text-[#c5221f] border-[#fad2cf]";
}

function humanSource(source: string) {
  if (source === "web") return "Website";
  if (source === "desktop") return "Ứng dụng Mac";
  if (source === "oauth") return "Đăng nhập/kết nối";
  if (source === "payment_webhook") return "Cổng thanh toán";
  return "Hệ thống";
}

function eventActor(event: RecentEvent) {
  return event.actorUser?.email || event.actorUser?.name || event.actorUserId || "Ẩn danh / hệ thống";
}

function eventEndpoint(event: RecentEvent) {
  if (!event.requestPath) return "Không rõ API";
  return [event.requestMethod, event.requestPath].filter(Boolean).join(" ");
}

function MiniBarChart({ data, field, color }: { data: DailyMetric[]; field: keyof DailyMetric; color: string }) {
  const max = Math.max(...data.map((item) => Number(item[field]) || 0), 1);

  return (
    <div className="flex h-40 items-end gap-1 rounded bg-white p-4 border border-[#dadce0]">
      {data.map((item) => {
        const value = Number(item[field]) || 0;
        return (
          <div key={item.date} className="flex flex-1 flex-col items-center gap-1">
            <div className="text-[10px] font-medium text-[#5f6368]">{value ? value.toLocaleString("vi-VN") : ""}</div>
            <div className="w-full bg-[#f1f3f4] overflow-hidden flex items-end" style={{ height: "112px" }}>
              <div
                className={`w-full rounded-t-sm ${color}`}
                style={{ height: `${Math.max((value / max) * 100, value > 0 ? 8 : 0)}%` }}
              />
            </div>
            <div className="text-[10px] text-[#5f6368]">{new Date(item.date).getDate()}</div>
          </div>
        );
      })}
    </div>
  );
}
export default function AdminDashboard() {
  const { data: stats, isLoading: loading, error: queryError, isFetching: updating, refetch: loadStats } = useQuery<AdminStats>({
    queryKey: ["adminStats"],
    queryFn: () => apiClient.get("/api/admin/stats").then((res) => res.data),
    refetchInterval: 1000,
  });

  const error = queryError ? (queryError instanceof Error ? queryError.message : "Không tải được thống kê") : null;
  const [recentEventsPage, setRecentEventsPage] = useState(1);

  const planPercent = useMemo(() => {
    if (!stats?.overview.totalUsers) return 0;
    return Math.round((stats.overview.proUsers / stats.overview.totalUsers) * 100);
  }, [stats]);

  const recentEventsTotalPages = Math.max(Math.ceil((stats?.recentEvents.length ?? 0) / recentEventsPageSize), 1);
  const pagedRecentEvents = useMemo(() => {
    if (!stats) return [];
    const start = (recentEventsPage - 1) * recentEventsPageSize;
    return stats.recentEvents.slice(start, start + recentEventsPageSize);
  }, [recentEventsPage, stats]);

  useEffect(() => {
    if (recentEventsPage > recentEventsTotalPages) {
      const timer = setTimeout(() => setRecentEventsPage(recentEventsTotalPages), 0);
      return () => clearTimeout(timer);
    }
  }, [recentEventsPage, recentEventsTotalPages]);

  if (loading && !stats) {
    return (
      <div className="h-full w-full flex items-center justify-center bg-[#f8f9fa]">
        <Loader2 className="animate-spin text-[#1a73e8]" size={48} />
      </div>
    );
  }

  if (error && !stats) {
    return (
      <div className="rounded bg-white border border-[#dadce0] p-8 text-center shadow-sm">
        <AlertTriangle className="mx-auto mb-4 text-[#ea4335]" size={40} />
        <h1 className="text-xl font-medium text-[#202124]">Không tải được dashboard</h1>
        <p className="mt-2 text-sm text-[#5f6368]">{error}</p>
        <button onClick={() => { void loadStats(); }} className="mt-4 px-4 py-2 rounded bg-[#1a73e8] text-white text-sm font-medium hover:bg-[#1557b0] transition-colors">Thử lại</button>
      </div>
    );
  }

  if (!stats) return null;

  return (
    <div className="space-y-6 bg-[#f8f9fa] font-sans text-[#202124]">
      {/* Accessibility: announce polling updates to screen readers */}
      <span aria-live="polite" className="sr-only">
        {updating ? "Đang cập nhật thống kê..." : stats ? "Đã cập nhật thống kê" : ""}
      </span>
      <div className="flex items-center justify-between gap-4 border-b border-[#dadce0] pb-4">
        <div>
          <h1 className="text-2xl font-normal tracking-tight text-[#202124]">Tổng quan</h1>
          <p className="mt-1 text-sm text-[#5f6368]">Theo dõi người dùng, doanh thu, thiết bị đang dùng và cảnh báo cần chú ý.</p>
          <p className="mt-1 text-xs text-[#5f6368]">Cập nhật: {formatDateTime(stats.generatedAt)}</p>
        </div>
        <button
          className="inline-flex items-center gap-2 px-4 py-2 rounded text-sm font-medium text-[#1a73e8] border border-[#dadce0] bg-white hover:bg-[#f8f9fa] transition-colors disabled:opacity-60"
          onClick={() => loadStats()}
          disabled={loading}
        >
          <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
          Làm mới
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard title="Tổng người dùng" value={stats.overview.totalUsers.toLocaleString("vi-VN")} icon={Users} color="text-[#1a73e8]" change={`${stats.overview.newUsers7d} trong 7 ngày`} isPositive />
        <StatCard title="Doanh thu đã thanh toán" value={formatCurrency(stats.overview.totalRevenue)} icon={CreditCard} color="text-[#34a853]" />
        <StatCard title="Phiên đang hoạt động" value={stats.overview.activeSessions.toLocaleString("vi-VN")} icon={Activity} color="text-[#fbbc04]" />
        <StatCard title="Sự cố 7 ngày" value={(stats.overview.recentFailedEvents + stats.overview.recentRejectedEvents).toLocaleString("vi-VN")} icon={ShieldCheck} color="text-[#ea4335]" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-medium text-[#202124]">Xu hướng 14 ngày</h2>
            <span className="text-xs font-medium text-[#5f6368]">User mới / thanh toán / event</span>
          </div>
          <div className="grid grid-cols-1 gap-4">
            <div className="p-4 rounded bg-white border border-[#dadce0] shadow-sm">
              <div className="flex items-center justify-between mb-4">
                <div>
                  <p className="text-sm font-medium text-[#202124]">Đăng ký mới</p>
                  <p className="text-xs text-[#5f6368]">Số tài khoản tạo mới theo ngày.</p>
                </div>
                <TrendingUp className="text-[#34a853]" size={20} />
              </div>
              <MiniBarChart data={stats.trends} field="users" color="bg-[#34a853]" />
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="p-4 rounded bg-white border border-[#dadce0] shadow-sm">
                <p className="text-sm font-medium text-[#202124] mb-1">Thanh toán thành công</p>
                <p className="text-xs text-[#5f6368] mb-4">Số transaction paid theo ngày.</p>
                <MiniBarChart data={stats.trends} field="paidTransactions" color="bg-[#1a73e8]" />
              </div>
              <div className="p-4 rounded bg-white border border-[#dadce0] shadow-sm">
                <p className="text-sm font-medium text-[#202124] mb-1">Event backend</p>
                <p className="text-xs text-[#5f6368] mb-4">Số AppEvent được ghi nhận.</p>
                <MiniBarChart data={stats.trends} field="events" color="bg-[#fbbc04]" />
              </div>
            </div>
          </div>
        </div>

        <div className="space-y-4">
          <h2 className="text-lg font-medium text-[#202124]">Phân bổ & sức khỏe</h2>
          <div className="p-4 rounded bg-white border border-[#dadce0] shadow-sm space-y-6">
            <div>
              <div className="flex justify-between mb-2 text-sm font-medium">
                <span className="text-[#5f6368]">Pro users</span>
                <span className="text-[#202124]">{planPercent}%</span>
              </div>
              <div className="h-2 rounded-full bg-[#f1f3f4] overflow-hidden">
                <div className="h-full rounded-full bg-[#1a73e8]" style={{ width: `${planPercent}%` }} />
              </div>
              <div className="mt-4 grid grid-cols-2 gap-3 text-sm">
                <div className="rounded border border-[#dadce0] p-3">
                  <p className="text-xs text-[#5f6368] mb-1">Pro</p>
                  <p className="text-lg text-[#202124] font-medium">{stats.overview.proUsers}</p>
                </div>
                <div className="rounded border border-[#dadce0] bg-[#f8f9fa] p-3">
                  <p className="text-xs text-[#5f6368] mb-1">Free</p>
                  <p className="text-lg text-[#202124] font-medium">{stats.overview.freeUsers}</p>
                </div>
              </div>
            </div>
            <div className="border-t border-[#dadce0] pt-4 space-y-3">
              <div className="flex justify-between text-sm"><span className="text-[#5f6368]">Admin accounts</span><span className="font-medium text-[#202124]">{stats.overview.adminUsers}</span></div>
              <div className="flex justify-between text-sm"><span className="text-[#5f6368]">User mới 30 ngày</span><span className="font-medium text-[#202124]">{stats.overview.newUsers30d}</span></div>
              <div className="flex justify-between text-sm"><span className="text-[#5f6368]">Paid transactions</span><span className="font-medium text-[#34a853]">{stats.overview.paidTransactions}</span></div>
              <div className="flex justify-between text-sm"><span className="text-[#5f6368]">Pending / Failed</span><span className="font-medium text-[#b06000]">{stats.overview.pendingTransactions} / <span className="text-[#c5221f]">{stats.overview.failedTransactions}</span></span></div>
            </div>
            <div className="border-t border-[#dadce0] pt-4">
              <div className="flex items-center gap-2">
                <div className={`w-2 h-2 rounded-full ${stats.systemHealth === "Healthy" ? "bg-[#34a853]" : "bg-[#fbbc04]"}`} />
                <span className="text-sm font-medium text-[#202124]">{stats.systemHealth}</span>
              </div>
              <p className="mt-2 text-xs text-[#5f6368]">Dựa trên event failure/rejected trong 7 ngày gần nhất.</p>
            </div>
          </div>
        </div>
      </div>

      <div className="p-4 rounded bg-white border border-[#dadce0] shadow-sm">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h2 className="text-lg font-medium text-[#202124]">Hoạt động backend gần đây</h2>
            <p className="text-xs text-[#5f6368] mt-1">Event đã được sanitize, không chứa token/prompt/raw payload.</p>
          </div>
          <BarChart3 className="text-[#5f6368]" size={20} />
        </div>
        <div className="overflow-x-auto rounded border border-[#dadce0]">
          <table className="w-full min-w-[900px] border-collapse text-left text-sm">
            <thead className="bg-[#f8f9fa] border-b border-[#dadce0]">
              <tr>
                <th className="px-4 py-3 font-medium text-[#5f6368]">Thời gian</th>
                <th className="px-4 py-3 font-medium text-[#5f6368]">Hoạt động</th>
                <th className="px-4 py-3 font-medium text-[#5f6368]">API</th>
                <th className="px-4 py-3 font-medium text-[#5f6368]">Người thực hiện</th>
                <th className="px-4 py-3 font-medium text-[#5f6368]">Kết quả</th>
                <th className="px-4 py-3 font-medium text-[#5f6368]">Khu vực</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[#dadce0]">
              {stats.recentEvents.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-[#5f6368]">Chưa có hoạt động nào được ghi nhận.</td>
                </tr>
              ) : pagedRecentEvents.map((event) => (
                <tr key={event.id} className="hover:bg-[#f8f9fa] transition-colors">
                  <td className="whitespace-nowrap px-4 py-3 text-[#5f6368]">{formatDateTime(event.createdAt)}</td>
                  <td className="px-4 py-3 font-medium text-[#202124]">{humanEventName(event.eventType)}</td>
                  <td className="px-4 py-3 font-mono text-xs text-[#202124]">{eventEndpoint(event)}</td>
                  <td className="px-4 py-3 text-[#5f6368]">{eventActor(event)}</td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium border ${humanOutcomeClass(event.outcome)}`}>
                      {event.statusCode ? `${humanOutcome(event.outcome)} · Code ${event.statusCode}` : humanOutcome(event.outcome)}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-[#5f6368]">{humanSource(event.source)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {stats.recentEvents.length > recentEventsPageSize && (
          <div className="mt-4 flex flex-col gap-3 border-t border-[#dadce0] pt-4 sm:flex-row sm:items-center sm:justify-between">
            <p className="text-sm text-[#5f6368]">Trang {recentEventsPage} / {recentEventsTotalPages} · {stats.recentEvents.length} event gần đây</p>
            <div className="flex items-center gap-2">
              <button
                onClick={() => setRecentEventsPage((current) => Math.max(current - 1, 1))}
                disabled={recentEventsPage <= 1 || loading}
                className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#3c4043] hover:bg-[#f8f9fa] disabled:opacity-40"
              >
                <ChevronLeft size={16} />
                Trước
              </button>
              <button
                onClick={() => setRecentEventsPage((current) => Math.min(current + 1, recentEventsTotalPages))}
                disabled={recentEventsPage >= recentEventsTotalPages || loading}
                className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-3 py-2 text-sm font-medium text-[#3c4043] hover:bg-[#f8f9fa] disabled:opacity-40"
              >
                Sau
                <ChevronRight size={16} />
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
