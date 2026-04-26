import React from "react";
import { Save, Shield, Bell, Zap, Globe, Database } from "lucide-react";

export default function AdminSettings() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Cài đặt hệ thống</h1>
        <p className="text-[var(--muted)] mt-1">Cấu hình các tham số vận hành cho toàn bộ ứng dụng Notch.</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
        <div className="md:col-span-2 space-y-6">
          {/* General Settings */}
          <section className="p-8 rounded-[32px] border border-[var(--border)] bg-white space-y-6">
            <div className="flex items-center gap-3 mb-2">
              <Zap size={20} className="text-[var(--accent)]" />
              <h2 className="text-xl font-bold">Tính năng & Trải nghiệm</h2>
            </div>
            
            <div className="space-y-4">
              <div className="flex items-center justify-between py-2">
                <div>
                  <p className="font-bold">Chế độ Bảo trì (Maintenance)</p>
                  <p className="text-sm text-[var(--muted)]">Tạm dừng quyền truy cập vào cổng thông tin.</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-[var(--accent)]"></div>
                </label>
              </div>
              
              <div className="flex items-center justify-between py-2 border-t border-[var(--border)]">
                <div>
                  <p className="font-bold">Thử nghiệm Gemini Nano</p>
                  <p className="text-sm text-[var(--muted)]">Cho phép người dùng dùng thử các tính năng AI cục bộ.</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" defaultChecked />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-[var(--accent)]"></div>
                </label>
              </div>
            </div>
          </section>

          {/* API Config */}
          <section className="p-8 rounded-[32px] border border-[var(--border)] bg-white space-y-6">
            <div className="flex items-center gap-3 mb-2">
              <Globe size={20} className="text-purple-600" />
              <h2 className="text-xl font-bold">Cấu hình API</h2>
            </div>
            
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-bold mb-2">API Endpoint chính</label>
                <input 
                  type="text" 
                  defaultValue="https://api.notch.pro/v1" 
                  className="w-full px-4 py-3 border border-[var(--border)] rounded-2xl focus:ring-2 focus:ring-[var(--accent)] focus:outline-none"
                />
              </div>
              <div>
                <label className="block text-sm font-bold mb-2">Thời gian hết hạn Token (phút)</label>
                <input 
                  type="number" 
                  defaultValue="1440" 
                  className="w-full px-4 py-3 border border-[var(--border)] rounded-2xl focus:ring-2 focus:ring-[var(--accent)] focus:outline-none"
                />
              </div>
            </div>
          </section>
        </div>

        <div className="space-y-6">
          <div className="p-8 rounded-[32px] border border-[var(--border)] bg-[var(--surface-soft)] space-y-4">
            <h3 className="font-bold text-lg">Lưu thay đổi</h3>
            <p className="text-sm text-[var(--muted)]">Hãy cẩn thận khi thay đổi các thiết lập hệ thống, điều này ảnh hưởng đến toàn bộ người dùng.</p>
            <button className="w-full portal-button flex items-center justify-center gap-2">
              <Save size={18} />
              Lưu tất cả
            </button>
          </div>

          <div className="p-8 rounded-[32px] border border-[var(--border)] bg-white space-y-4">
            <div className="flex items-center gap-2 text-amber-600">
              <Database size={18} />
              <h3 className="font-bold text-sm uppercase tracking-wider">Cơ sở dữ liệu</h3>
            </div>
            <div className="space-y-2">
              <p className="text-xs text-[var(--muted)] font-medium">Bản sao lưu cuối: Hôm nay, 04:00 AM</p>
              <button className="text-[var(--accent)] text-sm font-bold hover:underline">Sao lưu ngay</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
