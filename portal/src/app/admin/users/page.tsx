"use client";

import React, { useEffect, useState } from "react";
import { Search, Filter, MoreVertical, CheckCircle2, XCircle, Clock, Loader2 } from "lucide-react";

export default function UsersManagement() {
  const [users, setUsers] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch("/api/admin/users")
      .then(res => res.json())
      .then(data => {
        setUsers(data);
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
          <h1 className="text-3xl font-bold tracking-tight">Quản lý người dùng</h1>
          <p className="text-[var(--muted)] mt-1">Dữ liệu từ cơ sở dữ liệu ({users.length} người dùng mới nhất).</p>
        </div>
      </div>

      <div className="overflow-hidden border border-[var(--border)] rounded-3xl bg-white">
        <table className="w-full text-left border-collapse">
          <thead>
            <tr className="bg-[var(--surface-soft)] border-b border-[var(--border)]">
              <th className="px-6 py-4 text-sm font-bold text-[var(--muted-strong)] uppercase tracking-wider">Người dùng</th>
              <th className="px-6 py-4 text-sm font-bold text-[var(--muted-strong)] uppercase tracking-wider">Gói cước</th>
              <th className="px-6 py-4 text-sm font-bold text-[var(--muted-strong)] uppercase tracking-wider">Quyền hạn</th>
              <th className="px-6 py-4 text-sm font-bold text-[var(--muted-strong)] uppercase tracking-wider">Ngày tham gia</th>
              <th className="px-6 py-4 text-sm font-bold text-[var(--muted-strong)] uppercase tracking-wider text-right">Thao tác</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--border)]">
            {users.map((user) => (
              <tr key={user.id} className="hover:bg-[var(--surface-soft)] transition-colors group">
                <td className="px-6 py-5">
                  <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-slate-100 flex items-center justify-center font-bold text-slate-600">
                      {user.name?.[0] || user.email?.[0] || "?"}
                    </div>
                    <div>
                      <p className="font-bold text-[var(--foreground)]">{user.name || "N/A"}</p>
                      <p className="text-xs text-[var(--muted)]">{user.email}</p>
                    </div>
                  </div>
                </td>
                <td className="px-6 py-5">
                  <span className={`px-3 py-1 rounded-full text-xs font-bold ${
                    user.isPro ? 'bg-purple-100 text-purple-700' : 'bg-slate-100 text-slate-600'
                  }`}>
                    {user.isPro ? "Pro" : "Free"}
                  </span>
                </td>
                <td className="px-6 py-5">
                  <span className={`text-sm font-medium ${user.isAdmin ? 'text-red-600' : 'text-slate-600'}`}>
                    {user.isAdmin ? "Admin" : "User"}
                  </span>
                </td>
                <td className="px-6 py-5">
                  <span className="text-sm text-[var(--muted-strong)]">
                    {new Date(user.createdAt).toLocaleDateString("vi-VN")}
                  </span>
                </td>
                <td className="px-6 py-5 text-right">
                  <button className="p-2 hover:bg-white rounded-lg transition-colors border border-transparent hover:border-[var(--border)]">
                    <MoreVertical size={18} className="text-[var(--muted)]" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
