"use client";

import React, { useEffect, useState } from "react";
import { Shield, Zap, Lock, Unlock, Save, Loader2, Plus, Trash2 } from "lucide-react";

export default function CapabilitiesManagement() {
  const [capabilities, setCapabilities] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    fetchCapabilities();
  }, []);

  const fetchCapabilities = async () => {
    try {
      const res = await fetch("/api/admin/capabilities");
      const data = await res.json();
      setCapabilities(data);
      setLoading(false);
    } catch (error) {
      setLoading(false);
    }
  };

  const handleTogglePro = async (key: string, isProOnly: boolean) => {
    const item = capabilities.find(c => c.key === key);
    await updateCapability({ ...item, isProOnly });
  };

  const handleToggleEnabled = async (key: string, isEnabled: boolean) => {
    const item = capabilities.find(c => c.key === key);
    await updateCapability({ ...item, isEnabled });
  };

  const updateCapability = async (data: any) => {
    setSaving(true);
    try {
      await fetch("/api/admin/capabilities", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(data)
      });
      await fetchCapabilities();
    } finally {
      setSaving(false);
    }
  };

  const initDefaultCapabilities = async () => {
    const defaults = [
      { key: "talk_connection", name: "Gemini Live (Talk)", description: "Sử dụng Gemini AI trực tiếp từ notch", isProOnly: true, isEnabled: true },
      { key: "focus_pomodoro", name: "Focus Mode (Pomodoro)", description: "Cài đặt Pomodoro nâng cao", isProOnly: false, isEnabled: true },
      { key: "focus_website_blocklist", name: "Website Blocking", description: "Chặn trang web gây xao nhãng", isProOnly: false, isEnabled: true },
      { key: "media_controls", name: "Media Controls", description: "Điều khiển nhạc trên notch", isProOnly: false, isEnabled: true },
      { key: "browser_bridge", name: "Browser Bridge", description: "Kết nối ứng dụng với trình duyệt", isProOnly: false, isEnabled: true },
    ];

    for (const cap of defaults) {
      await updateCapability(cap);
    }
  };

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
          <h1 className="text-3xl font-bold tracking-tight">Quản lý tính năng (Capabilities)</h1>
          <p className="text-[var(--muted)] mt-1">Phân quyền tính năng cho gói Pro và Free.</p>
        </div>
        <div className="flex gap-3">
          {capabilities.length === 0 && (
            <button className="portal-button" onClick={initDefaultCapabilities}>
              Khởi tạo mặc định
            </button>
          )}
          <button className="portal-button-ghost">
            <Plus size={18} /> Thêm tính năng
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6">
        {capabilities.map((cap) => (
          <div key={cap.key} className="p-8 rounded-[32px] border border-[var(--border)] bg-white hover:shadow-md transition-all">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
              <div className="flex items-center gap-4">
                <div className={`w-12 h-12 rounded-2xl flex items-center justify-center ${cap.isProOnly ? 'bg-purple-100 text-purple-600' : 'bg-blue-100 text-blue-600'}`}>
                  {cap.isProOnly ? <Lock size={24} /> : <Unlock size={24} />}
                </div>
                <div>
                  <h3 className="text-xl font-bold">{cap.name}</h3>
                  <p className="text-sm text-[var(--muted)]">{cap.description}</p>
                  <code className="text-[10px] bg-slate-100 px-2 py-0.5 rounded mt-1 inline-block text-slate-500">{cap.key}</code>
                </div>
              </div>

              <div className="flex items-center gap-8">
                <div className="flex flex-col gap-2">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--muted)]">Quyền hạn</span>
                  <div className="flex p-1 bg-[var(--surface-soft)] rounded-xl border border-[var(--border)]">
                    <button 
                      onClick={() => handleTogglePro(cap.key, false)}
                      className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all ${!cap.isProOnly ? 'bg-white shadow-sm text-blue-600' : 'text-[var(--muted)]'}`}
                    >
                      Free
                    </button>
                    <button 
                      onClick={() => handleTogglePro(cap.key, true)}
                      className={`px-4 py-1.5 rounded-lg text-xs font-bold transition-all ${cap.isProOnly ? 'bg-white shadow-sm text-purple-600' : 'text-[var(--muted)]'}`}
                    >
                      Pro Only
                    </button>
                  </div>
                </div>

                <div className="flex flex-col gap-2">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--muted)]">Trạng thái</span>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input 
                      type="checkbox" 
                      className="sr-only peer" 
                      checked={cap.isEnabled}
                      onChange={(e) => handleToggleEnabled(cap.key, e.target.checked)}
                    />
                    <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-[var(--green)]"></div>
                  </label>
                </div>

                <button className="p-3 text-red-500 hover:bg-red-50 rounded-2xl transition-colors">
                  <Trash2 size={20} />
                </button>
              </div>
            </div>
          </div>
        ))}

        {capabilities.length === 0 && (
          <div className="p-20 text-center border-2 border-dashed border-[var(--border)] rounded-[48px]">
            <Zap size={48} className="mx-auto text-[var(--border-strong)] mb-4" />
            <p className="text-[var(--muted)] font-medium">Chưa có tính năng nào được cấu hình.</p>
          </div>
        )}
      </div>

      {saving && (
        <div className="fixed bottom-8 right-8 bg-white border border-[var(--border)] shadow-2xl rounded-2xl px-6 py-4 flex items-center gap-3 animate-bounce">
          <Loader2 className="animate-spin text-[var(--accent)]" size={20} />
          <span className="font-bold text-sm">Đang lưu thay đổi...</span>
        </div>
      )}
    </div>
  );
}
