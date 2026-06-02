import { useState } from 'react'
import { Bell, CheckCircle2, Database, LifeBuoy, Loader2, LockKeyhole, LogOut, Save, Sparkles } from 'lucide-react'

import { apiClient } from '@/api/client'

const settingGroups = [
  {
    title: 'Trải nghiệm người dùng',
    description: 'Các thiết lập ảnh hưởng trực tiếp đến cách người dùng dùng Notch.',
    icon: Sparkles,
    items: [
      { label: 'Cho phép dùng thử tính năng AI mới', description: 'Người dùng có thể thấy các tính năng thử nghiệm khi đội ngũ đã bật phát hành.', enabled: true, key: 'feature_preview' },
      { label: 'Hiển thị thông báo sản phẩm', description: 'Gửi thông báo trong portal khi có thay đổi quan trọng về gói hoặc tính năng.', enabled: true, key: 'product_notifications' },
    ],
  },
  {
    title: 'Bảo mật tài khoản',
    description: 'Kiểm soát đăng nhập, phiên sử dụng và thiết bị tin cậy.',
    icon: LockKeyhole,
    items: [
      { label: 'Yêu cầu phiên đăng nhập an toàn', description: 'Người dùng cần đăng nhập lại khi phiên cũ không còn hợp lệ.', enabled: true, key: 'secure_session' },
      { label: 'Theo dõi thiết bị đáng tin cậy', description: 'Ghi nhận thiết bị đã xác minh để admin dễ kiểm tra hoạt động bất thường.', enabled: true, key: 'device_tracking' },
    ],
  },
  {
    title: 'Thông báo vận hành',
    description: 'Giúp admin nhận biết vấn đề quan trọng mà không cần xem dữ liệu kỹ thuật.',
    icon: Bell,
    items: [
      { label: 'Cảnh báo thanh toán lỗi', description: 'Đánh dấu các giao dịch không thành công để đội ngũ hỗ trợ kiểm tra.', enabled: true, key: 'payment_error_alerts' },
      { label: 'Cảnh báo hoạt động bị từ chối', description: 'Theo dõi khi người dùng bị chặn do chưa đủ quyền hoặc phiên hết hạn.', enabled: true, key: 'rejected_alerts' },
    ],
  },
]

const healthItems = [
  { label: 'Đăng nhập và phiên dùng', value: 'Đang hoạt động', tone: 'green' },
  { label: 'Thanh toán', value: 'Sẵn sàng', tone: 'green' },
  { label: 'Ghi nhận hoạt động', value: 'Đã bật', tone: 'blue' },
]

function TogglePreview({ enabled }: { enabled: boolean }) {
  return (
    <div className={`relative h-5 w-9 rounded-full border focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#1a73e8] focus-visible:ring-offset-2 ${enabled ? 'border-[#1a73e8] bg-[#1a73e8]' : 'border-[#dadce0] bg-[#f1f3f4]'}`}>
      <span className={`absolute top-0.5 h-3.5 w-3.5 rounded-full bg-white shadow-sm ${enabled ? 'translate-x-[18px]' : 'translate-x-0.5'}`} />
    </div>
  )
}

function statusClass(tone: string) {
  if (tone === 'green') return 'admin-pill-green'
  if (tone === 'blue') return 'admin-pill-blue'
  return 'admin-pill-gray'
}

export function AdminSettingsPage() {
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [logoutError, setLogoutError] = useState<string | null>(null)
  const [loggingOut, setLoggingOut] = useState(false)

  const handleSave = async () => {
    setSaving(true)
    setSaved(false)
    // Settings are local-only for now; just simulate a save
    await new Promise(resolve => setTimeout(resolve, 600))
    setSaving(false)
    setSaved(true)
    setTimeout(() => setSaved(false), 3000)
  }

  const handleLogout = async () => {
    setLoggingOut(true)
    setLogoutError(null)
    try {
      await apiClient.post('/api/auth/logout')
      window.location.href = '/'
    } catch {
      setLogoutError('Không thể đăng xuất. Vui lòng thử lại.')
      setLoggingOut(false)
    }
  }

  return (
    <div className="space-y-6 bg-[#f8f9fa] font-sans text-[#202124]">
      <div className="flex items-center justify-between gap-4 border-b border-[#dadce0] pb-4">
        <div>
          <h1 className="text-2xl font-normal tracking-tight text-[#202124]">Cài đặt</h1>
          <p className="mt-1 text-sm text-[#5f6368]">Quản lý các lựa chọn vận hành bằng ngôn ngữ dễ hiểu cho đội ngũ hỗ trợ.</p>
        </div>
        <button
          type="button"
          onClick={() => void handleSave()}
          disabled={saving}
          className="inline-flex items-center gap-2 rounded border border-[#dadce0] bg-white px-4 py-2 text-sm font-medium text-[#1a73e8] hover:bg-[#f8f9fa] transition-colors disabled:opacity-60 cursor-pointer"
        >
          {saving ? <Loader2 size={16} className="animate-spin" /> : <Save size={16} />}
          {saving ? 'Đang lưu...' : 'Lưu thay đổi'}
        </button>
      </div>

      {saved && (
        <div className="rounded border border-[#ceead6] bg-[#e6f4ea] p-4 text-sm font-medium text-[#137333] flex items-center gap-2">
          <CheckCircle2 size={16} />
          Đã lưu cài đặt thành công.
        </div>
      )}

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        {/* Left: setting groups */}
        <div className="space-y-4 lg:col-span-2">
          {settingGroups.map(group => {
            const Icon = group.icon
            return (
              <section key={group.title} className="rounded border border-[#dadce0] bg-white shadow-sm">
                <div className="flex items-start gap-3 border-b border-[#dadce0] px-4 py-4">
                  <div className="rounded border border-[#d2e3fc] bg-[#e8f0fe] p-2 text-[#1967d2] shrink-0">
                    <Icon size={18} />
                  </div>
                  <div>
                    <h2 className="text-base font-medium text-[#202124]">{group.title}</h2>
                    <p className="mt-1 text-sm text-[#5f6368]">{group.description}</p>
                  </div>
                </div>
                <div className="divide-y divide-[#e8eaed]">
                  {group.items.map(item => (
                    <div
                      key={item.key}
                      className="flex items-center justify-between gap-6 px-4 py-4"
                    >
                      <div>
                        <p className="text-sm font-medium text-[#202124]">{item.label}</p>
                        <p className="mt-1 text-sm text-[#5f6368]">{item.description}</p>
                      </div>
                      <TogglePreview enabled={item.enabled} />
                    </div>
                  ))}
                </div>
              </section>
            )
          })}
        </div>

        {/* Right: system health, data safety, support, logout */}
        <div className="space-y-4">
          <section className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
            <div className="flex items-center gap-3">
              <div className="rounded border border-[#ceead6] bg-[#e6f4ea] p-2 text-[#137333]">
                <CheckCircle2 size={18} />
              </div>
              <div>
                <h2 className="text-base font-medium text-[#202124]">Tình trạng hệ thống</h2>
                <p className="text-xs text-[#5f6368]">Tóm tắt cho vận hành hằng ngày.</p>
              </div>
            </div>
            <div className="mt-4 space-y-3">
              {healthItems.map(item => (
                <div key={item.label} className="flex items-center justify-between gap-3 rounded border border-[#e8eaed] bg-[#f8f9fa] p-3">
                  <span className="text-sm text-[#5f6368]">{item.label}</span>
                  <span className={`admin-pill ${statusClass(item.tone)}`}>{item.value}</span>
                </div>
              ))}
            </div>
          </section>

          <section className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
            <div className="flex items-center gap-3">
              <div className="rounded border border-[#feefc3] bg-[#fef7e0] p-2 text-[#b06000]">
                <Database size={18} />
              </div>
              <div>
                <h2 className="text-base font-medium text-[#202124]">Dữ liệu an toàn</h2>
                <p className="text-xs text-[#5f6368]">Không hiển thị khóa, token hoặc cấu hình kỹ thuật.</p>
              </div>
            </div>
            <p className="mt-4 text-sm leading-6 text-[#5f6368]">
              Trang này chỉ trình bày các lựa chọn admin có thể hiểu và thao tác. Các thông số nhạy cảm được giữ trong cấu hình máy chủ.
            </p>
          </section>

          <section className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
            <div className="flex items-center gap-3">
              <div className="rounded border border-[#d2e3fc] bg-[#e8f0fe] p-2 text-[#1967d2]">
                <LifeBuoy size={18} />
              </div>
              <div>
                <h2 className="text-base font-medium text-[#202124]">Hỗ trợ</h2>
                <p className="text-xs text-[#5f6368]">Dành cho đội ngũ chăm sóc người dùng.</p>
              </div>
            </div>
            <div className="mt-4 rounded border border-[#e8eaed] bg-[#f8f9fa] p-3 text-sm text-[#5f6368] leading-6">
              Khi có sự cố, hãy kiểm tra trang Tổng quan và chi tiết người dùng trước khi thay đổi quyền truy cập.
            </div>
          </section>

          <section className="rounded border border-[#dadce0] bg-white p-4 shadow-sm">
            <div className="flex items-center gap-3 text-[#5f6368]">
              <LockKeyhole size={18} />
              <div>
                <h2 className="text-base font-medium text-[#202124]">Phiên làm việc</h2>
                <p className="text-xs text-[#5f6368]">Đăng xuất tài khoản admin khỏi portal trên thiết bị này.</p>
              </div>
            </div>
            <div className="mt-4">
              {logoutError && (
                <p className="mb-3 text-sm text-[#c5221f] font-semibold">{logoutError}</p>
              )}
              <button
                type="button"
                onClick={() => void handleLogout()}
                disabled={loggingOut}
                className="inline-flex w-full items-center justify-center gap-2 rounded border border-[#fad2cf] bg-white px-4 py-2 text-sm font-medium text-[#c5221f] transition-colors hover:bg-[#fce8e6] disabled:opacity-60 cursor-pointer"
              >
                {loggingOut ? <Loader2 size={16} className="animate-spin" /> : <LogOut size={16} />}
                {loggingOut ? 'Đang đăng xuất...' : 'Đăng xuất khỏi admin'}
              </button>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}