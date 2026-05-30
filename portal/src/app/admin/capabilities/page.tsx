"use client";

import React, { useEffect, useMemo, useState } from "react";
import { CheckCircle2, Loader2, RefreshCw, ShieldCheck, SlidersHorizontal, Sparkles } from "lucide-react";

type Capability = {
  key: string;
  name: string;
  description: string;
  isProOnly: boolean;
  isEnabled: boolean;
};

function Toggle({ checked, onChange, disabled }: { checked: boolean; onChange: (checked: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      disabled={disabled}
      onClick={() => onChange(!checked)}
      className={`relative inline-flex h-4 w-7 items-center rounded-full border transition-colors disabled:opacity-40 cursor-pointer focus:outline-none focus-visible:ring-2 focus-visible:ring-[#1a73e8] focus-visible:ring-offset-1 ${checked ? "border-[#1a73e8] bg-[#1a73e8]" : "border-[#dadce0] bg-[#e8eaed]"}`}
    >
      <span className={`h-3 w-3 rounded-full bg-white shadow-sm transition-transform ${checked ? "translate-x-[13px]" : "translate-x-0.5"}`} />
    </button>
  );
}

function accessLabel(capability: Capability) {
  return capability.isProOnly ? "Chỉ gói Pro" : "Mọi người dùng";
}

export default function CapabilitiesManagement() {
  const [capabilities, setCapabilities] = useState<Capability[]>([]);
  const [loading, setLoading] = useState(true);
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const enabledCount = useMemo(() => capabilities.filter((capability) => capability.isEnabled).length, [capabilities]);
  const proCount = useMemo(() => capabilities.filter((capability) => capability.isProOnly).length, [capabilities]);

  const fetchCapabilities = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch("/api/admin/capabilities");
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không tải được quyền truy cập");
      setCapabilities(data);
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : "Không tải được quyền truy cập");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void fetchCapabilities();
  }, []);

  const updateCapability = async (capability: Capability) => {
    setSavingKey(capability.key);
    setError(null);
    try {
      const response = await fetch("/api/admin/capabilities", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(capability),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không lưu được thay đổi");
      setCapabilities((current) => current.map((item) => (item.key === capability.key ? data : item)));
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Không lưu được thay đổi");
    } finally {
      setSavingKey(null);
    }
  };

  const initDefaultCapabilities = async () => {
    setSavingKey("restore_defaults");
    setError(null);
    try {
      const response = await fetch("/api/admin/capabilities", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "restore_defaults" }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data?.error || "Không khôi phục được cấu hình mặc định");
      setCapabilities(data);
    } catch (restoreError) {
      setError(restoreError instanceof Error ? restoreError.message : "Không khôi phục được cấu hình mặc định");
    } finally {
      setSavingKey(null);
    }
  };

  if (loading && capabilities.length === 0) {
    return (
      <div className="h-full w-full flex items-center justify-center bg-[#f8f9fa]">
        <Loader2 className="animate-spin text-[#1a73e8]" size={48} />
      </div>
    );
  }

  return (
    <div className="space-y-6 bg-[#f8f9fa] font-sans text-[#202124]">
      <div className="flex flex-col items-start justify-between gap-4 border-b border-[#dadce0] pb-4 sm:flex-row sm:items-center">
        <div className="min-w-0">
          <h1 className="text-2xl font-normal tracking-tight text-[#202124]">Quyền truy cập</h1>
          <p className="mt-1 text-sm text-[#5f6368]">Bật tắt tính năng và chọn nhóm người dùng được phép sử dụng.</p>
        </div>
        <div className="flex w-full flex-col gap-2 sm:w-auto sm:flex-row sm:items-center">
          <button onClick={initDefaultCapabilities} className="inline-flex items-center justify-center gap-2 rounded border border-[#1a73e8] bg-[#1a73e8] px-4 py-2 text-sm font-medium text-white hover:bg-[#1557b0]">
              <Sparkles size={16} />
              Khôi phục mặc định
            </button>
          <button onClick={fetchCapabilities} disabled={loading} className="inline-flex items-center justify-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] disabled:opacity-60">
            <RefreshCw size={16} className={loading ? "animate-spin" : ""} />
            Làm mới
          </button>
        </div>
      </div>

      {error && <div className="rounded border border-[#fad2cf] bg-[#fce8e6] p-4 text-sm font-medium text-[#c5221f]">{error}</div>}

      <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Tổng tính năng</p>
          <p className="mt-2 text-2xl font-normal text-[#202124]">{capabilities.length}</p>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Đang bật</p>
          <p className="mt-2 text-2xl font-normal text-[#137333]">{enabledCount}</p>
        </div>
        <div className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
          <p className="text-xs font-medium text-[#5f6368]">Dành cho Pro</p>
          <p className="mt-2 text-2xl font-normal text-[#1967d2]">{proCount}</p>
        </div>
      </div>

      <div className="rounded border border-[#dadce0] bg-white shadow-sm">
        <div className="flex items-start justify-between gap-3 border-b border-[#dadce0] px-4 py-3 sm:items-center">
          <div className="flex min-w-0 items-start gap-3 sm:items-center">
            <ShieldCheck className="text-[#1a73e8]" size={20} />
            <div>
              <h2 className="text-base font-medium text-[#202124]">Danh sách tính năng</h2>
              <p className="text-xs text-[#5f6368]">Thay đổi có hiệu lực ngay trên ứng dụng và portal.</p>
            </div>
          </div>
          {savingKey && <Loader2 className="animate-spin text-[#1a73e8]" size={18} />}
        </div>

        {capabilities.length === 0 ? (
          <div className="p-10 text-center">
            <SlidersHorizontal className="mx-auto mb-3 text-[#5f6368]" size={32} />
            <p className="text-sm font-medium text-[#202124]">Chưa có tính năng nào được cấu hình.</p>
            <p className="mt-1 text-sm text-[#5f6368]">Tạo cấu hình mặc định để bắt đầu quản lý quyền truy cập.</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="admin-console-table min-w-[900px]">
              <thead>
                <tr>
                  <th>Tính năng</th>
                  <th>Người được dùng</th>
                  <th>Trạng thái</th>
                  <th className="text-right">Bật/Tắt</th>
                </tr>
              </thead>
              <tbody>
                {capabilities.map((capability) => (
                  <tr key={capability.key}>
                    <td>
                      <div className="flex items-start gap-3">
                        <div className={`mt-0.5 rounded border p-2 ${capability.isProOnly ? "border-[#d7aefb] bg-[#f3e8fd] text-[#8430ce]" : "border-[#d2e3fc] bg-[#e8f0fe] text-[#1967d2]"}`}>
                          {capability.isProOnly ? <Sparkles size={16} /> : <CheckCircle2 size={16} />}
                        </div>
                        <div>
                          <p className="font-medium text-[#202124]">{capability.name}</p>
                          <p className="mt-1 text-sm text-[#5f6368]">{capability.description}</p>
                        </div>
                      </div>
                    </td>
                    <td>
                      <div className="inline-flex rounded border border-[#dadce0] bg-[#f8f9fa] p-1">
                        <button onClick={() => updateCapability({ ...capability, isProOnly: false })} disabled={savingKey === capability.key} className={`rounded px-3 py-1.5 text-xs font-medium ${!capability.isProOnly ? "bg-white text-[#1a73e8] shadow-sm" : "text-[#5f6368] hover:text-[#202124]"}`}>Mọi người dùng</button>
                        <button onClick={() => updateCapability({ ...capability, isProOnly: true })} disabled={savingKey === capability.key} className={`rounded px-3 py-1.5 text-xs font-medium ${capability.isProOnly ? "bg-white text-[#1a73e8] shadow-sm" : "text-[#5f6368] hover:text-[#202124]"}`}>Chỉ Pro</button>
                      </div>
                    </td>
                    <td>
                      <span className={`admin-pill ${capability.isEnabled ? "admin-pill-green" : "admin-pill-gray"}`}>{capability.isEnabled ? "Đang bật" : "Đang tắt"}</span>
                      <p className="mt-1 text-xs text-[#5f6368]">{accessLabel(capability)}</p>
                    </td>
                    <td className="text-right">
                      <Toggle checked={capability.isEnabled} disabled={savingKey === capability.key} onChange={(checked) => updateCapability({ ...capability, isEnabled: checked })} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
