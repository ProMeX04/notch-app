"use client";

import React, { useEffect, useState } from "react";
import { Shield, Zap, Lock, Unlock, Save, Loader2, Plus, Trash2, ChevronRight, Info } from "lucide-react";

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
      { key: "panel_shelf", name: "Shelf", description: "Lưu tạm file, text và link trong notch", isProOnly: true, isEnabled: true },
    ];

    for (const cap of defaults) {
      await updateCapability(cap);
    }
  };

  if (loading) {
    return (
      <div className="h-full w-full flex items-center justify-center">
        <Loader2 className="animate-spin text-indigo-500" size={48} />
      </div>
    );
  }

  return (
    <div className="space-y-8 max-w-5xl mx-auto">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight text-slate-900">Quyền hạn hệ thống</h1>
          <p className="text-slate-500 mt-1">Quản lý các tính năng Pro và quyền truy cập của người dùng.</p>
        </div>
        <div className="flex gap-3">
          {capabilities.length === 0 && (
            <button className="px-4 py-2 rounded-xl text-sm font-semibold text-white bg-indigo-600 hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-500/20" onClick={initDefaultCapabilities}>
              Khởi tạo mặc định
            </button>
          )}
          <button className="px-4 py-2 rounded-xl text-sm font-semibold text-slate-600 bg-white/50 border border-slate-200 hover:bg-white/80 transition-all flex items-center gap-2">
            <Plus size={18} /> Thêm tính năng
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 gap-6">
        {capabilities.map((cap) => (
          <div key={cap.key} className="p-6 rounded-[32px] bg-white/60 border border-white/80 shadow-sm backdrop-blur-md hover:shadow-md transition-all group">
            <div className="flex flex-col md:flex-row md:items-center justify-between gap-8">
              <div className="flex items-center gap-5">
                <div className={`w-14 h-14 rounded-2xl flex items-center justify-center shadow-inner transition-transform group-hover:scale-105 duration-300 ${cap.isProOnly ? 'bg-gradient-to-br from-purple-500 to-indigo-600 text-white' : 'bg-gradient-to-br from-blue-500 to-cyan-500 text-white'}`}>
                  {cap.isProOnly ? <Lock size={28} /> : <Unlock size={28} />}
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h3 className="text-xl font-bold text-slate-800">{cap.name}</h3>
                    {cap.isProOnly && (
                      <span className="px-2 py-0.5 rounded-full bg-purple-100 text-purple-600 text-[9px] font-bold uppercase tracking-wider border border-purple-200">Pro</span>
                    )}
                  </div>
                  <p className="text-sm text-slate-500 mt-1">{cap.description}</p>
                  <div className="flex items-center gap-2 mt-2">
                    <code className="text-[10px] bg-slate-100 px-2 py-0.5 rounded font-mono text-slate-400">{cap.key}</code>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-10">
                <div className="flex flex-col gap-3">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Gói áp dụng</span>
                  <div className="glass-tabs">
                    <button 
                      onClick={() => handleTogglePro(cap.key, false)}
                      className={`glass-tab-btn ${!cap.isProOnly ? 'glass-tab-btn-active' : ''}`}
                    >
                      Free Plan
                    </button>
                    <button 
                      onClick={() => handleTogglePro(cap.key, true)}
                      className={`glass-tab-btn ${cap.isProOnly ? 'glass-tab-btn-active' : ''}`}
                    >
                      Pro Exclusive
                    </button>
                  </div>
                </div>

                <div className="flex flex-col gap-3 items-center">
                  <span className="text-[10px] font-bold uppercase tracking-wider text-slate-400">Kích hoạt</span>
                  <label className="premium-switch">
                    <input 
                      type="checkbox" 
                      checked={cap.isEnabled}
                      onChange={(e) => handleToggleEnabled(cap.key, e.target.checked)}
                    />
                    <span className="slider"></span>
                  </label>
                </div>

                <div className="flex items-center border-l border-slate-100 pl-6 gap-2">
                  <button className="p-3 text-slate-400 hover:text-red-500 hover:bg-red-50 rounded-2xl transition-all">
                    <Trash2 size={20} />
                  </button>
                  <button className="p-3 text-slate-400 hover:text-indigo-500 hover:bg-indigo-50 rounded-2xl transition-all">
                    <ChevronRight size={20} />
                  </button>
                </div>
              </div>
            </div>
          </div>
        ))}

        {capabilities.length === 0 && (
          <div className="p-20 text-center border-2 border-dashed border-slate-200 rounded-[48px] bg-slate-50/50">
            <div className="w-16 h-16 bg-white rounded-2xl shadow-sm flex items-center justify-center mx-auto mb-4">
              <Zap size={32} className="text-slate-300" />
            </div>
            <p className="text-slate-400 font-medium">Chưa có tính năng nào được cấu hình trong hệ thống.</p>
          </div>
        )}
      </div>

      <div className="p-6 rounded-[32px] bg-indigo-50 border border-indigo-100 flex items-start gap-4">
        <div className="p-2 bg-indigo-500 rounded-lg text-white">
          <Info size={20} />
        </div>
        <div>
          <h4 className="text-sm font-bold text-indigo-900">Lưu ý cấu hình</h4>
          <p className="text-xs text-indigo-700 mt-1 leading-relaxed">
            Việc thay đổi trạng thái "Pro Only" sẽ ảnh hưởng ngay lập tức đến quyền truy cập của người dùng trên toàn bộ nền tảng (macOS App và Web Portal). 
            Hãy chắc chắn rằng các tính năng Pro được kiểm tra kỹ lưỡng trước khi kích hoạt.
          </p>
        </div>
      </div>

      {saving && (
        <div className="fixed bottom-8 right-8 bg-slate-900 text-white shadow-2xl rounded-2xl px-6 py-4 flex items-center gap-3 animate-in fade-in slide-in-from-bottom-4 duration-300 z-[100]">
          <Loader2 className="animate-spin text-indigo-400" size={20} />
          <span className="font-bold text-sm">Đang đồng bộ quyền hạn...</span>
        </div>
      )}
    </div>
  );
}
